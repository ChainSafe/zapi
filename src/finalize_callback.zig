const std = @import("std");
const c = @import("c.zig");
const Env = @import("Env.zig");

pub fn FinalizeCallback(comptime Data: type, comptime Hint: type) type {
    return *const fn (Env, *Data, ?*Hint) void;
}

pub fn wrapFinalizeCallback(
    comptime Data: type,
    comptime Hint: type,
    comptime finalize_cb: FinalizeCallback(Data, Hint),
) c.napi_finalize {
    const wrapper = struct {
        pub fn f(
            env: c.napi_env,
            data: ?*anyopaque,
            hint: ?*anyopaque,
        ) callconv(.C) void {
            return finalize_cb(
                Env{ .env = env },
                @alignCast(@ptrCast(data)),
                @alignCast(@ptrCast(hint)),
            );
        }
    };
    return wrapper.f;
}
