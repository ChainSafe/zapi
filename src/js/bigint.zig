const std = @import("std");
const napi = @import("../napi.zig");
const context = @import("context.zig");

pub const BigInt = struct {
    val: napi.Value,

    pub fn validateArg(val: napi.Value) !void {
        if ((try val.typeof()) != .bigint) return error.TypeMismatch;
    }

    /// Returns the i64 value. If lossless is provided, it indicates whether the
    /// conversion was lossless.
    pub fn toI64(self: BigInt, lossless: ?*bool) !i64 {
        return self.val.getValueBigintInt64(lossless);
    }

    /// Returns the u64 value. If lossless is provided, it indicates whether the
    /// conversion was lossless.
    pub fn toU64(self: BigInt, lossless: ?*bool) !u64 {
        return self.val.getValueBigintUint64(lossless);
    }

    /// Returns the i128 value by reading two 64-bit words.
    pub fn toI128(self: BigInt) !i128 {
        var sign_bit: u1 = 0;
        var words: [2]u64 = .{ 0, 0 };
        const result = try self.val.getValueBigintWords(&sign_bit, &words);
        const lo: u128 = result[0];
        const hi: u128 = if (result.len > 1) result[1] else 0;
        const magnitude: u128 = (hi << 64) | lo;
        if (sign_bit == 1) {
            // Negative: negate the magnitude
            if (magnitude == 0) return 0;
            return -@as(i128, @intCast(magnitude));
        }
        return @intCast(magnitude);
    }

    pub fn assertI64(self: BigInt) i64 {
        return self.toI64(null) catch @panic("BigInt.assertI64 failed");
    }

    pub fn assertU64(self: BigInt) u64 {
        return self.toU64(null) catch @panic("BigInt.assertU64 failed");
    }

    pub fn assertI128(self: BigInt) i128 {
        return self.toI128() catch @panic("BigInt.assertI128 failed");
    }

    /// Creates a JS BigInt from a Zig integer value.
    /// Accepts i64, u64, and comptime_int.
    pub fn from(value: anytype) BigInt {
        const e = context.env();
        const T = @TypeOf(value);
        const val = switch (@typeInfo(T)) {
            .int, .comptime_int => blk: {
                if (@typeInfo(T) == .comptime_int) {
                    if (value >= std.math.minInt(i64) and value <= std.math.maxInt(i64)) {
                        break :blk e.createBigintInt64(@intCast(value)) catch @panic("BigInt.from: createBigintInt64 failed");
                    } else if (value >= 0 and value <= std.math.maxInt(u64)) {
                        break :blk e.createBigintUint64(@intCast(value)) catch @panic("BigInt.from: createBigintUint64 failed");
                    } else {
                        @compileError("BigInt.from: comptime_int value out of range for i64/u64. Use fromWords for larger values.");
                    }
                } else {
                    const info = @typeInfo(T).int;
                    if (info.signedness == .signed and info.bits <= 64) {
                        break :blk e.createBigintInt64(@intCast(value)) catch @panic("BigInt.from: createBigintInt64 failed");
                    } else if (info.signedness == .unsigned and info.bits <= 64) {
                        break :blk e.createBigintUint64(@intCast(value)) catch @panic("BigInt.from: createBigintUint64 failed");
                    } else {
                        @compileError("BigInt.from: integer too large. Use fromWords for i128/u128.");
                    }
                }
            },
            else => @compileError("BigInt.from: unsupported type " ++ @typeName(T) ++ ". Use integer types."),
        };
        return .{ .val = val };
    }

    pub fn toValue(self: BigInt) napi.Value {
        return self.val;
    }
};
