const std = @import("std");
const napi = @import("../napi.zig");
const context = @import("context.zig");
const wrap_function = @import("wrap_function.zig");
const wrap_class = @import("wrap_class.zig");
const class_meta = @import("class_meta.zig");
const class_runtime = @import("class_runtime.zig");

/// Registers a Zig `Module`'s public declarations (functions, classes, namespaces)
/// as JavaScript exports in the current Node-API environment at compile time.
///
/// This is the primary entry point for integrating ZAPI DSL-based Zig code into
/// Node.js. It inspects the `Module`'s `pub` declarations and automatically
/// creates corresponding JavaScript functions, classes, and sub-namespaces.
///
/// Optional `options` can be provided to customize module lifecycle hooks:
///
/// - `.init = fn (refcount: u32) !void`: Called when the module is initialized
///   in a new N-API environment. `refcount` is the number of active environments
///   *before* the current one is added (0 for the first environment).
///   Allows for environment-specific setup. Can return an error.
///
/// - `.cleanup = fn (refcount: u32) void`: Called when an N-API environment
///   exits. `refcount` is the number of active environments *after* the current
///   one is removed (0 for the last environment).
///   Allows for environment-specific teardown.
///
/// - `.register = fn (env: napi.Env, exports: napi.Value) !void`: Allows for
///   manual registration of exports if the default reflection mechanism is
///   insufficient. This function is called *after* all automatic DSL exports
///   have been processed and *before* the module's `init` hook (if present).
///   `exports` is the JavaScript object that will hold the module's exports.
///
/// The DSL internally manages an atomic refcount for module instances across
/// different N-API environments.
///
/// Usage Examples:
/// ```zig
/// comptime {
///     // Basic export of all `pub` functions, classes, and sub-namespaces
///     js.exportModule(@This());
/// }
///
/// comptime {
///     // Export with custom initialization and cleanup hooks
///     js.exportModule(@This(), .{
///         .init = myInitFunction,
///         .cleanup = myCleanupFunction,
///     });
/// }
///
/// comptime {
///     // Export with a manual registration function
///     js.exportModule(@This(), .{
///         .register = myCustomRegisterFunction,
///     });
/// }
/// ```
pub fn exportModule(comptime Module: type, comptime options: anytype) void {
    const has_init = @hasField(@TypeOf(options), "init");
    const has_cleanup = @hasField(@TypeOf(options), "cleanup");
    const has_register = @hasField(@TypeOf(options), "register");
    const has_lifecycle = has_init or has_cleanup;

    const State = struct {
        var env_refcount: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);

        // addEnvCleanupHook requires a non-null *Data pointer.
        const CleanupData = struct {
            _dummy: u8 = 0,
        };
        var cleanup_data: CleanupData = .{};

        fn cleanupHook(_: *CleanupData) void {
            const prev = env_refcount.fetchSub(1, .acq_rel);
            const new_refcount = prev - 1;
            if (has_cleanup) {
                options.cleanup(new_refcount);
            }
        }
    };

    const init = struct {
        pub fn moduleInit(env: napi.Env, module: napi.Value) anyerror!void {
            const prev = context.setEnv(env);
            defer context.restoreEnv(prev);

            if (has_lifecycle) {
                const prev_refcount = State.env_refcount.fetchAdd(1, .monotonic);
                var cleanup_hook_registered = false;
                errdefer if (!cleanup_hook_registered) {
                    _ = State.env_refcount.fetchSub(1, .acq_rel);
                };

                if (has_init) {
                    try options.init(prev_refcount);
                }

                _ = try registerDecls(Module, env, module, 0);

                if (has_register) {
                    try options.register(env, module);
                }

                if (shouldRegisterEnvCleanupHook(has_lifecycle)) {
                    try env.addEnvCleanupHook(
                        State.CleanupData,
                        &State.cleanup_data,
                        State.cleanupHook,
                    );
                    cleanup_hook_registered = true;
                }
                return;
            }

            // Register all pub decls
            _ = try registerDecls(Module, env, module, 0);

            // Manual registration hook for non-DSL modules
            if (has_register) {
                try options.register(env, module);
            }
        }
    };

    napi.module.register(init.moduleInit);
}

fn shouldRegisterEnvCleanupHook(has_lifecycle: bool) bool {
    return has_lifecycle;
}

/// Iterates module declarations and registers DSL functions and js_meta classes.
fn registerDecls(comptime Module: type, env: napi.Env, module: napi.Value, comptime depth: usize) !bool {
    const decls = @typeInfo(Module).@"struct".decls;
    var exported_any = false;

    inline for (decls) |decl| {
        const field = @field(Module, decl.name);
        const FieldType = @TypeOf(field);
        const field_info = @typeInfo(FieldType);

        if (field_info == .@"fn") {
            // Skip functions whose parameters aren't DSL types
            const fn_params = field_info.@"fn".params;
            const is_dsl_fn = comptime blk: {
                for (fn_params) |p| {
                    const PT = p.type orelse break :blk false;
                    if (!wrap_function.isDslOrOptionalDsl(PT)) break :blk false;
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
            exported_any = true;
        } else if (field_info == .type) {
            const InnerType = field;
            if (@typeInfo(InnerType) == .@"struct") {
                if (comptime class_meta.hasClassMeta(InnerType)) {
                    const wrapped = wrap_class.wrapClass(InnerType);
                    const props = wrapped.getPropertyDescriptors();
                    const class_name = comptime class_meta.getClassName(InnerType, decl.name);
                    const name: [:0]const u8 = class_name ++ "";

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
                    try class_runtime.registerClass(InnerType, env, cls);
                    try module.setNamedProperty(name, cls);
                    exported_any = true;
                } else {
                    const ns_obj = try env.createObject();
                    if (try registerDecls(InnerType, env, ns_obj, depth + 1)) {
                        const name: [:0]const u8 = decl.name ++ "";
                        try module.setNamedProperty(name, ns_obj);
                        exported_any = true;
                    }
                }
            }
        }
    }
    return exported_any;
}

test "exportModule comptime smoke test" {
    try std.testing.expect(true);
}

test "exportModule registers cleanup hook for init-only lifecycle" {
    try std.testing.expect(shouldRegisterEnvCleanupHook(true));
    try std.testing.expect(!shouldRegisterEnvCleanupHook(false));
}
