const std = @import("std");
const c = @import("c.zig");
const status = @import("status.zig");
const Env = @import("Env.zig");
const CallbackInfo = @import("callback_info.zig").CallbackInfo;
const Value = @import("Value.zig");

// User function in a typesafe form for NAPI consumption
pub fn Callback(comptime argc_cap: usize) type {
    return *const fn (Env, CallbackInfo(argc_cap)) anyerror!Value;
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
                e.throwError(@errorName(err), "CallbackInfo initialization failed") catch {};
                return null;
            };
            const result = cb(e, cb_info) catch |err| {
                if (err == error.PendingException) return null;

                if (status.isNapiError(err)) {
                    const error_info = e.getLastErrorInfo() catch {
                        e.throwError(@errorName(err), "NapiError") catch {};
                        return null;
                    };
                    const error_info_status = @as(status.Status, @enumFromInt(error_info.error_code));
                    if (error_info_status == .ok) {
                        e.throwError(@errorName(err), "NapiError") catch {};
                    } else {
                        e.throwError(
                            @tagName(error_info_status),
                            std.mem.span(error_info.error_message),
                        ) catch {};
                    }
                } else {
                    e.throwError(@errorName(err), "ZigError") catch {};
                }
                return null;
            };
            return result.value;
        }
    };
    return wrapper.f;
}
