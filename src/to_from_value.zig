const std = @import("std");
const Env = @import("Env.zig");
const Value = @import("Value.zig");

pub fn fromValue(
    comptime T: type,
    value: Value,
    comptime hint: anytype,
) !T {
    const type_info = @typeInfo(T);
    switch (type_info) {
        .bool => {
            return try value.getValueBool();
        },
        .int => |i| {
            if (i.signedness == .signed) {
                const n: i64 = if (i.bits <= 32)
                    try value.getValueInt32()
                else
                    try value.getValueInt64();
                return std.math.cast(T, n) orelse error.InvalidArg;
            }

            const n: i64 = if (i.bits <= 32)
                @as(i64, try value.getValueUint32())
            else
                try value.getValueInt64();
            return std.math.cast(T, n) orelse error.InvalidArg;
        },
        .float => {
            if (T == f64) {
                return try value.getValueDouble();
            } else {
                return @floatCast(try value.getValueDouble());
            }
        },
        .pointer => |p| {
            if (p.child == u8 and p.size == .slice) {
                if (hint == .buffer) {
                    return try value.getBufferInfo();
                }
            }
            return error.GenericFailure; // Unsupported pointer type
        },
        else => {
            return error.GenericFailure; // Unsupported type
        },
    }
}

pub fn toValue(
    comptime T: type,
    v: T,
    env: Env,
    comptime hint: anytype,
) !Value {
    const type_info = @typeInfo(T);
    switch (type_info) {
        .bool => {
            return try env.getBoolean(v);
        },
        .int => |i| {
            if (i.signedness == .signed) {
                const n = std.math.cast(i64, v) orelse return error.InvalidArg;
                if (i.bits <= 32) {
                    return try env.createInt32(std.math.cast(i32, n) orelse return error.InvalidArg);
                }
                return try env.createInt64(n);
            }

            const n = std.math.cast(u64, v) orelse return error.InvalidArg;
            if (i.bits <= 32) {
                return try env.createUint32(std.math.cast(u32, n) orelse return error.InvalidArg);
            }
            return try env.createInt64(std.math.cast(i64, n) orelse return error.InvalidArg);
        },
        .float => {
            if (T == f64) {
                return try env.createDouble(v);
            } else {
                return try env.createDouble(@floatCast(v));
            }
        },
        .pointer => |p| {
            const h = hint;
            if (p.child == u8 and p.size == .slice) {
                const bytes: []const u8 = @ptrCast(v);
                if (h == .string) {
                    return try env.createStringUtf8(bytes);
                } else if (h == .external_buffer) {
                    return try env.createExternalBuffer(bytes, null, null);
                } else if (h == .buffer or h == .auto) {
                    return try env.createBufferCopy(bytes, null);
                }
            }
            const child_type_info = @typeInfo(p.child);
            if (p.size == .one and child_type_info == .array and child_type_info.array.child == u8) {
                return try env.createBufferCopy(@ptrCast(v), null);
            }
            return error.GenericFailure; // Unsupported pointer type
        },
        .error_union => |eu| {
            return try toValue(eu.payload, try v, env, hint);
        },
        .void => {
            return try env.getUndefined();
        },
        else => {
            return error.GenericFailure; // Unsupported type
        },
    }
}
