const std = @import("std");
const c = @import("c.zig");
const Env = @import("Env.zig");

pub fn FinalizeCallback(comptime Data: type) type {
    return *const fn (Env, *Data, ?*anyopaque) void;
}

pub fn wrapFinalizeCallback(
    comptime Data: type,
    comptime finalize_cb: FinalizeCallback(Data),
) c.napi_finalize {
    const wrapper = struct {
        pub fn f(
            env: c.napi_env,
            data: ?*anyopaque,
            hint: ?*anyopaque,
        ) callconv(.C) void {
            if (data == null) return;
            return finalize_cb(
                Env{ .env = env },
                @alignCast(@ptrCast(data)),
                hint,
            );
        }
    };
    return wrapper.f;
}
