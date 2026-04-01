const std = @import("std");
const napi = @import("../napi.zig");
const context = @import("context.zig");
const wrap_function = @import("wrap_function.zig");
const wrap_class = @import("wrap_class.zig");

/// Scans pub decls of `Module` and registers them as JS exports.
///
/// Optional second argument for lifecycle hooks:
///   js.exportModule(@This(), .{
///       .init    = fn (refcount: u32) !void,  — called during registration
///       .cleanup = fn (refcount: u32) void,   — called on env exit
///   })
///
/// The DSL manages an atomic refcount internally:
///   - .init receives the refcount BEFORE increment (0 = first env)
///   - .cleanup receives the refcount AFTER decrement (0 = last env)
///
/// Usage:
///   comptime { js.exportModule(@This()); }
///   comptime { js.exportModule(@This(), .{ .init = ..., .cleanup = ... }); }
pub fn exportModule(comptime Module: type, comptime options: anytype) void {
    const has_init = @hasField(@TypeOf(options), "init");
    const has_cleanup = @hasField(@TypeOf(options), "cleanup");
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

            // Lifecycle: init
            if (has_lifecycle) {
                const prev_refcount = State.env_refcount.fetchAdd(1, .monotonic);

                if (has_init) {
                    options.init(prev_refcount) catch |err| {
                        // Rollback refcount on init failure
                        _ = State.env_refcount.fetchSub(1, .acq_rel);
                        return err;
                    };
                }
            }

            // Register all pub decls
            try registerDecls(Module, env, module);

            // Lifecycle: register cleanup hook
            if (has_cleanup) {
                try env.addEnvCleanupHook(
                    State.CleanupData,
                    &State.cleanup_data,
                    State.cleanupHook,
                );
            }
        }
    };

    napi.module.register(init.moduleInit);
}

/// Iterates module declarations and registers DSL functions and js_class structs.
fn registerDecls(comptime Module: type, env: napi.Env, module: napi.Value) !void {
    const decls = @typeInfo(Module).@"struct".decls;

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
            } else if (@typeInfo(InnerType) == .@"struct" and hasDslDecls(InnerType)) {
                // Namespace — create JS object and recurse
                const ns_obj = try env.createObject();
                try registerDecls(InnerType, env, ns_obj);
                const name: [:0]const u8 = decl.name ++ "";
                try module.setNamedProperty(name, ns_obj);
            }
        }
    }
}

/// Comptime check: does this struct type contain any exportable DSL content?
/// Returns true if it has at least one DSL-compatible function, js_class struct,
/// or nested struct that itself qualifies as a namespace.
fn hasDslDecls(comptime T: type) bool {
    if (@typeInfo(T) != .@"struct") return false;
    const decls = @typeInfo(T).@"struct".decls;
    inline for (decls) |decl| {
        const field = @field(T, decl.name);
        const FieldType = @TypeOf(field);
        const field_info = @typeInfo(FieldType);

        if (field_info == .@"fn") {
            const fn_params = field_info.@"fn".params;
            const is_dsl = blk: {
                inline for (fn_params) |p| {
                    const PT = p.type orelse break :blk false;
                    if (!wrap_function.isDslOrOptionalDsl(PT)) break :blk false;
                }
                break :blk true;
            };
            if (is_dsl) return true;
        } else if (field_info == .type) {
            const InnerType = field;
            if (@typeInfo(InnerType) == .@"struct") {
                if (@hasDecl(InnerType, "js_class") and
                    @TypeOf(@field(InnerType, "js_class")) == bool and
                    @field(InnerType, "js_class") == true)
                {
                    return true;
                }
                if (hasDslDecls(InnerType)) return true;
            }
        }
    }
    return false;
}

test "exportModule comptime smoke test" {
    try std.testing.expect(true);
}
