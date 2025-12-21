const c = @import("c.zig");
const status = @import("status.zig");
const NapiError = @import("status.zig").NapiError;
const Value = @import("Value.zig");

pub fn CallbackInfo(comptime argc_cap: usize) type {
    return struct {
        env: c.napi_env,
        args: [argc_cap]c.napi_value,
        this_arg: c.napi_value,
        argc: usize,
        data: ?*anyopaque,

        const Self = @This();

        /// https://nodejs.org/api/n-api.html#napi_get_cb_info
        pub fn init(env: c.napi_env, cb_info: c.napi_callback_info) NapiError!Self {
            var info = Self{
                .env = env,
                .args = undefined,
                .this_arg = undefined,
                .argc = undefined,
                .data = undefined,
            };

            var initial_argc = argc_cap;

            try status.check(
                c.napi_get_cb_info(env, cb_info, &initial_argc, &info.args, &info.this_arg, @ptrCast(&info.data)),
            );

            info.argc = if (initial_argc <= argc_cap) initial_argc else argc_cap;

            return info;
        }

        /// Caller must ensure that `index` is less than `argc`.
        pub fn arg(self: Self, index: usize) Value {
            return Value{
                .env = self.env,
                .value = self.args[index],
            };
        }

        pub fn getArg(self: Self, index: usize) ?Value {
            if (index >= self.argc) return null;
            return Value{
                .env = self.env,
                .value = self.args[index],
            };
        }

        pub fn this(self: Self) Value {
            return Value{
                .env = self.env,
                .value = self.this_arg,
            };
        }
    };
}
