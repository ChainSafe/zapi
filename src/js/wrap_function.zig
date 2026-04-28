const std = @import("std");
const napi = @import("../napi.zig");
const context = @import("context.zig");
const class_meta = @import("class_meta.zig");
const class_runtime = @import("class_runtime.zig");

/// Checks whether `T` is a ZAPI DSL wrapper type (a struct with a `val: napi.Value` field).
///
/// This comptime function is used internally by the DSL to determine if a Zig
/// type should be treated as a JavaScript value wrapper. It is exposed as an
/// advanced helper for custom metaprogramming and type introspection.
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

/// Checks if `T` is a ZAPI DSL type, `napi.Value`, an N-API class type, or an optional
/// wrapping one of those (e.g., `?js.Number`, `?*MyClass`).
///
/// This comptime function assists in validating argument and return types for
/// DSL-wrapped functions and methods.
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

/// Counts the number of required (non-optional) parameters in a function signature.
///
/// This comptime function is used to validate the `argc` passed from JavaScript
/// against the expected number of required arguments in the Zig function.
pub fn requiredArgCount(comptime params: []const std.builtin.Type.Fn.Param) usize {
    var count: usize = 0;
    for (params) |p| {
        const PT = p.type orelse continue;
        if (@typeInfo(PT) != .optional) count += 1;
    }
    return count;
}

fn normalizedArgType(comptime T: type) type {
    if (@typeInfo(T) == .optional) return @typeInfo(T).optional.child;
    return T;
}

fn typedArrayName(comptime array_type: napi.value_types.TypedarrayType) []const u8 {
    return switch (array_type) {
        .int8 => "Int8Array",
        .uint8 => "Uint8Array",
        .uint8_clamped => "Uint8ClampedArray",
        .int16 => "Int16Array",
        .uint16 => "Uint16Array",
        .int32 => "Int32Array",
        .uint32 => "Uint32Array",
        .float32 => "Float32Array",
        .float64 => "Float64Array",
        .bigint64 => "BigInt64Array",
        .biguint64 => "BigUint64Array",
    };
}

fn argTypeDescription(comptime T: type) []const u8 {
    const Inner = normalizedArgType(T);

    if (Inner == napi.Value) return "a JavaScript value";
    if (comptime isDslType(Inner)) {
        if (Inner == @import("number.zig").Number) return "a number";
        if (Inner == @import("string.zig").String) return "a string";
        if (Inner == @import("boolean.zig").Boolean) return "a boolean";
        if (Inner == @import("bigint.zig").BigInt) return "a bigint";
        if (Inner == @import("date.zig").Date) return "a Date";
        if (Inner == @import("array.zig").Array) return "an Array";
        if (Inner == @import("function.zig").Function) return "a function";
        if (@hasDecl(Inner, "expected_array_type")) return comptime ("a " ++ typedArrayName(Inner.expected_array_type));
        return "a compatible JavaScript value";
    }

    if (comptime class_meta.isClassType(Inner)) return "an instance of " ++ @typeName(Inner);
    if (@typeInfo(Inner) == .pointer) {
        const ptr = @typeInfo(Inner).pointer;
        if (ptr.size == .one and class_meta.isClassType(ptr.child)) {
            return "an instance of " ++ @typeName(ptr.child);
        }
    }

    return "a compatible JavaScript value";
}

/// Throws a JavaScript `TypeError` in the current N-API environment, indicating
/// that a function argument has an incorrect type.
///
/// This function formats an error message like "Argument N must be `expected_type`"
/// based on the `arg_index` and the expected Zig type `T`.
/// Panics if N-API error creation fails.
pub fn throwArgTypeError(e: napi.Env, comptime T: type, arg_index: usize) void {
    var buf: [128:0]u8 = undefined;
    const message = std.fmt.bufPrintZ(&buf, "Argument {d} must be {s}", .{ arg_index + 1, argTypeDescription(T) }) catch return;
    e.throwTypeError("", message) catch {};
}

fn validateDslArg(comptime T: type, value: napi.Value) !void {
    if (T == napi.Value) return;
    if (!comptime isDslType(T)) return;
    if (@hasDecl(T, "validateArg")) {
        try T.validateArg(value);
    }
}

/// Converts a raw `napi.c.napi_value` (JavaScript value) into a Zig type.
///
/// This function handles conversion to `napi.Value`, ZAPI DSL wrapper types
/// (e.g., `js.Number`), and N-API class types (`*MyClass` or `MyClass`).
/// It performs runtime type validation for DSL wrapper types and unwraps native
/// pointers for class types.
/// Returns `error.TypeMismatch` if type validation fails or an N-API class
/// cannot be unwrapped. Compile-time error for unsupported `T` type.
pub fn convertArg(comptime T: type, raw: napi.c.napi_value, env: napi.c.napi_env) !T {
    const value = napi.Value{ .env = env, .value = raw };

    if (T == napi.Value) {
        return value;
    }
    if (comptime isDslType(T)) {
        try validateDslArg(T, value);
        return T{ .val = value };
    }
    if (comptime class_meta.isClassType(T)) {
        const e = napi.Env{ .env = env };
        const ptr = e.unwrapChecked(T, value, class_runtime.typeTag(T)) catch return error.TypeMismatch;
        return ptr.*;
    }
    switch (@typeInfo(T)) {
        .pointer => |ptr| {
            if (ptr.size == .one and class_meta.isClassType(ptr.child)) {
                const e = napi.Env{ .env = env };
                return e.unwrapChecked(ptr.child, value, class_runtime.typeTag(ptr.child)) catch error.TypeMismatch;
            }
        },
        else => {},
    }
    @compileError("convertArg: unsupported type " ++ @typeName(T));
}

/// Converts a raw `napi.c.napi_value` into a Zig type, specifically handling
/// optional types (`?T`).
///
/// If the raw value corresponds to an omitted argument (`param_index >= actual_argc`)
/// or is explicitly JavaScript `undefined`, it returns `null` for optional Zig types.
/// Otherwise, it performs conversion using `convertArg`.
pub fn convertArgWithOptional(
    comptime T: type,
    raw: napi.c.napi_value,
    env: napi.c.napi_env,
    param_index: usize,
    actual_argc: usize,
) !T {
    if (@typeInfo(T) == .optional) {
        if (param_index >= actual_argc) return null;
        const raw_value = napi.Value{ .env = env, .value = raw };
        if ((try raw_value.typeof()) == .undefined) return null;
        const Inner = @typeInfo(T).optional.child;
        return try convertArg(Inner, raw, env);
    }
    return try convertArg(T, raw, env);
}

/// Converts a Zig value into a raw `napi.c.napi_value`, handling various DSL
/// types, `napi.Value`, `void`, and N-API classes.
///
/// This function is used internally by the DSL when a Zig function returns a
/// value that needs to be marshalled back to JavaScript. It handles special
/// cases like `void` (returns JS `undefined`) and materializes N-API class
/// instances if necessary. A `preferred_ctor` can be provided for class
/// materialization.
/// Panics if N-API operations fail for `void` or class materialization.
/// Compile-time error for unsupported `T` type.
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

/// Converts a Zig value into a raw `napi.c.napi_value`.
///
/// This is a convenience wrapper around `convertReturnWithCtor` that does not
/// provide a preferred constructor for class materialization.
pub fn convertReturn(comptime T: type, value: T, env: napi.c.napi_env) napi.c.napi_value {
    return convertReturnWithCtor(T, value, env, null);
}

/// Calls the user-provided Zig function with the given arguments and converts
/// its return value to a raw `napi.c.napi_value`.
///
/// This comptime function handles Zig `error unions` (`!T`), `optional` types (`?T`),
/// and combinations (`!?T`). If the function returns an error, it throws a
/// JavaScript `Error`. If it returns `null` or `undefined`, it returns JS `undefined`.
/// A `preferred_ctor` can be provided for class materialization in return types.
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

/// Calls the user-provided Zig function with the given arguments and converts
/// its return value to a raw `napi.c.napi_value`.
///
/// This is a convenience wrapper around `callAndConvertWithCtor` that does not
/// provide a preferred constructor for class materialization.
pub fn callAndConvert(comptime func: anytype, args: std.meta.ArgsTuple(@TypeOf(func)), env: napi.c.napi_env) napi.c.napi_value {
    return callAndConvertWithCtor(func, args, env, null);
}

/// Generates a C-ABI `napi_callback` that wraps a ZAPI DSL-typed Zig function.
///
/// This function is the core of the ZAPI DSL's function export mechanism. The
/// generated callback takes raw N-API arguments and performs the following steps:
///   1. Sets the thread-local `napi_env` via `context.setEnv`/`context.restoreEnv`.
///   2. Extracts JavaScript arguments (`raw_args`, `this_arg`) via `napi_get_cb_info`.
///   3. Converts each argument to its corresponding ZAPI DSL type via `convertArgWithOptional`.
///   4. Calls the user's Zig function and handles its return value (including errors
///      and optionals) via `callAndConvert`.
///   5. Sets up thread-local `thisArg` context if it's an instance method/getter/setter.
///
/// Panics if N-API operations fail during callback info retrieval or argument conversion.
pub fn wrapFunction(comptime func: anytype) napi.c.napi_callback {
    const FnType = @TypeOf(func);
    const fn_info = @typeInfo(FnType).@"fn";
    const params = fn_info.params;
    const argc = params.len;
    const required_argc = comptime requiredArgCount(params);

    const wrapper = struct {
        pub fn callback(raw_env: napi.c.napi_env, cb_info: napi.c.napi_callback_info) callconv(.c) napi.c.napi_value {
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
                args[i] = convertArgWithOptional(ParamType, raw_args[i], raw_env, i, actual_argc) catch {
                    throwArgTypeError(e, ParamType, i);
                    return null;
                };
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

test "argTypeDescription names typed arrays and unwraps optionals" {
    const typed_arrays = @import("typed_arrays.zig");

    try std.testing.expectEqualStrings("a number", argTypeDescription(?@import("number.zig").Number));
    try std.testing.expectEqualStrings("a Uint8Array", argTypeDescription(typed_arrays.Uint8Array));
}
