const std = @import("std");
const napi = @import("../napi.zig");
const context = @import("context.zig");

/// Zero-cost wrapper around a JS `number` value.
///
/// This struct provides a type-safe way to interact with JavaScript numbers
/// from Zig, offering methods for conversion to various Zig numeric types and
/// for creating JS numbers from Zig primitives.
///
/// `from()` panics on N-API failure (e.g. invalid env). This is a deliberate
/// design choice to keep DSL signatures clean (no `try` on every construction).
/// N-API creation calls only fail if the environment is invalid, which indicates
/// a programming error. Use `assert*()` variants for the same panic-on-failure
/// pattern when extracting values, or `to*()` variants to get error unions.
pub const Number = struct {
    /// The underlying `napi.Value` representing the JavaScript number.
    val: napi.Value,

    /// Validates if the given `napi.Value` is a JavaScript number.
    ///
    /// Returns an error if the value is not a number, suitable for argument
    /// validation in DSL-wrapped functions.
    pub fn validateArg(val: napi.Value) !void {
        if ((try val.typeof()) != .number) return error.TypeMismatch;
    }

    /// Attempts to convert the JavaScript number to a Zig `i32`.
    ///
    /// Returns an error if the conversion fails (e.g., number is too large).
    pub fn toI32(self: Number) !i32 {
        return self.val.getValueInt32();
    }

    /// Attempts to convert the JavaScript number to a Zig `u32`.
    ///
    /// Returns an error if the conversion fails (e.g., number is negative or too large).
    pub fn toU32(self: Number) !u32 {
        return self.val.getValueUint32();
    }

    /// Attempts to convert the JavaScript number to a Zig `f64`.
    ///
    /// This conversion is generally lossless for most JS numbers, which are typically `f64`.
    pub fn toF64(self: Number) !f64 {
        return self.val.getValueDouble();
    }

    /// Attempts to convert the JavaScript number to a Zig `i64`.
    ///
    /// Returns an error if the conversion fails (e.g., number is too large).
    pub fn toI64(self: Number) !i64 {
        return self.val.getValueInt64();
    }

    /// Converts the JavaScript number to a Zig `i32`, panicking on failure.
    ///
    /// This is a convenience method for cases where the number is guaranteed
    /// to be representable as an `i32`.
    pub fn assertI32(self: Number) i32 {
        return self.toI32() catch @panic("Number.assertI32 failed");
    }

    /// Converts the JavaScript number to a Zig `u32`, panicking on failure.
    ///
    /// This is a convenience method for cases where the number is guaranteed
    /// to be representable as a `u32`.
    pub fn assertU32(self: Number) u32 {
        return self.toU32() catch @panic("Number.assertU32 failed");
    }

    /// Converts the JavaScript number to a Zig `f64`, panicking on failure.
    ///
    /// This is a convenience method for cases where the conversion is guaranteed
    /// (e.g., number is already an `f64` or small integer).
    pub fn assertF64(self: Number) f64 {
        return self.toF64() catch @panic("Number.assertF64 failed");
    }

    /// Converts the JavaScript number to a Zig `i64`, panicking on failure.
    ///
    /// This is a convenience method for cases where the number is guaranteed
    /// to be representable as an `i64`.
    pub fn assertI64(self: Number) i64 {
        return self.toI64() catch @panic("Number.assertI64 failed");
    }

    /// Creates a JavaScript `Number` from a Zig numeric value.
    ///
    /// Accepts integer types (`i8`..`i64`, `u8`..`u64`), float types (`f32`, `f64`),
    /// `comptime_int`, and `comptime_float`.
    ///
    /// Unsigned 64-bit values above `i64` max are created via JS `number`
    /// (`double`), rather than `int64`, so values above `2^53 - 1` may lose
    /// integer precision. Use `BigInt` when exact large integers matter.
    ///
    /// Panics if N-API operations fail (e.g., invalid environment) or for Zig
    /// integer types larger than `u64` (use `BigInt` for `i128`/`u128`).
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
                    } else if (value >= 0 and value <= std.math.maxInt(u64)) {
                        break :blk e.createDouble(@floatFromInt(value)) catch @panic("Number.from: createDouble failed");
                    } else {
                        @compileError("Number.from: value out of range for JS number. Use BigInt for i128/u128.");
                    }
                } else {
                    const info = @typeInfo(T).int;
                    if (info.bits <= 32 and info.signedness == .signed) {
                        break :blk e.createInt32(@intCast(value)) catch @panic("Number.from: createInt32 failed");
                    } else if (info.bits <= 32 and info.signedness == .unsigned) {
                        break :blk e.createUint32(@intCast(value)) catch @panic("Number.from: createUint32 failed");
                    } else if (info.bits <= 64 and info.signedness == .signed) {
                        break :blk e.createInt64(@intCast(value)) catch @panic("Number.from: createInt64 failed");
                    } else if (info.bits <= 64 and info.signedness == .unsigned) {
                        if (value <= std.math.maxInt(i64)) {
                            break :blk e.createInt64(@intCast(value)) catch @panic("Number.from: createInt64 failed");
                        }
                        break :blk e.createDouble(@floatFromInt(value)) catch @panic("Number.from: createDouble failed");
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

    /// Returns the underlying `napi.Value` representation of this JavaScript number.
    pub fn toValue(self: Number) napi.Value {
        return self.val;
    }
};
