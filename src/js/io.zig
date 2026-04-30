const std = @import("std");

const gpa: std.mem.Allocator = std.heap.page_allocator;

const SpinLock = struct {
    state: std.atomic.Mutex = .unlocked,

    fn lock(self: *SpinLock) void {
        while (!self.state.tryLock()) {
            std.atomic.spinLoopHint();
        }
    }

    fn unlock(self: *SpinLock) void {
        self.state.unlock();
    }
};

const State = struct {
    var mutex: SpinLock = .{};
    var instance: std.Io.Threaded = undefined;
    var initialized: bool = false;
    var refcount: u32 = 0;
};

/// Retains the shared DSL `std.Io` instance for an active N-API environment.
///
/// Called internally from `js.exportModule(...)` on module registration.
/// The underlying `std.Io.Threaded` is initialized lazily on the first retain
/// and torn down after the last matching `release()`.
pub fn retain() void {
    State.mutex.lock();
    defer State.mutex.unlock();

    if (State.refcount == 0) {
        State.instance = std.Io.Threaded.init(gpa, .{});
        State.initialized = true;
    }
    State.refcount += 1;
}

/// Releases one active N-API environment's hold on the shared DSL `std.Io`.
///
/// Called internally from the env cleanup hook installed by
/// `js.exportModule(...)`.
pub fn release() void {
    State.mutex.lock();
    defer State.mutex.unlock();

    std.debug.assert(State.refcount > 0);
    State.refcount -= 1;

    if (State.refcount == 0 and State.initialized) {
        State.instance.deinit();
        State.initialized = false;
    }
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
    State.mutex.lock();
    defer State.mutex.unlock();

    if (!State.initialized) {
        @panic("js.io() called before DSL module registration or after env cleanup");
    }
    return State.instance.io();
}

test "shared io retains and releases across env registrations" {
    try std.testing.expect(!State.initialized);
    try std.testing.expectEqual(@as(u32, 0), State.refcount);

    retain();
    try std.testing.expect(State.initialized);
    try std.testing.expectEqual(@as(u32, 1), State.refcount);
    _ = io();

    retain();
    try std.testing.expectEqual(@as(u32, 2), State.refcount);

    release();
    try std.testing.expect(State.initialized);
    try std.testing.expectEqual(@as(u32, 1), State.refcount);

    release();
    try std.testing.expect(!State.initialized);
    try std.testing.expectEqual(@as(u32, 0), State.refcount);
}
