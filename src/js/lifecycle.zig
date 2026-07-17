const std = @import("std");

/// Refcounted shared state with lifecycle hooks serialized under a mutex.
///
/// Optional `hooks`:
///
/// - `.init = fn (instance: *T, prev_refcount: u32) !void`: called under the
///   lock before the refcount is incremented (`prev_refcount` is 0 for the
///   first holder). On error the refcount is left untouched.
/// - `.cleanup = fn (instance: *T, new_refcount: u32) void`: called under the
///   lock after the refcount is decremented (`new_refcount` is 0 for the last
///   holder).
///
/// Each instantiation owns its own refcount, mutex, and `T` instance.
pub fn SharedResource(comptime T: type, comptime hooks: anytype) type {
    const has_init = @hasField(@TypeOf(hooks), "init");
    const has_cleanup = @hasField(@TypeOf(hooks), "cleanup");

    return struct {
        var mutex: std.Io.Mutex = .init;
        var refcount: u32 = 0;
        var instance: T = undefined;

        /// Returns the refcount before this retain (0 for the first holder).
        pub fn retain() !u32 {
            std.Io.Threaded.mutexLock(&mutex);
            defer std.Io.Threaded.mutexUnlock(&mutex);

            const prev = refcount;
            if (has_init) try hooks.init(&instance, prev);
            refcount += 1;
            return prev;
        }

        pub fn release() void {
            std.Io.Threaded.mutexLock(&mutex);
            defer std.Io.Threaded.mutexUnlock(&mutex);

            std.debug.assert(refcount > 0);
            refcount -= 1;
            if (has_cleanup) hooks.cleanup(&instance, refcount);
        }

        /// Returns the shared instance, or null when no holder is active.
        pub fn get() ?*T {
            std.Io.Threaded.mutexLock(&mutex);
            defer std.Io.Threaded.mutexUnlock(&mutex);

            if (refcount == 0) return null;
            return &instance;
        }
    };
}

test "SharedResource runs init before increment and cleanup after decrement" {
    const Hooks = struct {
        var inits: [2]u32 = undefined;
        var init_count: usize = 0;
        var cleanups: [2]u32 = undefined;
        var cleanup_count: usize = 0;

        fn init(_: *void, prev_refcount: u32) !void {
            inits[init_count] = prev_refcount;
            init_count += 1;
        }
        fn cleanup(_: *void, new_refcount: u32) void {
            cleanups[cleanup_count] = new_refcount;
            cleanup_count += 1;
        }
    };
    const S = SharedResource(void, .{ .init = Hooks.init, .cleanup = Hooks.cleanup });

    try std.testing.expectEqual(@as(u32, 0), try S.retain());
    try std.testing.expectEqual(@as(u32, 1), try S.retain());
    S.release();
    S.release();

    try std.testing.expectEqualSlices(u32, &.{ 0, 1 }, Hooks.inits[0..2]);
    try std.testing.expectEqualSlices(u32, &.{ 1, 0 }, Hooks.cleanups[0..2]);
}

test "SharedResource leaves refcount untouched and skips cleanup when init fails" {
    const Hooks = struct {
        var fail: bool = true;
        var cleanup_count: u32 = 0;

        fn init(_: *void, _: u32) !void {
            if (fail) return error.InitFailed;
        }
        fn cleanup(_: *void, _: u32) void {
            cleanup_count += 1;
        }
    };
    const S = SharedResource(void, .{ .init = Hooks.init, .cleanup = Hooks.cleanup });

    try std.testing.expectError(error.InitFailed, S.retain());
    try std.testing.expect(S.get() == null);
    try std.testing.expectEqual(@as(u32, 0), Hooks.cleanup_count);

    Hooks.fail = false;
    try std.testing.expectEqual(@as(u32, 0), try S.retain());
    S.release();
    try std.testing.expectEqual(@as(u32, 1), Hooks.cleanup_count);
}

test "SharedResource exposes the instance only while retained" {
    const Hooks = struct {
        fn init(instance: *u32, prev_refcount: u32) !void {
            if (prev_refcount == 0) instance.* = 42;
        }
    };
    const S = SharedResource(u32, .{ .init = Hooks.init });

    try std.testing.expect(S.get() == null);
    _ = try S.retain();
    try std.testing.expectEqual(@as(u32, 42), S.get().?.*);
    S.release();
    try std.testing.expect(S.get() == null);
}
