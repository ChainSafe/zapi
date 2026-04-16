const std = @import("std");
const napi = @import("../napi.zig");
const context = @import("context.zig");

pub const BigInt = struct {
    /// The underlying `napi.Value` representing the JavaScript BigInt.
    val: napi.Value,

    /// Validates if the given `napi.Value` is a JavaScript BigInt.
    ///
    /// Returns an error (`error.TypeMismatch`) if the value is not a BigInt,
    /// suitable for argument validation in DSL-wrapped functions.
    pub fn validateArg(val: napi.Value) !void {
        if ((try val.typeof()) != .bigint) return error.TypeMismatch;
    }

    /// Attempts to convert the JavaScript BigInt to a Zig `i64`.
    ///
    /// If `lossless` is provided, it will be set to `true` if the BigInt can be
    /// represented exactly as an `i64`, and `false` otherwise (e.g., if the
    /// BigInt is too large or too small for `i64`).
    /// Returns an error if the conversion fails or the `napi_env` is invalid.
    pub fn toI64(self: BigInt, lossless: ?*bool) !i64 {
        return self.val.getValueBigintInt64(lossless);
    }

    /// Attempts to convert the JavaScript BigInt to a Zig `u64`.
    ///
    /// If `lossless` is provided, it will be set to `true` if the BigInt can be
    /// represented exactly as a `u64`, and `false` otherwise.
    /// Returns an error if the conversion fails (e.g., BigInt is negative) or
    /// the `napi_env` is invalid.
    pub fn toU64(self: BigInt, lossless: ?*bool) !u64 {
        return self.val.getValueBigintUint64(lossless);
    }

    /// Attempts to convert the JavaScript BigInt to a Zig `i128`.
    ///
    /// This function reads the BigInt as two 64-bit words and reconstructs it
    /// into a Zig `i128`. It handles both positive and negative BigInts.
    /// Returns an error if N-API operations fail.
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

    /// Converts the JavaScript BigInt to a Zig `i64`, panicking on failure.
    ///
    /// This is a convenience method for cases where the BigInt is guaranteed
    /// to be representable as an `i64` without loss.
    pub fn assertI64(self: BigInt) i64 {
        return self.toI64(null) catch @panic("BigInt.assertI64 failed");
    }

    /// Converts the JavaScript BigInt to a Zig `u64`, panicking on failure.
    ///
    /// This is a convenience method for cases where the BigInt is guaranteed
    /// to be representable as a `u64` without loss.
    pub fn assertU64(self: BigInt) u64 {
        return self.toU64(null) catch @panic("BigInt.assertU64 failed");
    }

    /// Converts the JavaScript BigInt to a Zig `i128`, panicking on failure.
    ///
    /// This is a convenience method for cases where the BigInt is guaranteed
    /// to be representable as an `i128`.
    pub fn assertI128(self: BigInt) i128 {
        return self.toI128() catch @panic("BigInt.assertI128 failed");
    }

    /// Creates a JavaScript `BigInt` from a Zig integer value.
    ///
    /// Accepts `i64`, `u64`, and `comptime_int` values within this range.
    /// For `i128`/`u128` values, use `fromWords` (not currently exposed but
    /// available at the `napi.Env` level).
    ///
    /// Panics if N-API operations fail (e.g., invalid environment) or for Zig
    /// integer types larger than `u64` that cannot be converted to `i64`/`u64`.
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

    /// Returns the underlying `napi.Value` representation of this JavaScript BigInt.
    pub fn toValue(self: BigInt) napi.Value {
        return self.val;
    }
};
