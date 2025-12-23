const c = @import("c.zig");
const Env = @import("Env.zig");
const Value = @import("Value.zig");

extern fn napi_register_module_v1(env: c.napi_env, module: c.napi_value) c.napi_status;

pub fn register(comptime f: fn (Env, Value) anyerror!void) void {
    const wrapper = opaque {
        fn napi_register_module_v1(env: c.napi_env, module: c.napi_value) callconv(.C) c.napi_value {
            const e = Env{
                .env = env,
            };
            const v = Value{
                .env = env,
                .value = module,
            };
            f(e, v) catch |err| {
                e.throwError(@errorName(err), "Error in module registration") catch unreachable;
            };
            return module;
        }
    };

    @export(&wrapper.napi_register_module_v1, .{
        .name = "napi_register_module_v1",
        .linkage = .strong,
    });
}
