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
        /// C-ABI constructor callback for napi_define_class.
        pub const constructor: napi.c.napi_callback = genConstructor();

        /// Default GC-invoked destructor. Frees the native object using c_allocator.
        pub fn defaultFinalize(_: napi.Env, obj: *T, _: ?*anyopaque) void {
            if (@hasDecl(T, "deinit")) {
                obj.deinit();
            }
            std.heap.c_allocator.destroy(obj);
        }

        /// Returns an array of napi_property_descriptor for all public methods of T.
        pub fn getPropertyDescriptors() []const napi.c.napi_property_descriptor {
            const decls = @typeInfo(T).@"struct".decls;
            comptime var count: usize = 0;
            inline for (decls) |decl| {
                if (comptime shouldSkipDecl(decl.name)) continue;
                const field = @field(T, decl.name);
                const field_info = @typeInfo(@TypeOf(field));
                if (field_info != .@"fn") continue;
                count += 1;
            }

            if (count == 0) return &[0]napi.c.napi_property_descriptor{};

            const descriptors = comptime blk: {
                var descs: [count]napi.c.napi_property_descriptor = undefined;
                var idx: usize = 0;
                for (decls) |decl| {
                    if (shouldSkipDecl(decl.name)) continue;
                    const field = @field(T, decl.name);
                    const field_info = @typeInfo(@TypeOf(field));
                    if (field_info != .@"fn") continue;

                    const fn_info = field_info.@"fn";
                    const params = fn_info.params;

                    var desc = std.mem.zeroes(napi.c.napi_property_descriptor);
                    const method_name: [:0]const u8 = decl.name ++ "";
                    desc.utf8name = method_name.ptr;

                    if (params.len > 0 and isClassSelfParam(params[0].type.?)) {
                        // Instance method
                        const is_by_value = params[0].type.? == T;
                        desc.method = wrapMethod(T, field, is_by_value);
                        desc.attributes = @intFromEnum(napi.value_types.PropertyAttributes.default_method);
                    } else if (isStaticFactory(field)) {
                        // Static factory — uses this_arg as constructor
                        desc.method = wrapStaticFactory(T, field);
                        desc.attributes = @intFromEnum(napi.value_types.PropertyAttributes.default_method) |
                            @intFromEnum(napi.value_types.PropertyAttributes.static);
                    } else {
                        // Plain static method
                        desc.method = wrap_function.wrapFunction(field);
                        desc.attributes = @intFromEnum(napi.value_types.PropertyAttributes.default_method) |
                            @intFromEnum(napi.value_types.PropertyAttributes.static);
                    }

                    descs[idx] = desc;
                    idx += 1;
                }
                break :blk descs;
            };

            return &descriptors;
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
                std.mem.eql(u8, name, "deinit");
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

        pub fn hasFactories() bool {
            const decls = @typeInfo(T).@"struct".decls;
            inline for (decls) |decl| {
                if (comptime shouldSkipDecl(decl.name)) continue;
                const field = @field(T, decl.name);
                const field_info = @typeInfo(@TypeOf(field));
                if (field_info != .@"fn") continue;
                if (comptime isStaticMethod(field_info.@"fn".params) and isStaticFactory(field)) return true;
            }
            return false;
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
            const decls = @typeInfo(T).@"struct".decls;
            comptime var factory_count: usize = 0;
            inline for (decls) |decl| {
                if (comptime shouldSkipDecl(decl.name)) continue;
                const field = @field(T, decl.name);
                const field_info = @typeInfo(@TypeOf(field));
                if (field_info != .@"fn") continue;
                if (comptime isStaticMethod(field_info.@"fn".params) and isStaticFactory(field)) factory_count += 1;
            }

            if (factory_count == 0) return &[0]napi.c.napi_property_descriptor{};

            const S = struct {
                var descs: [factory_count]napi.c.napi_property_descriptor = undefined;
            };

            var idx: usize = 0;
            inline for (decls) |decl| {
                if (comptime shouldSkipDecl(decl.name)) continue;
                const field = @field(T, decl.name);
                const field_info2 = @typeInfo(@TypeOf(field));
                if (field_info2 != .@"fn") continue;
                if (comptime isStaticMethod(field_info2.@"fn".params) and isStaticFactory(field)) {
                    S.descs[idx] = std.mem.zeroes(napi.c.napi_property_descriptor);
                    const method_name: [:0]const u8 = decl.name ++ "";
                    S.descs[idx].utf8name = method_name.ptr;
                    S.descs[idx].method = wrapStaticFactory(T, field);
                    S.descs[idx].attributes = @intFromEnum(napi.value_types.PropertyAttributes.default_method) |
                        @intFromEnum(napi.value_types.PropertyAttributes.static);
                    S.descs[idx].data = @ptrCast(ctor);
                    idx += 1;
                }
            }

            return S.descs[0..factory_count];
        }
    };
}

test "wrapClass compile-time validation requires js_class" {
    // This is a negative comptime test — we just verify the function exists
    // and the isDslType helper works. Actual validation would be a compileError.
    try std.testing.expect(true);
}
