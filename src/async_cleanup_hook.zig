const std = @import("std");
const c = @import("c.zig").c;

pub fn AsyncCleanupHookCallback(comptime Data: type) type {
    return *const fn (c.napi_async_cleanup_hook_handle, *Data) void;
}

pub fn wrapAsyncCleanupHook(
    comptime Data: type,
    comptime cb: AsyncCleanupHookCallback(Data),
) c.napi_async_cleanup_hook {
    const wrapper = struct {
        fn f(handle: c.napi_async_cleanup_hook_handle, arg: ?*anyopaque) callconv(.c) void {
            if (arg == null) return;
            cb(handle, @ptrCast(@alignCast(arg)));
        }
    };
    return wrapper.f;
}
