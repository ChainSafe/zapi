const std = @import("std");
const c = @import("c.zig");

pub fn CleanupHookCallback(comptime Data: type) type {
    return *const fn (*Data) void;
}

pub fn wrapCleanupHook(
    comptime Data: type,
    comptime cb: CleanupHookCallback(Data),
) *const fn (?*anyopaque) callconv(.C) void {
    const wrapper = struct {
        fn f(arg: ?*anyopaque) callconv(.C) void {
            if (arg == null) return;
            cb(@ptrCast(@alignCast(arg)));
        }
    };
    return wrapper.f;
}
