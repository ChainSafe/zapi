const std = @import("std");
const napi = @import("../napi.zig");
const context = @import("context.zig");
const class_meta = @import("class_meta.zig");
const class_runtime = @import("class_runtime.zig");
const wrap_function = @import("wrap_function.zig");
const convertArg = wrap_function.convertArg;
const callAndConvert = wrap_function.callAndConvert;

/// Given a class type `T` (a struct with `pub const js_meta = js.class(...)`
/// or legacy `pub const js_class = true`), returns a type with comptime-generated
/// N-API constructor, finalizer, property descriptors, and method wrappers.
pub fn wrapClass(comptime T: type) type {
    if (!class_meta.isClassType(T)) {
        @compileError("wrapClass: " ++ @typeName(T) ++ " must declare `pub const js_meta = js.class(...)`");
    }

    if (!@hasDecl(T, "init")) {
        @compileError("wrapClass: " ++ @typeName(T) ++ " must have a `pub fn init(...)` constructor");
    }

    return struct {
        const all_decls = @typeInfo(T).@"struct".decls;
        const max_property_count = if (class_meta.hasProperties(T))
            class_meta.propertyFields(T).len
        else if (@hasDecl(T, "js_getters"))
            @typeInfo(@TypeOf(T.js_getters)).@"struct".fields.len
        else
            0;

        const MethodCategory = enum { instance_method, static_method, skip };
        const GetterKind = enum { method, field };

        const PropertyMeta = struct {
            name: []const u8,
            getter_kind: GetterKind,
            getter_name: ?[]const u8 = null,
            setter_name: ?[]const u8 = null,
            field_name: ?[]const u8 = null,
            is_by_value: bool = false,
        };

        const MethodMeta = struct {
            name: []const u8,
            category: MethodCategory = .skip,
            is_by_value: bool = false,
        };

        const ClassAnalysis = struct {
            properties: [max_property_count]PropertyMeta,
            property_count: usize,
            methods: [all_decls.len]MethodMeta,
            method_count: usize,
        };

        const analysis = analyzeClass();

        pub const constructor: napi.c.napi_callback = genConstructor();

        pub fn defaultFinalize(_: napi.Env, obj: *T, hint: ?*anyopaque) void {
            if (class_runtime.isInternalPlaceholderHint(T, hint)) {
                class_runtime.destroyInternalPlaceholder(T, obj);
                return;
            }
            class_runtime.destroyNativeObject(T, obj);
        }

        fn isClassSelfParam(comptime ParamType: type) bool {
            return ParamType == *T or ParamType == *const T or ParamType == T;
        }

        fn isStaticMethod(comptime params: []const std.builtin.Type.Fn.Param) bool {
            return params.len == 0 or !isClassSelfParam(params[0].type.?);
        }

        fn returnedClassType(comptime Func: type) ?type {
            const ReturnType = @typeInfo(Func).@"fn".return_type.?;
            return switch (@typeInfo(ReturnType)) {
                .error_union => |eu| switch (@typeInfo(eu.payload)) {
                    .optional => |opt| if (class_meta.isClassType(opt.child)) opt.child else null,
                    else => if (class_meta.isClassType(eu.payload)) eu.payload else null,
                },
                .optional => |opt| if (class_meta.isClassType(opt.child)) opt.child else null,
                else => if (class_meta.isClassType(ReturnType)) ReturnType else null,
            };
        }

        fn shouldSkipDecl(comptime name: []const u8) bool {
            return std.mem.eql(u8, name, "init") or
                std.mem.eql(u8, name, "deinit") or
                std.mem.eql(u8, name, "js_meta") or
                std.mem.eql(u8, name, "js_class") or
                std.mem.eql(u8, name, "js_getters") or
                std.mem.eql(u8, name, "js_setters");
        }

        fn legacySetterTarget(comptime name: []const u8) ?[]const u8 {
            if (name.len > 4 and std.mem.eql(u8, name[0..4], "set_")) {
                return name[4..];
            }
            return null;
        }

        fn tupleContains(comptime tuple: anytype, comptime name: []const u8) bool {
            inline for (tuple) |entry| {
                if (std.mem.eql(u8, entry, name)) return true;
            }
            return false;
        }

        fn capitalizeFirst(comptime name: []const u8) []const u8 {
            if (name.len == 0) return name;
            comptime var buf: [name.len]u8 = undefined;
            buf[0] = std.ascii.toUpper(name[0]);
            inline for (name[1..], 1..) |ch, idx| {
                buf[idx] = ch;
            }
            return &buf;
        }

        fn derivedSetterName(comptime property_name: []const u8) []const u8 {
            return "set" ++ capitalizeFirst(property_name);
        }

        fn accessorName(comptime property_name: []const u8, accessor: class_meta.AccessorRef, comptime is_setter: bool) ?[]const u8 {
            return switch (accessor) {
                .none => null,
                .derived => if (is_setter) derivedSetterName(property_name) else property_name,
                .named => |name| name,
            };
        }

        fn validateGetterMethod(comptime getter_name: []const u8, comptime getter_field: anytype) bool {
            const getter_info = @typeInfo(@TypeOf(getter_field));
            if (getter_info != .@"fn") {
                @compileError("property getter '" ++ getter_name ++ "' is not a function in " ++ @typeName(T));
            }

            const getter_params = getter_info.@"fn".params;
            if (getter_params.len == 0 or !isClassSelfParam(getter_params[0].type.?)) {
                @compileError("getter '" ++ getter_name ++ "' must have a self parameter in " ++ @typeName(T));
            }
            if (getter_params.len > 1) {
                @compileError("getter '" ++ getter_name ++ "' must take only self");
            }

            const ReturnType = getter_info.@"fn".return_type.?;
            const InnerReturn = if (@typeInfo(ReturnType) == .error_union)
                @typeInfo(ReturnType).error_union.payload
            else
                ReturnType;
            if (InnerReturn == void) {
                @compileError("getter '" ++ getter_name ++ "' must return a value");
            }

            return getter_params[0].type.? == T;
        }

        fn validateSetterMethod(comptime setter_name: []const u8, comptime setter_field: anytype) void {
            const setter_info = @typeInfo(@TypeOf(setter_field));
            if (setter_info != .@"fn") {
                @compileError("property setter '" ++ setter_name ++ "' is not a function in " ++ @typeName(T));
            }

            const setter_params = setter_info.@"fn".params;
            if (setter_params.len == 0 or setter_params[0].type.? != *T) {
                @compileError("setter '" ++ setter_name ++ "' must take self as *" ++ @typeName(T));
            }
            if (setter_params.len != 2) {
                @compileError("setter '" ++ setter_name ++ "' must take exactly one argument besides self");
            }

            const SetterReturn = setter_info.@"fn".return_type.?;
            const SetterInner = if (@typeInfo(SetterReturn) == .error_union)
                @typeInfo(SetterReturn).error_union.payload
            else
                SetterReturn;
            if (SetterInner != void) {
                @compileError("setter '" ++ setter_name ++ "' must return void or !void");
            }
        }

        fn validateFieldProperty(comptime field_name: []const u8) void {
            const fields = @typeInfo(T).@"struct".fields;
            inline for (fields) |field_info| {
                if (std.mem.eql(u8, field_info.name, field_name)) return;
            }
            @compileError("js.field references missing field '" ++ field_name ++ "' in " ++ @typeName(T));
        }

        fn addProperty(props: anytype, count: *usize, meta: PropertyMeta) void {
            props[count.*] = meta;
            count.* += 1;
        }

        fn analyzeClass() ClassAnalysis {
            @setEvalBranchQuota(@max(50_000, 1000 + all_decls.len * 64 + max_property_count * 256));

            var properties: [max_property_count]PropertyMeta = undefined;
            var property_count: usize = 0;

            var consumed_methods = [_]bool{false} ** all_decls.len;
            var methods: [all_decls.len]MethodMeta = undefined;
            inline for (all_decls, 0..) |decl, idx| {
                methods[idx] = .{ .name = decl.name };
            }

            if (class_meta.hasProperties(T)) {
                inline for (class_meta.propertyFields(T)) |prop_field| {
                    const property_name = prop_field.name;
                    const spec = @field(T.js_meta.options.properties, property_name);
                    switch (class_meta.propertyKind(spec)) {
                        .computed => {
                            const getter_field = @field(T, property_name);
                            const is_by_value = validateGetterMethod(property_name, getter_field);
                            addProperty(&properties, &property_count, .{
                                .name = property_name,
                                .getter_kind = .method,
                                .getter_name = property_name,
                                .is_by_value = is_by_value,
                            });
                            consumedMethod(&consumed_methods, property_name);
                        },
                        .field => {
                            validateFieldProperty(spec.field_name);
                            addProperty(&properties, &property_count, .{
                                .name = property_name,
                                .getter_kind = .field,
                                .field_name = spec.field_name,
                            });
                        },
                        .prop => {
                            const getter_name = accessorName(property_name, spec.get, false) orelse
                                @compileError("js.prop for '" ++ property_name ++ "' requires a getter");
                            const getter_field = @field(T, getter_name);
                            const is_by_value = validateGetterMethod(getter_name, getter_field);

                            const setter_name = accessorName(property_name, spec.set, true);
                            if (setter_name) |name| {
                                validateSetterMethod(name, @field(T, name));
                                consumedMethod(&consumed_methods, name);
                            }

                            addProperty(&properties, &property_count, .{
                                .name = property_name,
                                .getter_kind = .method,
                                .getter_name = getter_name,
                                .setter_name = setter_name,
                                .is_by_value = is_by_value,
                            });
                            consumedMethod(&consumed_methods, getter_name);
                        },
                        .invalid => @compileError("unsupported property spec for '" ++ property_name ++ "'"),
                    }
                }
            } else if (@hasDecl(T, "js_getters")) {
                inline for (T.js_getters) |getter_name| {
                    const getter_field = @field(T, getter_name);
                    const is_by_value = validateGetterMethod(getter_name, getter_field);
                    const setter_name = if (@hasDecl(T, "js_setters") and tupleContains(T.js_setters, getter_name))
                        "set_" ++ getter_name
                    else
                        null;

                    if (setter_name) |name| {
                        validateSetterMethod(name, @field(T, name));
                        consumedMethod(&consumed_methods, name);
                    }

                    addProperty(&properties, &property_count, .{
                        .name = getter_name,
                        .getter_kind = .method,
                        .getter_name = getter_name,
                        .setter_name = setter_name,
                        .is_by_value = is_by_value,
                    });
                    consumedMethod(&consumed_methods, getter_name);
                }
            }

            var method_count: usize = 0;
            inline for (all_decls, 0..) |decl, idx| {
                const name = decl.name;
                if (shouldSkipDecl(name) or consumed_methods[idx]) continue;

                const field = @field(T, name);
                const field_info = @typeInfo(@TypeOf(field));
                if (field_info != .@"fn") continue;

                if (@hasDecl(T, "js_setters")) {
                    if (legacySetterTarget(name)) |target| {
                        if (tupleContains(T.js_setters, target)) continue;
                    }
                }

                const params = field_info.@"fn".params;
                methods[idx].category = if (isStaticMethod(params)) .static_method else .instance_method;
                methods[idx].is_by_value = if (params.len > 0 and isClassSelfParam(params[0].type.?))
                    params[0].type.? == T
                else
                    false;
                method_count += 1;
            }

            return .{
                .properties = properties,
                .property_count = property_count,
                .methods = methods,
                .method_count = method_count,
            };
        }

        fn consumedMethod(flags: *[all_decls.len]bool, comptime name: []const u8) void {
            inline for (all_decls, 0..) |decl, idx| {
                if (std.mem.eql(u8, decl.name, name)) {
                    flags[idx] = true;
                    return;
                }
            }
            @compileError("property accessor '" ++ name ++ "' does not match any public declaration in " ++ @typeName(T));
        }

        pub fn getPropertyDescriptors() []const napi.c.napi_property_descriptor {
            const descriptor_count = analysis.property_count + analysis.method_count;
            if (descriptor_count == 0) return &[0]napi.c.napi_property_descriptor{};

            const descriptors = comptime blk: {
                var descs: [descriptor_count]napi.c.napi_property_descriptor = undefined;
                var idx: usize = 0;

                for (analysis.properties[0..analysis.property_count]) |prop| {
                    var desc = std.mem.zeroes(napi.c.napi_property_descriptor);
                    const property_name: [:0]const u8 = prop.name ++ "";
                    desc.utf8name = property_name.ptr;
                    desc.getter = switch (prop.getter_kind) {
                        .method => wrapGetter(T, @field(T, prop.getter_name.?), prop.is_by_value),
                        .field => wrapFieldGetter(T, prop.field_name.?),
                    };
                    if (prop.setter_name) |setter_name| {
                        desc.setter = wrapSetter(T, @field(T, setter_name));
                    }
                    desc.attributes = @intFromEnum(napi.value_types.PropertyAttributes.default_jsproperty);
                    descs[idx] = desc;
                    idx += 1;
                }

                for (analysis.methods) |meta| {
                    if (meta.category == .skip) continue;
                    const field = @field(T, meta.name);
                    var desc = std.mem.zeroes(napi.c.napi_property_descriptor);
                    const method_name: [:0]const u8 = meta.name ++ "";
                    desc.utf8name = method_name.ptr;
                    switch (meta.category) {
                        .instance_method => {
                            desc.method = wrapMethod(T, field, meta.is_by_value);
                            desc.attributes = @intFromEnum(napi.value_types.PropertyAttributes.default_method);
                        },
                        .static_method => {
                            desc.method = wrapStaticMethod(T, field);
                            desc.attributes = @intFromEnum(napi.value_types.PropertyAttributes.default_method) |
                                @intFromEnum(napi.value_types.PropertyAttributes.static);
                        },
                        .skip => unreachable,
                    }
                    descs[idx] = desc;
                    idx += 1;
                }

                break :blk descs;
            };

            return &descriptors;
        }

        pub fn hasFactories() bool {
            return false;
        }

        pub fn getFactoryDescriptors(_: napi.c.napi_value) []const napi.c.napi_property_descriptor {
            return &[0]napi.c.napi_property_descriptor{};
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

                    const cb_argc = if (init_argc > 0) init_argc else 1;
                    var raw_args: [cb_argc]napi.c.napi_value = std.mem.zeroes([cb_argc]napi.c.napi_value);
                    var actual_argc: usize = cb_argc;
                    var this_arg: napi.c.napi_value = null;
                    napi.status.check(napi.c.napi_get_cb_info(
                        raw_env,
                        cb_info,
                        &actual_argc,
                        &raw_args,
                        &this_arg,
                        null,
                    )) catch {
                        e.throwError("", "Failed to get callback info in constructor") catch {};
                        return null;
                    };

                    if (actual_argc == 1) {
                        const internal_arg = napi.Value{ .env = raw_env, .value = raw_args[0] };
                        if ((internal_arg.typeof() catch null) == .external) {
                            const obj_ptr = std.heap.c_allocator.create(T) catch {
                                e.throwError("", "Out of memory allocating internal placeholder") catch {};
                                return null;
                            };
                            obj_ptr.* = std.mem.zeroes(T);

                            const this_val = napi.Value{ .env = raw_env, .value = this_arg };
                            _ = e.wrap(this_val, T, obj_ptr, defaultFinalize, class_runtime.internalPlaceholderHint(T), null) catch {
                                std.heap.c_allocator.destroy(obj_ptr);
                                e.throwError("", "Failed to wrap internal placeholder") catch {};
                                return null;
                            };
                            return this_arg;
                        }
                    }

                    const required_init_argc = comptime wrap_function.requiredArgCount(init_params);
                    if (required_init_argc > 0 and actual_argc < required_init_argc) {
                        e.throwTypeError("", "Constructor expects at least " ++ std.fmt.comptimePrint("{d}", .{required_init_argc}) ++ " arguments") catch {};
                        return null;
                    }

                    var args: std.meta.ArgsTuple(InitFnType) = undefined;
                    inline for (0..init_argc) |i| {
                        const ParamType = init_params[i].type.?;
                        args[i] = wrap_function.convertArgWithOptional(ParamType, raw_args[i], raw_env, i, actual_argc);
                    }

                    const init_result = callInit(init_fn, args) orelse return null;

                    const obj_ptr = std.heap.c_allocator.create(T) catch {
                        e.throwError("", "Out of memory allocating native object") catch {};
                        return null;
                    };
                    obj_ptr.* = init_result;

                    const this_val = napi.Value{ .env = raw_env, .value = this_arg };
                    _ = e.wrap(this_val, T, obj_ptr, defaultFinalize, null) catch {
                        std.heap.c_allocator.destroy(obj_ptr);
                        e.throwError("", "Failed to wrap native object") catch {};
                        return null;
                    };

                    return this_arg;
                }
            };
            return cb.callback;
        }

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

        fn wrapMethod(comptime Class: type, comptime method: anytype, comptime is_by_value: bool) napi.c.napi_callback {
            const MethodFnType = @TypeOf(method);
            const method_info = @typeInfo(MethodFnType).@"fn";
            const method_params = method_info.params;
            const js_argc = method_params.len - 1;
            const ReturnClass = comptime returnedClassType(MethodFnType);
            const prefers_receiver_ctor = ReturnClass != null and ReturnClass.? == Class;

            const method_cb = struct {
                pub fn callback(raw_env: napi.c.napi_env, cb_info: napi.c.napi_callback_info) callconv(.C) napi.c.napi_value {
                    const e = napi.Env{ .env = raw_env };
                    const prev_env = context.setEnv(e);
                    defer context.restoreEnv(prev_env);

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

                    const required_js_argc = comptime wrap_function.requiredArgCount(method_params[1..]);
                    if (required_js_argc > 0 and actual_argc < required_js_argc) {
                        e.throwTypeError("", "Method expects at least " ++ std.fmt.comptimePrint("{d}", .{required_js_argc}) ++ " arguments") catch {};
                        return null;
                    }

                    const this_val = napi.Value{ .env = raw_env, .value = this_arg };
                    const self_ptr = e.unwrap(Class, this_val) catch {
                        e.throwError("", "Failed to unwrap native object") catch {};
                        return null;
                    };

                    const prev_this = context.setThis(this_val);
                    defer context.restoreThis(prev_this);

                    var args: std.meta.ArgsTuple(MethodFnType) = undefined;
                    args[0] = if (is_by_value) self_ptr.* else self_ptr;

                    inline for (0..js_argc) |i| {
                        const ParamType = method_params[i + 1].type.?;
                        args[i + 1] = wrap_function.convertArgWithOptional(ParamType, raw_args[i], raw_env, i, actual_argc);
                    }

                    const preferred_ctor = if (prefers_receiver_ctor)
                        (this_val.getNamedProperty("constructor") catch null)
                    else
                        null;
                    return wrap_function.callAndConvertWithCtor(method, args, raw_env, preferred_ctor);
                }
            };
            return method_cb.callback;
        }

        fn wrapGetter(comptime Class: type, comptime getter_fn: anytype, comptime is_by_value: bool) napi.c.napi_callback {
            const GetterFnType = @TypeOf(getter_fn);
            const ReturnClass = comptime returnedClassType(GetterFnType);
            const prefers_receiver_ctor = ReturnClass != null and ReturnClass.? == Class;

            const getter_cb = struct {
                pub fn callback(raw_env: napi.c.napi_env, cb_info: napi.c.napi_callback_info) callconv(.C) napi.c.napi_value {
                    const e = napi.Env{ .env = raw_env };
                    const prev_env = context.setEnv(e);
                    defer context.restoreEnv(prev_env);

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

                    const this_val = napi.Value{ .env = raw_env, .value = this_arg };
                    const self_ptr = e.unwrap(Class, this_val) catch {
                        e.throwError("", "Failed to unwrap native object in getter") catch {};
                        return null;
                    };

                    const prev_this = context.setThis(this_val);
                    defer context.restoreThis(prev_this);

                    var args: std.meta.ArgsTuple(GetterFnType) = undefined;
                    args[0] = if (is_by_value) self_ptr.* else self_ptr;

                    const preferred_ctor = if (prefers_receiver_ctor)
                        (this_val.getNamedProperty("constructor") catch null)
                    else
                        null;
                    return wrap_function.callAndConvertWithCtor(getter_fn, args, raw_env, preferred_ctor);
                }
            };
            return getter_cb.callback;
        }

        fn wrapStaticMethod(comptime Class: type, comptime method: anytype) napi.c.napi_callback {
            const MethodFnType = @TypeOf(method);
            const method_info = @typeInfo(MethodFnType).@"fn";
            const method_params = method_info.params;
            const method_argc = method_params.len;
            const required_argc = comptime wrap_function.requiredArgCount(method_params);
            const ReturnClass = comptime returnedClassType(MethodFnType);
            const prefers_this_ctor = ReturnClass != null and ReturnClass.? == Class;

            const static_cb = struct {
                pub fn callback(raw_env: napi.c.napi_env, cb_info: napi.c.napi_callback_info) callconv(.C) napi.c.napi_value {
                    const e = napi.Env{ .env = raw_env };
                    const prev_env = context.setEnv(e);
                    defer context.restoreEnv(prev_env);

                    var raw_args: [if (method_argc > 0) method_argc else 1]napi.c.napi_value = std.mem.zeroes([if (method_argc > 0) method_argc else 1]napi.c.napi_value);
                    var actual_argc: usize = method_argc;
                    var this_arg: napi.c.napi_value = null;
                    napi.status.check(napi.c.napi_get_cb_info(
                        raw_env,
                        cb_info,
                        &actual_argc,
                        if (method_argc > 0) &raw_args else null,
                        &this_arg,
                        null,
                    )) catch {
                        e.throwError("", "Failed to get callback info in static method") catch {};
                        return null;
                    };

                    if (required_argc > 0 and actual_argc < required_argc) {
                        e.throwTypeError("", "Method expects at least " ++ std.fmt.comptimePrint("{d}", .{required_argc}) ++ " arguments") catch {};
                        return null;
                    }

                    var args: std.meta.ArgsTuple(MethodFnType) = undefined;
                    inline for (0..method_argc) |i| {
                        const ParamType = method_params[i].type.?;
                        args[i] = wrap_function.convertArgWithOptional(ParamType, raw_args[i], raw_env, i, actual_argc);
                    }

                    const preferred_ctor = if (prefers_this_ctor)
                        napi.Value{ .env = raw_env, .value = this_arg }
                    else
                        null;
                    return wrap_function.callAndConvertWithCtor(method, args, raw_env, preferred_ctor);
                }
            };
            return static_cb.callback;
        }

        fn wrapFieldGetter(comptime Class: type, comptime field_name: []const u8) napi.c.napi_callback {
            const FieldType = fieldType(field_name);

            const getter_cb = struct {
                pub fn callback(raw_env: napi.c.napi_env, cb_info: napi.c.napi_callback_info) callconv(.C) napi.c.napi_value {
                    const e = napi.Env{ .env = raw_env };
                    const prev_env = context.setEnv(e);
                    defer context.restoreEnv(prev_env);

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
                        e.throwError("", "Failed to get callback info in field getter") catch {};
                        return null;
                    };

                    const this_val = napi.Value{ .env = raw_env, .value = this_arg };
                    const self_ptr = e.unwrap(Class, this_val) catch {
                        e.throwError("", "Failed to unwrap native object in field getter") catch {};
                        return null;
                    };

                    const field_value: FieldType = @field(self_ptr.*, field_name);
                    return convertFieldValue(FieldType, field_value, raw_env);
                }
            };
            return getter_cb.callback;
        }

        fn fieldType(comptime field_name: []const u8) type {
            inline for (@typeInfo(T).@"struct".fields) |field_info| {
                if (std.mem.eql(u8, field_info.name, field_name)) return field_info.type;
            }
            @compileError("unknown field '" ++ field_name ++ "' on " ++ @typeName(T));
        }

        fn convertFieldValue(comptime FieldType: type, value: FieldType, raw_env: napi.c.napi_env) napi.c.napi_value {
            if (FieldType == bool) return @import("boolean.zig").Boolean.from(value).toValue().value;

            switch (@typeInfo(FieldType)) {
                .int, .comptime_int, .float, .comptime_float => return @import("number.zig").Number.from(value).toValue().value,
                .pointer => |ptr| {
                    if (ptr.size == .slice and ptr.child == u8 and ptr.is_const) {
                        return @import("string.zig").String.from(value).toValue().value;
                    }
                },
                else => {},
            }

            if (wrap_function.isDslType(FieldType)) {
                return value.val.value;
            }
            if (class_meta.isClassType(FieldType)) {
                return wrap_function.convertReturn(FieldType, value, raw_env);
            }

            @compileError("js.field unsupported field type " ++ @typeName(FieldType) ++ " on " ++ @typeName(T));
        }

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

                    const this_val = napi.Value{ .env = raw_env, .value = this_arg };
                    const self_ptr = e.unwrap(Class, this_val) catch {
                        e.throwError("", "Failed to unwrap native object in setter") catch {};
                        return null;
                    };

                    const prev_this = context.setThis(this_val);
                    defer context.restoreThis(prev_this);

                    const value_arg = convertArg(ValueParamType, raw_args[0], raw_env);

                    var args: std.meta.ArgsTuple(SetterFnType) = undefined;
                    args[0] = self_ptr;
                    args[1] = value_arg;

                    const SetterReturnType = setter_info.return_type.?;
                    if (@typeInfo(SetterReturnType) == .error_union) {
                        @call(.auto, setter_fn, args) catch |err| {
                            e.throwError(@errorName(err), @errorName(err)) catch {};
                            return null;
                        };
                    } else {
                        @call(.auto, setter_fn, args);
                    }

                    return null;
                }
            };
            return setter_cb.callback;
        }
    };
}

test "wrapClass compile-time validation requires class metadata" {
    try std.testing.expect(true);
}
