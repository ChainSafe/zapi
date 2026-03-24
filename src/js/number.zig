const std = @import("std");
const napi = @import("../napi.zig");
const context = @import("context.zig");

pub const Number = struct {
    val: napi.Value,

    pub fn toI32(self: Number) !i32 {
        return self.val.getValueInt32();
    }

    pub fn toU32(self: Number) !u32 {
        return self.val.getValueUint32();
    }

    pub fn toF64(self: Number) !f64 {
        return self.val.getValueDouble();
    }

    pub fn toI64(self: Number) !i64 {
        return self.val.getValueInt64();
    }

    pub fn assertI32(self: Number) i32 {
        return self.toI32() catch @panic("Number.assertI32 failed");
    }

    pub fn assertU32(self: Number) u32 {
        return self.toU32() catch @panic("Number.assertU32 failed");
    }

    pub fn assertF64(self: Number) f64 {
        return self.toF64() catch @panic("Number.assertF64 failed");
    }

    pub fn assertI64(self: Number) i64 {
        return self.toI64() catch @panic("Number.assertI64 failed");
    }

    /// Creates a JS Number from a Zig numeric value.
    /// Accepts integer types (i8..i64, u8..u64), float types (f32, f64),
    /// comptime_int, and comptime_float.
    pub fn from(value: anytype) Number {
        const e = context.env();
        const T = @TypeOf(value);
        const val = switch (@typeInfo(T)) {
            .int, .comptime_int => blk: {
                if (@typeInfo(T) == .comptime_int) {
                    if (value >= std.math.minInt(i32) and value <= std.math.maxInt(i32)) {
                        break :blk e.createInt32(@intCast(value)) catch @panic("Number.from: createInt32 failed");
                    } else if (value >= std.math.minInt(i64) and value <= std.math.maxInt(i64)) {
                        break :blk e.createInt64(@intCast(value)) catch @panic("Number.from: createInt64 failed");
                    } else {
                        @compileError("Number.from: value out of range for JS number. Use BigInt for i128/u128.");
                    }
                } else {
                    const info = @typeInfo(T).int;
                    if (info.bits <= 32 and info.signedness == .signed) {
                        break :blk e.createInt32(@intCast(value)) catch @panic("Number.from: createInt32 failed");
                    } else if (info.bits <= 32 and info.signedness == .unsigned) {
                        break :blk e.createUint32(@intCast(value)) catch @panic("Number.from: createUint32 failed");
                    } else if (info.bits <= 64) {
                        break :blk e.createInt64(@intCast(value)) catch @panic("Number.from: createInt64 failed");
                    } else {
                        @compileError("Number.from: integer too large for JS number. Use BigInt for i128/u128.");
                    }
                }
            },
            .float, .comptime_float => blk: {
                break :blk e.createDouble(@floatCast(value)) catch @panic("Number.from: createDouble failed");
            },
            else => @compileError("Number.from: unsupported type " ++ @typeName(T) ++ ". Use integer or float types."),
        };
        return .{ .val = val };
    }

    pub fn toValue(self: Number) napi.Value {
        return self.val;
    }
};
