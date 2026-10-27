const std = @import("std");
const c = @import("c.zig").c;
const status = @import("status.zig");
const Env = @import("Env.zig");
const OwnedBuffer = @import("OwnedBuffer.zig");
const Value = @import("Value.zig");

/// Converts a JS value into `T`. Composite types (optionals, enums, structs,
/// tuples, arrays and slices) are converted recursively and pass `hint` down
/// to their elements. Strings and slices are allocated from `allocator`.
pub fn fromValue(
    comptime T: type,
    value: Value,
    comptime hint: anytype,
    allocator: std.mem.Allocator,
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
        .optional => |o| {
            return switch (try value.typeof()) {
                .null, .undefined => null,
                else => try fromValue(o.child, value, hint, allocator),
            };
        },
        .@"enum" => |e| {
            const n = try fromValue(e.tag_type, value, .auto, allocator);
            return std.enums.fromInt(T, n) orelse error.InvalidArg;
        },
        .array => |a| {
            try expectArrayLength(value, a.len);
            var result: T = undefined;
            for (&result, 0..) |*item, i| {
                item.* = try fromValue(a.child, try value.getElement(@intCast(i)), hint, allocator);
            }
            return result;
        },
        .@"struct" => |s| {
            var result: T = undefined;
            if (s.is_tuple) {
                try expectArrayLength(value, s.fields.len);
                inline for (s.fields, 0..) |field, i| {
                    @field(result, field.name) = try fromValue(field.type, try value.getElement(i), hint, allocator);
                }
            } else {
                if ((try value.typeof()) != .object) return error.ObjectExpected;
                inline for (s.fields) |field| {
                    const prop = try value.getNamedProperty(field.name ++ "");
                    @field(result, field.name) = try fromValue(field.type, prop, hint, allocator);
                }
            }
            return result;
        },
        .pointer => |p| {
            if (p.size != .slice or p.sentinel_ptr != null) {
                return error.GenericFailure; // Unsupported pointer type
            }
            if (p.child == u8) {
                return try bytesFromValue(value, hint, allocator);
            }
            const len = try value.getArrayLength();
            const items = try allocator.alloc(p.child, len);
            for (items, 0..) |*item, i| {
                item.* = try fromValue(p.child, try value.getElement(@intCast(i)), hint, allocator);
            }
            return items;
        },
        else => {
            return error.GenericFailure; // Unsupported type
        },
    }
}

/// `.buffer` borrows the Buffer's memory, `.string` copies a JS string into
/// `allocator`, and `.auto` accepts either.
fn bytesFromValue(value: Value, comptime hint: anytype, allocator: std.mem.Allocator) ![]u8 {
    if (hint == .buffer) return try value.getBufferInfo();
    if (hint != .string and (try value.typeof()) != .string) return try value.getBufferInfo();

    var len: usize = 0;
    try status.check(c.napi_get_value_string_utf8(value.env, value.value, null, 0, &len));
    // N-API always writes a null terminator, so the buffer needs one extra byte.
    const buf = try allocator.alloc(u8, len + 1);
    const str = try value.getValueStringUtf8(buf);
    return buf[0..str.len];
}

fn expectArrayLength(value: Value, len: usize) !void {
    if (!try value.isArray()) return error.ArrayExpected;
    if ((try value.getArrayLength()) != len) return error.InvalidArg;
}

pub fn toValue(
    comptime T: type,
    v: T,
    env: Env,
    comptime hint: anytype,
) !Value {
    const type_info = @typeInfo(T);
    comptime {
        const return_type = switch (type_info) {
            .error_union => |error_union| error_union.payload,
            else => T,
        };
        if (hint == .external_buffer and return_type != OwnedBuffer) {
            @compileError("external_buffer returns require an OwnedBuffer");
        }
        if (return_type == OwnedBuffer and hint != .external_buffer) {
            @compileError("OwnedBuffer returns require the external_buffer hint");
        }
    }

    if (T == OwnedBuffer) {
        var buffer = v;
        defer buffer.deinit();
        return try buffer.intoValue(env);
    }

    switch (type_info) {
        .bool => {
            return try env.getBoolean(v);
        },
        .int => |i| {
            if (i.signedness == .signed) {
                if (i.bits <= 32) {
                    return try env.createInt32(std.math.cast(i32, v) orelse return error.InvalidArg);
                }
                return try env.createInt64(std.math.cast(i64, v) orelse return error.InvalidArg);
            }

            if (i.bits <= 32) {
                return try env.createUint32(std.math.cast(u32, v) orelse return error.InvalidArg);
            }
            return try env.createInt64(std.math.cast(i64, v) orelse return error.InvalidArg);
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
                } else if (h == .buffer or h == .auto) {
                    return try env.createBufferCopy(bytes, null);
                }
            }
            const child_type_info = @typeInfo(p.child);
            if (p.size == .one and child_type_info == .array and child_type_info.array.child == u8) {
                return try env.createBufferCopy(@ptrCast(v), null);
            }
            if (p.size == .slice) {
                return try arrayToValue(p.child, v, env, hint);
            }
            return error.GenericFailure; // Unsupported pointer type
        },
        .optional => |o| {
            if (v) |inner| return try toValue(o.child, inner, env, hint);
            return try env.getNull();
        },
        .@"enum" => |e| {
            return try toValue(e.tag_type, @intFromEnum(v), env, .auto);
        },
        .array => |a| {
            return try arrayToValue(a.child, &v, env, hint);
        },
        .@"struct" => |s| {
            if (s.is_tuple) {
                const array = try env.createArrayWithLength(s.fields.len);
                inline for (s.fields, 0..) |field, i| {
                    try array.setElement(i, try toValue(field.type, @field(v, field.name), env, hint));
                }
                return array;
            }
            const object = try env.createObject();
            inline for (s.fields) |field| {
                try object.setNamedProperty(field.name ++ "", try toValue(field.type, @field(v, field.name), env, hint));
            }
            return object;
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

fn arrayToValue(comptime Child: type, items: []const Child, env: Env, comptime hint: anytype) !Value {
    const array = try env.createArrayWithLength(items.len);
    for (items, 0..) |item, i| {
        try array.setElement(@intCast(i), try toValue(Child, item, env, hint));
    }
    return array;
}
