const c = @import("c.zig");
const Env = @import("Env.zig");
const CallbackInfo = @import("callback_info.zig").CallbackInfo;
const Value = @import("Value.zig");

// User function in a typesafe form for NAPI consumption
pub fn Callback(comptime argc_cap: usize) type {
    return *const fn (Env, CallbackInfo(argc_cap)) Value;
}

pub fn wrapCallback(
    comptime argc_cap: usize,
    comptime cb: Callback(argc_cap),
) c.napi_callback {
    const wrapper = struct {
        pub fn f(
            env: c.napi_env,
            info: c.napi_callback_info,
        ) callconv(.C) c.napi_value {
            const e = Env{ .env = env };
            const cb_info = CallbackInfo(argc_cap).init(env, info) catch |err| {
                e.throwError(@errorName(err), "CallbackInfo initialization failed") catch unreachable;
                return null;
            };
            return cb(e, cb_info).value;
        }
    };
    return wrapper.f;
}
