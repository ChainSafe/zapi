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
            if (T == i32) {
                return try value.getValueInt32();
            }
            if (T == u32) {
                return try value.getValueUint32();
            }
            if (i.bits < 32) {
                if (i.signedness == .signed) {
                    return @intCast(try value.getValueInt32());
                } else {
                    return @intCast(try value.getValueUint32());
                }
            }
            return @intCast(try value.getValueInt64());
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
            if (T == i32) {
                return try env.createInt32(v);
            }
            if (T == u32) {
                return try env.createUint32(v);
            }
            if (i.bits < 32) {
                if (i.signedness == .signed) {
                    return try env.createInt32(v);
                } else {
                    return try env.createUint32(v);
                }
            }
            return try env.createInt64(@intCast(v));
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
                if (h == .string) {
                    return try env.createStringUtf8(@ptrCast(v));
                } else if (h == .buffer or h == .auto) {
                    return try env.createBufferCopy(@ptrCast(v), null);
                }
            }
            const child_type_info = @typeInfo(p.child);
            if (p.size == .one and child_type_info == .array and child_type_info.array.child == u8) {
                return try env.createBufferCopy(@ptrCast(v), null);
            }
            return error.GenericFailure; // Unsupported pointer type
        },
        .error_union => |eu| {
            const non_error_v = v catch |err| {
                env.throwError(@errorName(err), @errorName(err)) catch {};
                return Value.nullptr;
            };
            return try toValue(eu.payload, non_error_v, env, hint);
        },
        .void => {
            return try env.getUndefined();
        },
        else => {
            return error.GenericFailure; // Unsupported type
        },
    }
}
