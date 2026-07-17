const std = @import("std");
const lifecycle = @import("lifecycle.zig");

const gpa: std.mem.Allocator = std.heap.page_allocator;

const hooks = struct {
    fn init(instance: *std.Io.Threaded, prev_refcount: u32) !void {
        if (prev_refcount == 0) instance.* = std.Io.Threaded.init(gpa, .{});
    }
    fn cleanup(instance: *std.Io.Threaded, new_refcount: u32) void {
        if (new_refcount == 0) instance.deinit();
    }
};

const SharedIo = lifecycle.SharedResource(std.Io.Threaded, .{
    .init = hooks.init,
    .cleanup = hooks.cleanup,
});

/// Retains the shared DSL `std.Io` instance for an active N-API environment.
///
/// Called internally from `js.exportModule(...)` on module registration.
/// The underlying `std.Io.Threaded` is initialized lazily on the first retain
/// and torn down after the last matching `release()`.
pub fn retain() void {
    _ = SharedIo.retain() catch unreachable;
}

/// Releases one active N-API environment's hold on the shared DSL `std.Io`.
///
/// Called internally from the env cleanup hook installed by
/// `js.exportModule(...)`.
pub fn release() void {
    SharedIo.release();
}

/// Returns the shared `std.Io` handle managed by the JS DSL.
///
/// This handle is available during module init/cleanup hooks and while running
/// exported DSL callbacks. It is backed by a lazily initialized
/// `std.Io.Threaded`, retained for as long as at least one N-API environment
/// for the addon is active.
///
/// SAFETY: `js.io()` panics if called before the addon has been registered in a
/// JS environment or after the last environment has been cleaned up.
pub fn io() std.Io {
    const instance = SharedIo.get() orelse
        @panic("js.io() called before DSL module registration or after env cleanup");
    return instance.io();
}

test "shared io retains and releases across env registrations" {
    try std.testing.expect(SharedIo.get() == null);

    retain();
    const a = io();

    retain();
    const b = io();
    try std.testing.expectEqual(a.userdata, b.userdata);

    release();
    _ = io();

    release();
    try std.testing.expect(SharedIo.get() == null);
}
