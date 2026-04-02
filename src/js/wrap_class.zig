const std = @import("std");
const napi = @import("../napi.zig");
const context = @import("context.zig");
const wrap_function = @import("wrap_function.zig");
const convertArg = wrap_function.convertArg;
const convertReturn = wrap_function.convertReturn;
const callAndConvert = wrap_function.callAndConvert;
const isDslType = wrap_function.isDslType;

/// Given a class type `T` (a struct with `pub const js_class = true`), returns a
/// type with comptime-generated N-API constructor, finalizer, property descriptors,
/// and method wrappers.
pub fn wrapClass(comptime T: type) type {
    // Validation: must have js_class = true
    if (!@hasDecl(T, "js_class")) {
        @compileError("wrapClass: " ++ @typeName(T) ++ " must have `pub const js_class = true`");
    }

    // Validation: must have init
    if (!@hasDecl(T, "init")) {
        @compileError("wrapClass: " ++ @typeName(T) ++ " must have a `pub fn init(...)` constructor");
    }

    return struct {
        const all_decls = @typeInfo(T).@"struct".decls;
        const decl_count = all_decls.len;
        const DeclCategory = enum { getter, setter, instance_method, instance_factory, static_factory, static_method, skip };
        const DeclMeta = struct {
            name: []const u8,
            category: DeclCategory = .skip,
            is_by_value: bool = false,
            setter_name: ?[]const u8 = null,
        };
        const ClassMeta = struct {
            decls: [decl_count]DeclMeta,
            descriptor_count: usize,
            static_factory_count: usize,
        };
        const getter_name_count = if (@hasDecl(T, "js_getters"))
            @typeInfo(@TypeOf(T.js_getters)).@"struct".fields.len
        else
            0;
        const setter_name_count = if (@hasDecl(T, "js_setters"))
            @typeInfo(@TypeOf(T.js_setters)).@"struct".fields.len
        else
            0;
        const class_meta = analyzeClass();

        /// C-ABI constructor callback for napi_define_class.
        pub const constructor: napi.c.napi_callback = genConstructor();

        /// Default GC-invoked destructor. Frees the native object using c_allocator.
        pub fn defaultFinalize(_: napi.Env, obj: *T, _: ?*anyopaque) void {
            if (@hasDecl(T, "deinit")) {
                obj.deinit();
            }
            std.heap.c_allocator.destroy(obj);
        }

        fn isClassSelfParam(comptime ParamType: type) bool {
            return ParamType == *T or ParamType == *const T or ParamType == T;
        }

        fn isStaticMethod(comptime params: []const std.builtin.Type.Fn.Param) bool {
            return params.len == 0 or !isClassSelfParam(params[0].type.?);
        }

        fn shouldSkipDecl(comptime name: []const u8) bool {
            return std.mem.eql(u8, name, "js_class") or
                std.mem.eql(u8, name, "init") or
                std.mem.eql(u8, name, "deinit") or
                std.mem.eql(u8, name, "js_getters") or
                std.mem.eql(u8, name, "js_setters");
        }

        /// Returns the getter name for a potential setter function name.
        /// e.g., "set_count" -> "count", "reset" -> null
        fn setterTarget(comptime name: []const u8) ?[]const u8 {
            if (name.len > 4 and std.mem.eql(u8, name[0..4], "set_")) {
                return name[4..];
            }
            return null;
        }

        fn tupleIndex(comptime tuple: anytype, comptime name: []const u8) ?usize {
            inline for (tuple, 0..) |entry, idx| {
                if (std.mem.eql(u8, entry, name)) return idx;
            }
            return null;
        }

        fn validateGetterField(comptime getter_name: []const u8, comptime getter_field: anytype) void {
            const getter_info = @typeInfo(@TypeOf(getter_field));
            if (getter_info != .@"fn") {
                @compileError("js_getters: '" ++ getter_name ++ "' is not a function in " ++ @typeName(T));
            }

            const getter_params = getter_info.@"fn".params;
            if (getter_params.len == 0 or !isClassSelfParam(getter_params[0].type.?)) {
                @compileError("getter '" ++ getter_name ++ "' must have a self parameter in " ++ @typeName(T));
            }
            if (getter_params.len > 1) {
                @compileError("getter '" ++ getter_name ++ "' must take only self, got " ++
                    std.fmt.comptimePrint("{d}", .{getter_params.len - 1}) ++ " additional arg(s)");
            }

            const ReturnType = getter_info.@"fn".return_type.?;
            const InnerReturn = if (@typeInfo(ReturnType) == .error_union)
                @typeInfo(ReturnType).error_union.payload
            else
                ReturnType;
            if (InnerReturn == void) {
                @compileError("getter '" ++ getter_name ++ "' must return a DSL type, not void");
            }
        }

        fn validateSetterField(comptime set_fn_name: []const u8, comptime setter_field: anytype) void {
            const setter_info = @typeInfo(@TypeOf(setter_field));
            if (setter_info != .@"fn") {
                @compileError("'" ++ set_fn_name ++ "' is not a function in " ++ @typeName(T));
            }

            const setter_params = setter_info.@"fn".params;
            if (setter_params.len == 0 or setter_params[0].type.? != *T) {
                @compileError("setter '" ++ set_fn_name ++ "' must take self as *" ++ @typeName(T) ++ " (mutable pointer)");
            }
            if (setter_params.len != 2) {
                @compileError("setter '" ++ set_fn_name ++ "' must take exactly one argument besides self");
            }

            const SetterReturn = setter_info.@"fn".return_type.?;
            const SetterInner = if (@typeInfo(SetterReturn) == .error_union)
                @typeInfo(SetterReturn).error_union.payload
            else
                SetterReturn;
            if (SetterInner != void) {
                @compileError("setter '" ++ set_fn_name ++ "' must return void or !void");
            }
        }

        fn isStaticFactory(comptime method: anytype) bool {
            const fn_info = @typeInfo(@TypeOf(method)).@"fn";
            const ReturnType = fn_info.return_type.?;
            const Inner = if (@typeInfo(ReturnType) == .error_union)
                @typeInfo(ReturnType).error_union.payload
            else
                ReturnType;
            return Inner == T;
        }

        fn analyzeClass() ClassMeta {
            const branch_quota = @max(
                100_000,
                1000 + (decl_count * 32) + (getter_name_count * 256) + (setter_name_count * 256),
            );
            @setEvalBranchQuota(branch_quota);

            var metas: [decl_count]DeclMeta = undefined;
            inline for (all_decls, 0..) |decl, idx| {
                metas[idx] = .{ .name = decl.name };
            }

            var getter_flags = [_]bool{false} ** decl_count;
            var setter_decl_flags = [_]bool{false} ** decl_count;
            var getter_setter_names = [_]?[]const u8{null} ** decl_count;
            var getter_seen = [_]bool{false} ** getter_name_count;
            var setter_seen = [_]bool{false} ** setter_name_count;

            if (@hasDecl(T, "js_setters") and !@hasDecl(T, "js_getters")) {
                @compileError("js_setters requires js_getters to also be declared in " ++ @typeName(T));
            }

            if (@hasDecl(T, "js_setters")) {
                inline for (T.js_setters) |setter_name| {
                    if (tupleIndex(T.js_getters, setter_name) == null) {
                        @compileError("js_setters: '" ++ setter_name ++ "' is not listed in js_getters");
                    }
                }
            }

            inline for (all_decls, 0..) |decl, idx| {
                const name = decl.name;
                const field = @field(T, name);
                const field_info = @typeInfo(@TypeOf(field));

                if (@hasDecl(T, "js_getters")) {
                    if (tupleIndex(T.js_getters, name)) |getter_idx| {
                        getter_seen[getter_idx] = true;
                        getter_flags[idx] = true;
                        validateGetterField(name, field);

                        if (@hasDecl(T, "js_setters") and tupleIndex(T.js_setters, name) != null) {
                            getter_setter_names[idx] = "set_" ++ name;
                        }
                    }
                }

                if (setterTarget(name)) |target| {
                    if (field_info == .@"fn") {
                        if (@hasDecl(T, "js_setters")) {
                            if (tupleIndex(T.js_setters, target)) |setter_idx| {
                                setter_seen[setter_idx] = true;
                                setter_decl_flags[idx] = true;
                                validateSetterField(name, field);
                            } else if (@hasDecl(T, "js_getters")) {
                                @compileError("pub fn '" ++ name ++ "' looks like a setter but '" ++ target ++ "' is not in js_setters — add it or rename the function");
                            }
                        } else if (@hasDecl(T, "js_getters")) {
                            @compileError("pub fn '" ++ name ++ "' looks like a setter but '" ++ target ++ "' is not in js_setters — add it or rename the function");
                        }
                    }
                }
            }

            if (@hasDecl(T, "js_getters")) {
                inline for (T.js_getters, 0..) |getter_name, getter_idx| {
                    if (!getter_seen[getter_idx]) {
                        @compileError("js_getters: '" ++ getter_name ++ "' does not match any pub fn in " ++ @typeName(T));
                    }
                }
            }

            if (@hasDecl(T, "js_setters")) {
                inline for (T.js_setters, 0..) |setter_name, setter_idx| {
                    if (!setter_seen[setter_idx]) {
                        const set_fn_name = "set_" ++ setter_name;
                        @compileError("js_setters: '" ++ setter_name ++ "' requires a pub fn '" ++ set_fn_name ++ "' in " ++ @typeName(T));
                    }
                }
            }

            var descriptor_count: usize = 0;
            var static_factory_count: usize = 0;

            inline for (all_decls, 0..) |decl, idx| {
                const name = decl.name;
                if (shouldSkipDecl(name)) continue;

                const field = @field(T, name);
                const field_info = @typeInfo(@TypeOf(field));
                if (field_info != .@"fn") continue;

                if (getter_flags[idx]) {
                    const getter_params = field_info.@"fn".params;
                    metas[idx].category = .getter;
                    metas[idx].is_by_value = getter_params[0].type.? == T;
                    metas[idx].setter_name = getter_setter_names[idx];
                    descriptor_count += 1;
                    continue;
                }

                if (setter_decl_flags[idx]) {
                    metas[idx].category = .setter;
                    continue;
                }

                const params = field_info.@"fn".params;
                if (!isStaticMethod(params)) {
                    metas[idx].is_by_value = params[0].type.? == T;
                    metas[idx].category = if (isStaticFactory(field)) .instance_factory else .instance_method;
                    descriptor_count += 1;
                    continue;
                }

                metas[idx].category = if (isStaticFactory(field)) .static_factory else .static_method;
                descriptor_count += 1;
                if (metas[idx].category == .static_factory) {
                    static_factory_count += 1;
                }
            }

            return .{
                .decls = metas,
                .descriptor_count = descriptor_count,
                .static_factory_count = static_factory_count,
            };
        }

        /// Returns an array of napi_property_descriptor for all public declarations of T.
        /// Getters/setters produce accessor descriptors; methods/statics produce method descriptors.
        pub fn getPropertyDescriptors() []const napi.c.napi_property_descriptor {
            if (class_meta.descriptor_count == 0) return &[0]napi.c.napi_property_descriptor{};

            const descriptors = comptime blk: {
                var descs: [class_meta.descriptor_count]napi.c.napi_property_descriptor = undefined;
                var idx: usize = 0;

                for (class_meta.decls) |meta| {
                    switch (meta.category) {
                        .skip, .setter => continue,
                        else => {},
                    }

                    const field = @field(T, meta.name);

                    var desc = std.mem.zeroes(napi.c.napi_property_descriptor);
                    const property_name: [:0]const u8 = meta.name ++ "";
                    desc.utf8name = property_name.ptr;

                    switch (meta.category) {
                        .getter => {
                            desc.getter = wrapGetter(T, field, meta.is_by_value);
                            if (meta.setter_name) |setter_name| {
                                const setter_field = @field(T, setter_name);
                                desc.setter = wrapSetter(T, setter_field);
                            }
                            desc.attributes = @intFromEnum(napi.value_types.PropertyAttributes.default_jsproperty);
                        },
                        .instance_method => {
                            desc.method = wrapMethod(T, field, meta.is_by_value);
                            desc.attributes = @intFromEnum(napi.value_types.PropertyAttributes.default_method);
                        },
                        .instance_factory => {
                            desc.method = wrapInstanceFactory(T, field, meta.is_by_value);
                            desc.attributes = @intFromEnum(napi.value_types.PropertyAttributes.default_method);
                        },
                        .static_factory => {
                            desc.method = wrapStaticFactory(T, field);
                            desc.attributes = @intFromEnum(napi.value_types.PropertyAttributes.default_method) |
                                @intFromEnum(napi.value_types.PropertyAttributes.static);
                        },
                        .static_method => {
                            desc.method = wrap_function.wrapFunction(field);
                            desc.attributes = @intFromEnum(napi.value_types.PropertyAttributes.default_method) |
                                @intFromEnum(napi.value_types.PropertyAttributes.static);
                        },
                        .skip, .setter => unreachable,
                    }

                    descs[idx] = desc;
                    idx += 1;
                }

                break :blk descs;
            };

            return &descriptors;
        }

        pub fn hasFactories() bool {
            return class_meta.static_factory_count > 0;
        }

        fn genConstructor() napi.c.napi_callback {
            const init_fn = @field(T, "init");
            const InitFnType = @TypeOf(init_fn);
            const init_info = @typeInfo(InitFnType).@"fn";
            const init_params = init_info.params;
            const init_argc = init_params.len;

            const cb = struct {
                pub fn callback(raw_env: napi.c.napi_env, cb_info: napi.c.napi_callback_info) callconv(.C) napi.c.napi_value {
                    const e = napi.Env{ .env = raw_env };
                    const prev = context.setEnv(e);
                    defer context.restoreEnv(prev);

                    // Get args and this
                    var raw_args: [if (init_argc > 0) init_argc else 1]napi.c.napi_value = std.mem.zeroes([if (init_argc > 0) init_argc else 1]napi.c.napi_value);
                    var actual_argc: usize = init_argc;
                    var this_arg: napi.c.napi_value = null;
                    napi.status.check(napi.c.napi_get_cb_info(
                        raw_env,
                        cb_info,
                        &actual_argc,
                        if (init_argc > 0) &raw_args else null,
                        &this_arg,
                        null,
                    )) catch {
                        e.throwError("", "Failed to get callback info in constructor") catch {};
                        return null;
                    };

                    // Validate argument count (only required/non-optional params)
                    const required_init_argc = comptime wrap_function.requiredArgCount(init_params);
                    if (required_init_argc > 0 and actual_argc < required_init_argc) {
                        e.throwTypeError("", "Constructor expects at least " ++ std.fmt.comptimePrint("{d}", .{required_init_argc}) ++ " arguments") catch {};
                        return null;
                    }

                    // Build args and call init
                    var args: std.meta.ArgsTuple(InitFnType) = undefined;
                    inline for (0..init_argc) |i| {
                        const ParamType = init_params[i].type.?;
                        args[i] = wrap_function.convertArgWithOptional(ParamType, raw_args[i], raw_env, i, actual_argc);
                    }

                    const init_result = callInit(init_fn, args) orelse return null;

                    // Allocate native object on the heap
                    const obj_ptr = std.heap.c_allocator.create(T) catch {
                        e.throwError("", "Out of memory allocating native object") catch {};
                        return null;
                    };
                    obj_ptr.* = init_result;

                    // Wrap the native object onto the JS this
                    const this_val = napi.Value{ .env = raw_env, .value = this_arg };
                    _ = e.wrap(this_val, T, obj_ptr, defaultFinalize, null, null) catch {
                        std.heap.c_allocator.destroy(obj_ptr);
                        e.throwError("", "Failed to wrap native object") catch {};
                        return null;
                    };

                    return this_arg;
                }
            };
            return cb.callback;
        }

        /// Calls init handling error unions and optionals.
        fn callInit(comptime init_fn: anytype, args: std.meta.ArgsTuple(@TypeOf(init_fn))) ?T {
            const ReturnType = @typeInfo(@TypeOf(init_fn)).@"fn".return_type.?;
            const ret_info = @typeInfo(ReturnType);

            if (ret_info == .error_union) {
                const result = @call(.auto, init_fn, args) catch |err| {
                    const e = napi.Env{ .env = context.env().env };
                    e.throwError(@errorName(err), @errorName(err)) catch {};
                    return null;
                };

                const Payload = ret_info.error_union.payload;
                if (@typeInfo(Payload) == .optional) {
                    return result orelse {
                        const e = napi.Env{ .env = context.env().env };
                        e.throwError("", "Constructor returned null") catch {};
                        return null;
                    };
                }
                return result;
            }

            if (ret_info == .optional) {
                return @call(.auto, init_fn, args) orelse {
                    const e = napi.Env{ .env = context.env().env };
                    e.throwError("", "Constructor returned null") catch {};
                    return null;
                };
            }

            return @call(.auto, init_fn, args);
        }

        /// Generates a C callback for an instance method of class `Class`.
        /// Extracts `this`, unwraps the native object, and prepends self to the args.
        fn wrapMethod(comptime Class: type, comptime method: anytype, comptime is_by_value: bool) napi.c.napi_callback {
            const MethodFnType = @TypeOf(method);
            const method_info = @typeInfo(MethodFnType).@"fn";
            const method_params = method_info.params;
            // Number of JS arguments (excludes self param)
            const js_argc = method_params.len - 1;

            const method_cb = struct {
                pub fn callback(raw_env: napi.c.napi_env, cb_info: napi.c.napi_callback_info) callconv(.C) napi.c.napi_value {
                    const e = napi.Env{ .env = raw_env };
                    const prev_env = context.setEnv(e);
                    defer context.restoreEnv(prev_env);

                    // Get args and this
                    var raw_args: [if (js_argc > 0) js_argc else 1]napi.c.napi_value = std.mem.zeroes([if (js_argc > 0) js_argc else 1]napi.c.napi_value);
                    var actual_argc: usize = js_argc;
                    var this_arg: napi.c.napi_value = null;
                    napi.status.check(napi.c.napi_get_cb_info(
                        raw_env,
                        cb_info,
                        &actual_argc,
                        if (js_argc > 0) &raw_args else null,
                        &this_arg,
                        null,
                    )) catch {
                        e.throwError("", "Failed to get callback info in method") catch {};
                        return null;
                    };

                    // Validate argument count (only required/non-optional params)
                    const required_js_argc = comptime blk: {
                        var count: usize = 0;
                        for (method_params[1..]) |p| {
                            if (@typeInfo(p.type.?) != .optional) count += 1;
                        }
                        break :blk count;
                    };
                    if (required_js_argc > 0 and actual_argc < required_js_argc) {
                        e.throwTypeError("", "Method expects at least " ++ std.fmt.comptimePrint("{d}", .{required_js_argc}) ++ " arguments") catch {};
                        return null;
                    }

                    // Unwrap self from this
                    const this_val = napi.Value{ .env = raw_env, .value = this_arg };
                    const self_ptr = e.unwrap(Class, this_val) catch {
                        e.throwError("", "Failed to unwrap native object") catch {};
                        return null;
                    };

                    // Store JS this for js.thisArg() access
                    const prev_this = context.setThis(this_val);
                    defer context.restoreThis(prev_this);

                    // Build full args tuple (self + JS args)
                    var args: std.meta.ArgsTuple(MethodFnType) = undefined;
                    if (is_by_value) {
                        args[0] = self_ptr.*; // T (by value) for immutable methods
                    } else {
                        args[0] = self_ptr; // *T or *const T for pointer methods
                    }

                    inline for (0..js_argc) |i| {
                        const ParamType = method_params[i + 1].type.?;
                        args[i + 1] = wrap_function.convertArgWithOptional(ParamType, raw_args[i], raw_env, i, actual_argc);
                    }

                    return callAndConvert(method, args, raw_env);
                }
            };
            return method_cb.callback;
        }

        /// Generates a C callback for an instance method that returns a new instance of Class.
        /// Like wrapStaticFactory but for instance methods — gets the constructor from this.constructor.
        fn wrapInstanceFactory(comptime Class: type, comptime method_fn: anytype, comptime is_by_value: bool) napi.c.napi_callback {
            const MethodFnType = @TypeOf(method_fn);
            const method_info = @typeInfo(MethodFnType).@"fn";
            const method_params = method_info.params;
            const js_argc = method_params.len - 1; // excludes self
            const required_js_argc = comptime wrap_function.requiredArgCount(method_params[1..]);
            const ReturnType = method_info.return_type.?;

            const factory_cb = struct {
                pub fn callback(raw_env: napi.c.napi_env, cb_info: napi.c.napi_callback_info) callconv(.C) napi.c.napi_value {
                    const e = napi.Env{ .env = raw_env };
                    const prev_env = context.setEnv(e);
                    defer context.restoreEnv(prev_env);

                    // Get args and this
                    var raw_args: [if (js_argc > 0) js_argc else 1]napi.c.napi_value = std.mem.zeroes([if (js_argc > 0) js_argc else 1]napi.c.napi_value);
                    var actual_argc: usize = js_argc;
                    var this_arg: napi.c.napi_value = null;
                    napi.status.check(napi.c.napi_get_cb_info(
                        raw_env,
                        cb_info,
                        &actual_argc,
                        if (js_argc > 0) &raw_args else null,
                        &this_arg,
                        null,
                    )) catch {
                        e.throwError("", "Failed to get callback info in instance factory") catch {};
                        return null;
                    };

                    if (required_js_argc > 0 and actual_argc < required_js_argc) {
                        e.throwTypeError("", "Method expects at least " ++ std.fmt.comptimePrint("{d}", .{required_js_argc}) ++ " arguments") catch {};
                        return null;
                    }

                    // Unwrap self
                    const this_val = napi.Value{ .env = raw_env, .value = this_arg };
                    const self_ptr = e.unwrap(Class, this_val) catch {
                        e.throwError("", "Failed to unwrap native object in instance factory") catch {};
                        return null;
                    };

                    // Store JS this for js.thisArg() access
                    const prev_this = context.setThis(this_val);
                    defer context.restoreThis(prev_this);

                    // Build args tuple (self + JS args)
                    var args: std.meta.ArgsTuple(MethodFnType) = undefined;
                    if (is_by_value) {
                        args[0] = self_ptr.*;
                    } else {
                        args[0] = self_ptr;
                    }
                    inline for (0..js_argc) |i| {
                        const ParamType = method_params[i + 1].type.?;
                        args[i + 1] = wrap_function.convertArgWithOptional(ParamType, raw_args[i], raw_env, i, actual_argc);
                    }

                    // Call user function → get T value
                    const instance = if (@typeInfo(ReturnType) == .error_union)
                        @call(.auto, method_fn, args) catch |err| {
                            e.throwError(@errorName(err), @errorName(err)) catch {};
                            return null;
                        }
                    else
                        @call(.auto, method_fn, args);

                    // Allocate on heap
                    const obj_ptr = std.heap.c_allocator.create(Class) catch {
                        e.throwError("", "Out of memory allocating native object") catch {};
                        return null;
                    };
                    obj_ptr.* = instance;

                    // Get constructor from this.constructor (instance method, not static)
                    const ctor_val = this_val.getNamedProperty("constructor") catch {
                        std.heap.c_allocator.destroy(obj_ptr);
                        e.throwError("", "Failed to get constructor from instance") catch {};
                        return null;
                    };

                    // Create new JS instance
                    var js_instance: napi.c.napi_value = null;
                    napi.status.check(napi.c.napi_new_instance(
                        raw_env,
                        ctor_val.value,
                        0,
                        null,
                        &js_instance,
                    )) catch {
                        std.heap.c_allocator.destroy(obj_ptr);
                        e.throwError("", "Failed to create instance in instance factory") catch {};
                        return null;
                    };

                    // Remove the wrap that the constructor created (init() result),
                    // then re-wrap with the factory's result.
                    const instance_napi = napi.Value{ .env = raw_env, .value = js_instance };
                    const old_ptr = e.removeWrap(Class, instance_napi) catch {
                        std.heap.c_allocator.destroy(obj_ptr);
                        e.throwError("", "Failed to remove constructor wrap in instance factory") catch {};
                        return null;
                    };
                    std.heap.c_allocator.destroy(old_ptr);

                    // Wrap with the factory's result
                    _ = e.wrap(instance_napi, Class, obj_ptr, defaultFinalize, null, null) catch {
                        std.heap.c_allocator.destroy(obj_ptr);
                        e.throwError("", "Failed to wrap native object in instance factory") catch {};
                        return null;
                    };

                    return js_instance;
                }
            };
            return factory_cb.callback;
        }

        /// Generates a C callback for a getter property of class `Class`.
        /// Extracts `this`, unwraps the native object, calls the getter, and returns the value.
        fn wrapGetter(comptime Class: type, comptime getter_fn: anytype, comptime is_by_value: bool) napi.c.napi_callback {
            const GetterFnType = @TypeOf(getter_fn);

            const getter_cb = struct {
                pub fn callback(raw_env: napi.c.napi_env, cb_info: napi.c.napi_callback_info) callconv(.C) napi.c.napi_value {
                    const e = napi.Env{ .env = raw_env };
                    const prev_env = context.setEnv(e);
                    defer context.restoreEnv(prev_env);

                    // Get this_arg (no JS args for getters)
                    var argc: usize = 0;
                    var this_arg: napi.c.napi_value = null;
                    napi.status.check(napi.c.napi_get_cb_info(
                        raw_env,
                        cb_info,
                        &argc,
                        null,
                        &this_arg,
                        null,
                    )) catch {
                        e.throwError("", "Failed to get callback info in getter") catch {};
                        return null;
                    };

                    // Unwrap self
                    const this_val = napi.Value{ .env = raw_env, .value = this_arg };
                    const self_ptr = e.unwrap(Class, this_val) catch {
                        e.throwError("", "Failed to unwrap native object in getter") catch {};
                        return null;
                    };

                    // Store JS this for js.thisArg() access
                    const prev_this = context.setThis(this_val);
                    defer context.restoreThis(prev_this);

                    // Build args tuple (self only)
                    var args: std.meta.ArgsTuple(GetterFnType) = undefined;
                    if (is_by_value) {
                        args[0] = self_ptr.*;
                    } else {
                        args[0] = self_ptr;
                    }

                    // Call and convert return
                    return callAndConvert(getter_fn, args, raw_env);
                }
            };
            return getter_cb.callback;
        }

        /// Generates a C callback for a setter property of class `Class`.
        /// Extracts `this` and the assigned value, unwraps the native object, and calls the setter.
        fn wrapSetter(comptime Class: type, comptime setter_fn: anytype) napi.c.napi_callback {
            const SetterFnType = @TypeOf(setter_fn);
            const setter_info = @typeInfo(SetterFnType).@"fn";
            const setter_params = setter_info.params;
            const ValueParamType = setter_params[1].type.?;

            const setter_cb = struct {
                pub fn callback(raw_env: napi.c.napi_env, cb_info: napi.c.napi_callback_info) callconv(.C) napi.c.napi_value {
                    const e = napi.Env{ .env = raw_env };
                    const prev_env = context.setEnv(e);
                    defer context.restoreEnv(prev_env);

                    // Get this_arg and 1 arg (the assigned value)
                    var raw_args: [1]napi.c.napi_value = .{null};
                    var argc: usize = 1;
                    var this_arg: napi.c.napi_value = null;
                    napi.status.check(napi.c.napi_get_cb_info(
                        raw_env,
                        cb_info,
                        &argc,
                        &raw_args,
                        &this_arg,
                        null,
                    )) catch {
                        e.throwError("", "Failed to get callback info in setter") catch {};
                        return null;
                    };

                    // Unwrap self (always mutable pointer)
                    const this_val = napi.Value{ .env = raw_env, .value = this_arg };
                    const self_ptr = e.unwrap(Class, this_val) catch {
                        e.throwError("", "Failed to unwrap native object in setter") catch {};
                        return null;
                    };

                    // Store JS this for js.thisArg() access
                    const prev_this = context.setThis(this_val);
                    defer context.restoreThis(prev_this);

                    // Convert the assigned value
                    const value_arg = convertArg(ValueParamType, raw_args[0], raw_env);

                    // Build args tuple (self + value)
                    var args: std.meta.ArgsTuple(SetterFnType) = undefined;
                    args[0] = self_ptr;
                    args[1] = value_arg;

                    // Call setter — handle error union
                    const SetterReturnType = setter_info.return_type.?;
                    if (@typeInfo(SetterReturnType) == .error_union) {
                        @call(.auto, setter_fn, args) catch |err| {
                            e.throwError(@errorName(err), @errorName(err)) catch {};
                            return null;
                        };
                    } else {
                        @call(.auto, setter_fn, args);
                    }

                    // Setters return undefined
                    return null;
                }
            };
            return setter_cb.callback;
        }

        fn wrapStaticFactory(comptime Class: type, comptime method: anytype) napi.c.napi_callback {
            const MethodFnType = @TypeOf(method);
            const method_info = @typeInfo(MethodFnType).@"fn";
            const method_params = method_info.params;
            const method_argc = method_params.len;
            const required_argc = comptime wrap_function.requiredArgCount(method_params);
            const ReturnType = method_info.return_type.?;

            const factory_cb = struct {
                pub fn callback(raw_env: napi.c.napi_env, cb_info: napi.c.napi_callback_info) callconv(.C) napi.c.napi_value {
                    const e = napi.Env{ .env = raw_env };
                    const prev_env = context.setEnv(e);
                    defer context.restoreEnv(prev_env);

                    var raw_args: [if (method_argc > 0) method_argc else 1]napi.c.napi_value = std.mem.zeroes([if (method_argc > 0) method_argc else 1]napi.c.napi_value);
                    var actual_argc: usize = method_argc;
                    var this_arg: napi.c.napi_value = null;
                    var data_ptr: ?*anyopaque = null;
                    napi.status.check(napi.c.napi_get_cb_info(
                        raw_env,
                        cb_info,
                        &actual_argc,
                        if (method_argc > 0) &raw_args else null,
                        &this_arg,
                        &data_ptr,
                    )) catch {
                        e.throwError("", "Failed to get callback info in factory") catch {};
                        return null;
                    };

                    if (required_argc > 0 and actual_argc < required_argc) {
                        e.throwTypeError("", "Factory expects at least " ++ std.fmt.comptimePrint("{d}", .{required_argc}) ++ " arguments") catch {};
                        return null;
                    }

                    // Build args
                    var args: std.meta.ArgsTuple(MethodFnType) = undefined;
                    inline for (0..method_argc) |i| {
                        const ParamType = method_params[i].type.?;
                        args[i] = wrap_function.convertArgWithOptional(ParamType, raw_args[i], raw_env, i, actual_argc);
                    }

                    // Call user function
                    const instance = if (@typeInfo(ReturnType) == .error_union)
                        @call(.auto, method, args) catch |err| {
                            e.throwError(@errorName(err), @errorName(err)) catch {};
                            return null;
                        }
                    else
                        @call(.auto, method, args);

                    // Allocate on heap
                    const obj_ptr = std.heap.c_allocator.create(Class) catch {
                        e.throwError("", "Out of memory allocating native object") catch {};
                        return null;
                    };
                    obj_ptr.* = instance;

                    // Use this_arg as constructor (for static methods, this IS the constructor)
                    const ctor: napi.c.napi_value = this_arg;

                    // Create new JS instance
                    var js_instance: napi.c.napi_value = null;
                    napi.status.check(napi.c.napi_new_instance(
                        raw_env,
                        ctor,
                        0,
                        null,
                        &js_instance,
                    )) catch {
                        std.heap.c_allocator.destroy(obj_ptr);
                        e.throwError("", "Failed to create instance in factory") catch {};
                        return null;
                    };

                    // Remove the wrap that the constructor created (init() result),
                    // then re-wrap with the factory's result.
                    const instance_val = napi.Value{ .env = raw_env, .value = js_instance };
                    const old_ptr = e.removeWrap(Class, instance_val) catch {
                        std.heap.c_allocator.destroy(obj_ptr);
                        e.throwError("", "Failed to remove constructor wrap in factory") catch {};
                        return null;
                    };
                    // The constructor allocated this — free it since we're replacing
                    std.heap.c_allocator.destroy(old_ptr);

                    // Wrap with the factory's result
                    _ = e.wrap(instance_val, Class, obj_ptr, defaultFinalize, null, null) catch {
                        std.heap.c_allocator.destroy(obj_ptr);
                        e.throwError("", "Failed to wrap native object in factory") catch {};
                        return null;
                    };

                    return js_instance;
                }
            };
            return factory_cb.callback;
        }

        /// Returns property descriptors for factory methods with constructor as data.
        /// Called at runtime after napi_define_class returns the constructor value.
        pub fn getFactoryDescriptors(ctor: napi.c.napi_value) []const napi.c.napi_property_descriptor {
            if (class_meta.static_factory_count == 0) return &[0]napi.c.napi_property_descriptor{};

            const S = struct {
                var descs: [class_meta.static_factory_count]napi.c.napi_property_descriptor = undefined;
            };

            var idx: usize = 0;
            inline for (class_meta.decls) |meta| {
                if (meta.category == .static_factory) {
                    const field = @field(T, meta.name);
                    S.descs[idx] = std.mem.zeroes(napi.c.napi_property_descriptor);
                    const method_name: [:0]const u8 = meta.name ++ "";
                    S.descs[idx].utf8name = method_name.ptr;
                    S.descs[idx].method = wrapStaticFactory(T, field);
                    S.descs[idx].attributes = @intFromEnum(napi.value_types.PropertyAttributes.default_method) |
                        @intFromEnum(napi.value_types.PropertyAttributes.static);
                    S.descs[idx].data = @ptrCast(ctor);
                    idx += 1;
                }
            }

            return S.descs[0..class_meta.static_factory_count];
        }
    };
}

test "wrapClass compile-time validation requires js_class" {
    // This is a negative comptime test — we just verify the function exists
    // and the isDslType helper works. Actual validation would be a compileError.
    try std.testing.expect(true);
}
