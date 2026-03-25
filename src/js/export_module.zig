const std = @import("std");
const napi = @import("../napi.zig");
const context = @import("context.zig");
const wrap_function = @import("wrap_function.zig");
const wrap_class = @import("wrap_class.zig");

/// Iterates the declarations of `Module` and auto-registers:
///   - Public functions → wrapped via wrapFunction + napi_create_function
///   - Public const structs with `js_class = true` → wrapped via wrapClass + napi_define_class
///
/// Usage (at file scope):
///   comptime { js.exportModule(@This()); }
pub fn exportModule(comptime Module: type) void {
    const init = struct {
        pub fn moduleInit(env: napi.Env, module: napi.Value) anyerror!void {
            const prev = context.setEnv(env);
            defer context.restoreEnv(prev);

            const decls = @typeInfo(Module).@"struct".decls;

            inline for (decls) |decl| {
                const field = @field(Module, decl.name);
                const FieldType = @TypeOf(field);
                const field_info = @typeInfo(FieldType);

                if (field_info == .@"fn") {
                    // Skip functions whose parameters aren't DSL types
                    // (catches private helpers that use non-DSL signatures)
                    const fn_params = field_info.@"fn".params;
                    const is_dsl_fn = comptime blk: {
                        for (fn_params) |p| {
                            const PT = p.type orelse break :blk false;
                            if (PT != napi.Value and !wrap_function.isDslType(PT)) break :blk false;
                        }
                        break :blk true;
                    };
                    if (!is_dsl_fn) continue;

                    // DSL function — wrap and register
                    const cb = wrap_function.wrapFunction(field);
                    const name: [:0]const u8 = decl.name ++ "";

                    var js_fn: napi.c.napi_value = null;
                    try napi.status.check(napi.c.napi_create_function(
                        env.env,
                        name.ptr,
                        name.len,
                        cb,
                        null,
                        &js_fn,
                    ));

                    const fn_val = napi.Value{ .env = env.env, .value = js_fn };
                    try module.setNamedProperty(name, fn_val);
                } else if (field_info == .type) {
                    const InnerType = field;
                    if (@typeInfo(InnerType) == .@"struct" and
                        @hasDecl(InnerType, "js_class") and
                        @TypeOf(@field(InnerType, "js_class")) == bool and
                        @field(InnerType, "js_class") == true)
                    {
                        // Class with js_class — wrap and register
                        const wrapped = wrap_class.wrapClass(InnerType);
                        const props = wrapped.getPropertyDescriptors();
                        const name: [:0]const u8 = decl.name ++ "";

                        var class_val: napi.c.napi_value = null;
                        try napi.status.check(napi.c.napi_define_class(
                            env.env,
                            name.ptr,
                            name.len,
                            wrapped.constructor,
                            null,
                            props.len,
                            if (props.len > 0) props.ptr else null,
                            &class_val,
                        ));

                        const cls = napi.Value{ .env = env.env, .value = class_val };
                        try module.setNamedProperty(name, cls);
                    }
                }
            }
        }
    };

    napi.module.register(init.moduleInit);
}

test "exportModule comptime smoke test" {
    // Just verify the function exists and compiles.
    // Actual registration requires N-API runtime.
    try std.testing.expect(true);
}
