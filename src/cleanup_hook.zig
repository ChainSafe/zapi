const std = @import("std");
const c = @import("c.zig").c;

pub fn CleanupHookCallback(comptime Data: type) type {
    return *const fn (*Data) void;
}

pub fn wrapCleanupHook(
    comptime Data: type,
    comptime cb: CleanupHookCallback(Data),
) *const fn (?*anyopaque) callconv(.c) void {
    const wrapper = struct {
        fn f(arg: ?*anyopaque) callconv(.c) void {
            if (arg == null) return;
            cb(@ptrCast(@alignCast(arg)));
        }
    };
    return wrapper.f;
}
