const std = @import("std");
const napi = @import("../napi.zig");
const context = @import("context.zig");
const class_meta = @import("class_meta.zig");
const class_runtime = @import("class_runtime.zig");

/// Checks whether `T` is a DSL wrapper type (a struct with a `val: napi.Value` field).
pub fn isDslType(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info != .@"struct") return false;
    inline for (info.@"struct".fields) |field| {
        if (std.mem.eql(u8, field.name, "val") and field.type == napi.Value) {
            return true;
        }
    }
    return false;
}

/// Checks if T is a DSL type, napi.Value, or an optional wrapping one of those.
pub fn isDslOrOptionalDsl(comptime T: type) bool {
    if (T == napi.Value) return true;
    if (isDslType(T)) return true;
    if (class_meta.isClassType(T)) return true;
    if (@typeInfo(T) == .pointer) {
        const ptr = @typeInfo(T).pointer;
        if (ptr.size == .one and class_meta.isClassType(ptr.child)) return true;
    }
    if (@typeInfo(T) == .optional) {
        const Inner = @typeInfo(T).optional.child;
        if (Inner == napi.Value or isDslType(Inner) or class_meta.isClassType(Inner)) return true;
        if (@typeInfo(Inner) == .pointer) {
            const ptr = @typeInfo(Inner).pointer;
            return ptr.size == .one and class_meta.isClassType(ptr.child);
        }
    }
    return false;
}

/// Counts the number of required (non-optional) parameters.
pub fn requiredArgCount(comptime params: []const std.builtin.Type.Fn.Param) usize {
    var count: usize = 0;
    for (params) |p| {
        const PT = p.type orelse continue;
        if (@typeInfo(PT) != .optional) count += 1;
    }
    return count;
}

/// Wraps a raw napi.Value into a DSL wrapper type by setting its `val` field.
pub fn convertArg(comptime T: type, raw: napi.c.napi_value, env: napi.c.napi_env) T {
    if (T == napi.Value) {
        return napi.Value{ .env = env, .value = raw };
    }
    if (comptime isDslType(T)) {
        return T{ .val = napi.Value{ .env = env, .value = raw } };
    }
    if (comptime class_meta.isClassType(T)) {
        const e = napi.Env{ .env = env };
        const obj = napi.Value{ .env = env, .value = raw };
        const ptr = e.unwrap(T, obj) catch @panic("convertArg: failed to unwrap class instance");
        return ptr.*;
    }
    switch (@typeInfo(T)) {
        .pointer => |ptr| {
            if (ptr.size == .one and class_meta.isClassType(ptr.child)) {
                const e = napi.Env{ .env = env };
                const obj = napi.Value{ .env = env, .value = raw };
                return e.unwrap(ptr.child, obj) catch @panic("convertArg: failed to unwrap class pointer");
            }
        },
        else => {},
    }
    @compileError("convertArg: unsupported type " ++ @typeName(T));
}

/// Like convertArg, but handles optional types (?T).
/// Returns null if the argument is omitted or explicitly `undefined`,
/// otherwise wraps as the inner type.
pub fn convertArgWithOptional(
    comptime T: type,
    raw: napi.c.napi_value,
    env: napi.c.napi_env,
    param_index: usize,
    actual_argc: usize,
) T {
    if (@typeInfo(T) == .optional) {
        if (param_index >= actual_argc) return null;
        const raw_value = napi.Value{ .env = env, .value = raw };
        if ((raw_value.typeof() catch null) == .undefined) return null;
        const Inner = @typeInfo(T).optional.child;
        return convertArg(Inner, raw, env);
    }
    return convertArg(T, raw, env);
}

/// Extracts the raw napi_value from a DSL type, napi.Value, or handles void.
pub fn convertReturnWithCtor(comptime T: type, value: T, env: napi.c.napi_env, preferred_ctor: ?napi.Value) napi.c.napi_value {
    if (T == void) {
        var result: napi.c.napi_value = null;
        napi.status.check(napi.c.napi_get_undefined(env, &result)) catch return null;
        return result;
    }
    if (T == napi.Value) {
        return value.value;
    }
    if (comptime isDslType(T)) {
        return value.val.value;
    }
    if (comptime class_meta.isClassType(T)) {
        const e = napi.Env{ .env = env };
        const instance = class_runtime.materializeClassInstance(T, e, value, preferred_ctor) catch {
            e.throwError("", "Failed to materialize returned class instance") catch {};
            return null;
        };
        return instance.value;
    }
    @compileError("convertReturn: unsupported return type " ++ @typeName(T));
}

pub fn convertReturn(comptime T: type, value: T, env: napi.c.napi_env) napi.c.napi_value {
    return convertReturnWithCtor(T, value, env, null);
}

/// Calls the user function with the given args tuple and converts the return value,
/// handling error unions (`!T`), optionals (`?T`), and combinations (`!?T`).
pub fn callAndConvertWithCtor(comptime func: anytype, args: std.meta.ArgsTuple(@TypeOf(func)), env: napi.c.napi_env, preferred_ctor: ?napi.Value) napi.c.napi_value {
    const ReturnType = @typeInfo(@TypeOf(func)).@"fn".return_type.?;

    const ret_info = @typeInfo(ReturnType);

    // !T or !?T — error union
    if (ret_info == .error_union) {
        const result = @call(.auto, func, args) catch |err| {
            const e = napi.Env{ .env = env };
            e.throwError(@errorName(err), @errorName(err)) catch {};
            return null;
        };

        const Payload = ret_info.error_union.payload;
        const payload_info = @typeInfo(Payload);

        // !?T — optional inside error union
        if (payload_info == .optional) {
            if (result) |val| {
                return convertReturnWithCtor(payload_info.optional.child, val, env, preferred_ctor);
            } else {
                var undef: napi.c.napi_value = null;
                napi.status.check(napi.c.napi_get_undefined(env, &undef)) catch return null;
                return undef;
            }
        }

        // !T — plain error union
        return convertReturnWithCtor(Payload, result, env, preferred_ctor);
    }

    // ?T — optional (no error)
    if (ret_info == .optional) {
        const result = @call(.auto, func, args);
        if (result) |val| {
            return convertReturnWithCtor(ret_info.optional.child, val, env, preferred_ctor);
        } else {
            var undef: napi.c.napi_value = null;
            napi.status.check(napi.c.napi_get_undefined(env, &undef)) catch return null;
            return undef;
        }
    }

    // Plain T
    const result = @call(.auto, func, args);
    return convertReturnWithCtor(ReturnType, result, env, preferred_ctor);
}

pub fn callAndConvert(comptime func: anytype, args: std.meta.ArgsTuple(@TypeOf(func)), env: napi.c.napi_env) napi.c.napi_value {
    return callAndConvertWithCtor(func, args, env, null);
}

/// Generates a C-ABI napi_callback that wraps a DSL-typed Zig function.
/// The generated callback:
///   1. Sets the thread-local env via context.setEnv/restoreEnv
///   2. Extracts JS arguments via napi_get_cb_info
///   3. Converts each arg to its DSL type via convertArg
///   4. Calls the user function and handles the return via callAndConvert
pub fn wrapFunction(comptime func: anytype) napi.c.napi_callback {
    const FnType = @TypeOf(func);
    const fn_info = @typeInfo(FnType).@"fn";
    const params = fn_info.params;
    const argc = params.len;
    const required_argc = comptime requiredArgCount(params);

    const wrapper = struct {
        pub fn callback(raw_env: napi.c.napi_env, cb_info: napi.c.napi_callback_info) callconv(.C) napi.c.napi_value {
            const e = napi.Env{ .env = raw_env };
            const prev = context.setEnv(e);
            defer context.restoreEnv(prev);

            var raw_args: [if (argc > 0) argc else 1]napi.c.napi_value = std.mem.zeroes([if (argc > 0) argc else 1]napi.c.napi_value);
            var actual_argc: usize = argc;
            var this_arg: napi.c.napi_value = null;
            napi.status.check(napi.c.napi_get_cb_info(
                raw_env,
                cb_info,
                &actual_argc,
                if (argc > 0) &raw_args else null,
                &this_arg,
                null,
            )) catch {
                e.throwError("", "Failed to get callback info") catch {};
                return null;
            };

            if (required_argc > 0 and actual_argc < required_argc) {
                e.throwTypeError("", "Expected at least " ++ std.fmt.comptimePrint("{d}", .{required_argc}) ++ " arguments") catch {};
                return null;
            }

            var args: std.meta.ArgsTuple(FnType) = undefined;
            inline for (0..argc) |i| {
                const ParamType = params[i].type.?;
                args[i] = convertArgWithOptional(ParamType, raw_args[i], raw_env, i, actual_argc);
            }

            return callAndConvert(func, args, raw_env);
        }
    };
    return wrapper.callback;
}

// Comptime tests — these validate the type-checking logic at compile time.
// They do not require N-API runtime, so they can run in the native test runner.

test "isDslType recognizes DSL types" {
    const FakeDsl = struct { val: napi.Value };
    try std.testing.expect(isDslType(FakeDsl));
}

test "isDslType rejects non-DSL types" {
    try std.testing.expect(!isDslType(u32));
    try std.testing.expect(!isDslType(struct { x: u32 }));
}
