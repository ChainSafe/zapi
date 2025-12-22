const std = @import("std");
const Env = @import("Env.zig");
const Value = @import("Value.zig");
const Callback = @import("callback.zig").Callback;
const CallbackInfo = @import("callback_info.zig").CallbackInfo;
const toValue = @import("to_from_value.zig").toValue;
const fromValue = @import("to_from_value.zig").fromValue;

pub fn createCallback(
    comptime argc_cap: usize,
    comptime func: anytype,
    comptime options: anytype,
) Callback(argc_cap) {
    const fn_type = @TypeOf(func);
    const fn_type_info = @typeInfo(fn_type);
    comptime {
        if (fn_type_info != .@"fn") {
            @compileError("func must be a function");
        }
    }
    const fn_info = fn_type_info.@"fn";

    const Args = std.meta.ArgsTuple(fn_type);

    return struct {
        pub fn f(
            env: Env,
            info: CallbackInfo(argc_cap),
        ) anyerror!Value {
            var args: Args = undefined;

            var cb_arg_i: usize = 0;
            inline for (0..fn_info.params.len) |i| {
                const arg_hint = comptime getArgsHint(options, i);
                if (arg_hint == .data) {
                    args[i] = @alignCast(@ptrCast(info.data));
                } else if (arg_hint == .env) {
                    args[i] = env;
                } else if (arg_hint == .value) {
                    args[i] = info.arg(cb_arg_i);
                    cb_arg_i += 1;
                } else {
                    args[i] = try fromValue(fn_info.params[i].type.?, info.arg(cb_arg_i), arg_hint);
                    cb_arg_i += 1;
                }
            }
            const result = @call(.auto, func, args);
            const returns_hint = comptime getReturnsHint(options);
            if (returns_hint == .value) {
                return result;
            }
            return try toValue(fn_info.return_type.?, result, env, returns_hint);
        }
    }.f;
}

pub const ArgHint = enum {
    auto,

    buffer,
    string,

    /// userdata pointer, usually a struct
    data,

    /// napi.Env
    env,

    /// napi.Value
    value,
};

pub const ReturnsHint = enum {
    auto,
    buffer,
    string,

    /// napi.Value
    value,
};

pub fn getArgsHint(
    comptime options: anytype,
    comptime index: usize,
) ArgHint {
    if (std.meta.fieldIndex(@TypeOf(options), "args") == null) {
        return .auto;
    }
    const args_options = @field(options, "args");
    return @field(args_options, std.fmt.comptimePrint("{d}", .{index}));
}

pub fn getReturnsHint(
    comptime options: anytype,
) ReturnsHint {
    if (std.meta.fieldIndex(@TypeOf(options), "returns") == null) {
        return .auto;
    }
    return @field(options, "returns");
}
