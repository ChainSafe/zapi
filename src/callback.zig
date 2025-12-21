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
    // Compute argc by inspecting the function signature.
    // We're counting the number of napi values to allocate for the callback.
    // We need to remove any `Env` or `DataType` parameters.
    // const ptr_info = @typeInfo(@TypeOf(cb));
    // const fn_type_info = @typeInfo(ptr_info.pointer.child);
    // comptime var argc = 0;
    // inline for (fn_type_info.@"fn".params) |param| {
    //     if (param.type.? == Env or param.type.? == DataType) {
    //         // If the parameter is Env or DataType, we don't count it towards argc
    //         continue;
    //     }
    //     argc += 1;
    // }

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
