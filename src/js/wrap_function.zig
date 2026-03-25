const std = @import("std");
const napi = @import("../napi.zig");
const context = @import("context.zig");

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

/// Wraps a raw napi.Value into a DSL wrapper type by setting its `val` field.
pub fn convertArg(comptime T: type, raw: napi.c.napi_value, env: napi.c.napi_env) T {
    if (T == napi.Value) {
        return napi.Value{ .env = env, .value = raw };
    }
    if (comptime isDslType(T)) {
        return T{ .val = napi.Value{ .env = env, .value = raw } };
    }
    @compileError("convertArg: unsupported type " ++ @typeName(T));
}

/// Extracts the raw napi_value from a DSL type, napi.Value, or handles void.
pub fn convertReturn(comptime T: type, value: T, env: napi.c.napi_env) napi.c.napi_value {
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
    @compileError("convertReturn: unsupported return type " ++ @typeName(T));
}

/// Calls the user function with the given args tuple and converts the return value,
/// handling error unions (`!T`), optionals (`?T`), and combinations (`!?T`).
pub fn callAndConvert(comptime func: anytype, args: std.meta.ArgsTuple(@TypeOf(func)), env: napi.c.napi_env) napi.c.napi_value {
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
                return convertReturn(payload_info.optional.child, val, env);
            } else {
                var undef: napi.c.napi_value = null;
                napi.status.check(napi.c.napi_get_undefined(env, &undef)) catch return null;
                return undef;
            }
        }

        // !T — plain error union
        return convertReturn(Payload, result, env);
    }

    // ?T — optional (no error)
    if (ret_info == .optional) {
        const result = @call(.auto, func, args);
        if (result) |val| {
            return convertReturn(ret_info.optional.child, val, env);
        } else {
            var undef: napi.c.napi_value = null;
            napi.status.check(napi.c.napi_get_undefined(env, &undef)) catch return null;
            return undef;
        }
    }

    // Plain T
    const result = @call(.auto, func, args);
    return convertReturn(ReturnType, result, env);
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

    const wrapper = struct {
        pub fn callback(raw_env: napi.c.napi_env, cb_info: napi.c.napi_callback_info) callconv(.C) napi.c.napi_value {
            const e = napi.Env{ .env = raw_env };
            const prev = context.setEnv(e);
            defer context.restoreEnv(prev);

            // Extract arguments
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

            // Validate argument count
            if (argc > 0 and actual_argc < argc) {
                e.throwTypeError("", "Expected " ++ std.fmt.comptimePrint("{d}", .{argc}) ++ " arguments") catch {};
                return null;
            }

            // Build args tuple
            var args: std.meta.ArgsTuple(FnType) = undefined;
            inline for (0..argc) |i| {
                const ParamType = params[i].type.?;
                args[i] = convertArg(ParamType, raw_args[i], raw_env);
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
