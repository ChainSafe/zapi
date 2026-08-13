//! Allocator-backed bytes whose ownership can be transferred to JavaScript.
//! Like other Zig owning values, an OwnedBuffer must not be copied while it owns data.

const std = @import("std");
const c = @import("c.zig").c;
const Env = @import("Env.zig");
const Value = @import("Value.zig");

allocator: std.mem.Allocator,
data: []u8,

const OwnedBuffer = @This();

/// Takes ownership of `data`, which must have been allocated by `allocator`.
/// The allocator must remain valid until the buffer is deinitialized or finalized by JavaScript.
pub fn fromOwnedSlice(allocator: std.mem.Allocator, data: []u8) OwnedBuffer {
    return .{
        .allocator = allocator,
        .data = data,
    };
}

/// Copies `data` into a new owned allocation.
pub fn fromSlice(allocator: std.mem.Allocator, data: []const u8) !OwnedBuffer {
    return .fromOwnedSlice(allocator, try allocator.dupe(u8, data));
}

/// Releases data that has not been transferred to JavaScript. This is also
/// safe after a successful transfer, when `data` is empty.
pub fn deinit(self: *OwnedBuffer) void {
    self.allocator.free(self.data);
    self.* = undefined;
}

/// Transfers ownership to a JavaScript Buffer.
///
/// On success, `self.data` is empty and JavaScript releases the original
/// allocation through the Buffer finalizer. Failures before N-API accepts the
/// external memory leave ownership in `self`; failures after ownership may
/// have transferred leave `self.data` empty.
///
/// Unsupported external buffers return `error.NoExternalBuffersAllowed`
/// without a copy fallback. The caller may deinitialize `self` after this
/// function returns.
pub fn intoValue(self: *OwnedBuffer, env: Env) !Value {
    const data = self.data;

    if (data.len == 0) {
        const value = try env.createBuffer(0, null);
        self.allocator.free(data);
        self.data = &.{};
        return value;
    }

    const owner = try moveToHeap(self);

    return env.createExternalBuffer(data, finalize, owner) catch |err| {
        switch (err) {
            error.NoExternalBuffersAllowed,
            error.PendingException,
            error.CannotRunJS,
            => restoreFromHeap(self, owner),
            else => {},
        }
        return err;
    };
}

fn moveToHeap(self: *OwnedBuffer) !*OwnedBuffer {
    const owner = try self.allocator.create(OwnedBuffer);
    owner.* = self.*;
    self.data = &.{};
    return owner;
}

fn restoreFromHeap(self: *OwnedBuffer, owner: *OwnedBuffer) void {
    const allocator = owner.allocator;
    std.debug.assert(self.data.len == 0);
    self.* = owner.*;
    allocator.destroy(owner);
}

fn finalize(
    _: c.napi_env,
    finalize_data: ?*anyopaque,
    finalize_hint: ?*anyopaque,
) callconv(.c) void {
    const owner: *OwnedBuffer = @ptrCast(@alignCast(finalize_hint orelse unreachable));
    std.debug.assert(finalize_data == @as(?*anyopaque, @ptrCast(owner.data.ptr)));
    release(owner);
}

fn release(owner: *OwnedBuffer) void {
    const allocator = owner.allocator;
    allocator.free(owner.data);
    allocator.destroy(owner);
}

test "OwnedBuffer fromSlice owns an independent copy" {
    var source = [_]u8{ 1, 2, 3 };
    var buffer = try OwnedBuffer.fromSlice(std.testing.allocator, &source);
    defer buffer.deinit();

    source[0] = 9;
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, buffer.data);
}

test "OwnedBuffer retains data when moving the owner to the heap fails" {
    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = 1,
    });
    {
        var buffer = try OwnedBuffer.fromSlice(
            failing_allocator.allocator(),
            "external",
        );
        defer buffer.deinit();

        try std.testing.expectError(error.OutOfMemory, moveToHeap(&buffer));
        try std.testing.expectEqualSlices(u8, "external", buffer.data);
        try std.testing.expectEqual(@as(usize, 0), failing_allocator.deallocations);
    }

    try std.testing.expectEqual(@as(usize, 1), failing_allocator.deallocations);
}

test "OwnedBuffer restores ownership from the heap" {
    var buffer = try OwnedBuffer.fromSlice(std.testing.allocator, "external");
    defer buffer.deinit();

    const owner = try moveToHeap(&buffer);
    const source_is_empty = buffer.data.len == 0;

    restoreFromHeap(&buffer, owner);

    try std.testing.expect(source_is_empty);
    try std.testing.expectEqualSlices(u8, "external", buffer.data);
}
