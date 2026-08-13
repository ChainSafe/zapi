//! Allocator-backed bytes whose ownership can be transferred to JavaScript.
//! Like other Zig owning values, an OwnedBuffer must not be copied or deinitialized after transfer.

const std = @import("std");
const c = @import("c.zig").c;
const Env = @import("Env.zig");
const Value = @import("Value.zig");

allocator: std.mem.Allocator,
data: []u8,

const OwnedBuffer = @This();

const FinalizerContext = struct {
    allocator: std.mem.Allocator,
    data: []u8,
};

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

/// Releases a buffer that has not been transferred to JavaScript.
pub fn deinit(self: *OwnedBuffer) void {
    self.allocator.free(self.data);
    self.* = undefined;
}

/// Transfers ownership to a JavaScript Buffer.
/// This consumes the buffer even on failure; the caller must not deinitialize it afterwards.
/// On success, JavaScript releases the allocation through the N-API finalizer.
pub fn intoValue(self: OwnedBuffer, env: Env) !Value {
    const allocator = self.allocator;
    const data = self.data;

    if (data.len == 0) {
        defer allocator.free(data);
        return try env.createBuffer(0, null);
    }

    const context = try createFinalizerContext(self);

    return env.createExternalBuffer(data, finalize, context) catch |err| {
        if (err == error.NoExternalBuffersAllowed) {
            defer release(context);
            return try env.createBufferCopy(data, null);
        }
        // Other failures may occur after the finalizer has taken ownership.
        return err;
    };
}

fn createFinalizerContext(self: OwnedBuffer) !*FinalizerContext {
    const context = self.allocator.create(FinalizerContext) catch |err| {
        self.allocator.free(self.data);
        return err;
    };
    context.* = .{
        .allocator = self.allocator,
        .data = self.data,
    };
    return context;
}

fn finalize(
    _: c.napi_env,
    finalize_data: ?*anyopaque,
    finalize_hint: ?*anyopaque,
) callconv(.c) void {
    const context: *FinalizerContext = @ptrCast(@alignCast(finalize_hint orelse unreachable));
    std.debug.assert(finalize_data == @as(?*anyopaque, @ptrCast(context.data.ptr)));
    release(context);
}

fn release(context: *FinalizerContext) void {
    const allocator = context.allocator;
    allocator.free(context.data);
    allocator.destroy(context);
}

test "OwnedBuffer fromSlice owns an independent copy" {
    var source = [_]u8{ 1, 2, 3 };
    var buffer = try OwnedBuffer.fromSlice(std.testing.allocator, &source);
    defer buffer.deinit();

    source[0] = 9;
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, buffer.data);
}

test "OwnedBuffer releases data when finalizer context allocation fails" {
    const data = try std.testing.allocator.dupe(u8, "external");

    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = 0,
    });
    const buffer = OwnedBuffer.fromOwnedSlice(failing_allocator.allocator(), data);

    try std.testing.expectError(error.OutOfMemory, createFinalizerContext(buffer));
    try std.testing.expectEqual(@as(usize, 1), failing_allocator.deallocations);
}
