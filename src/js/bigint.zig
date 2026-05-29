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

    /// Attempts to convert the JavaScript BigInt exactly to a Zig `i64`.
    ///
    /// Returns `error.InvalidArg` if the value is outside the `i64` range. Use
    /// `toI64LowBits` when low-64-bit conversion is intended.
    pub fn toI64(self: BigInt) !i64 {
        var lossless = false;
        const value = try self.toI64LowBits(&lossless);
        if (!lossless) return error.InvalidArg;
        return value;
    }

    /// Converts the JavaScript BigInt to the low 64 bits as a Zig `i64`.
    ///
    /// If `lossless` is provided, it is set to whether the returned `i64`
    /// represents the original BigInt exactly. Out-of-range values still return
    /// their low 64 bits, matching N-API BigInt conversion semantics, but set
    /// `lossless` to false.
    pub fn toI64LowBits(self: BigInt, lossless: ?*bool) !i64 {
        return self.val.getValueBigintInt64(lossless);
    }

    /// Attempts to convert the JavaScript BigInt exactly to a Zig `u64`.
    ///
    /// Returns `error.InvalidArg` if the value is negative or outside the `u64`
    /// range. Use `toU64LowBits` when low-64-bit conversion is intended.
    pub fn toU64(self: BigInt) !u64 {
        var lossless = false;
        const value = try self.toU64LowBits(&lossless);
        if (!lossless) return error.InvalidArg;
        return value;
    }

    /// Converts the JavaScript BigInt to the low 64 bits as a Zig `u64`.
    ///
    /// If `lossless` is provided, it is set to whether the returned `u64`
    /// represents the original BigInt exactly. Out-of-range or negative values
    /// still return their low 64 bits, matching N-API BigInt conversion
    /// semantics, but set `lossless` to false.
    pub fn toU64LowBits(self: BigInt, lossless: ?*bool) !u64 {
        return self.val.getValueBigintUint64(lossless);
    }

    /// Attempts to convert the JavaScript BigInt exactly to a Zig `i128`.
    ///
    /// Returns `error.InvalidArg` if the value is outside `[-2^127, 2^127)`.
    /// Use `toI128LowBits` when low-128-bit conversion is intended.
    ///
    /// Returns an error if N-API operations fail.
    pub fn toI128(self: BigInt) !i128 {
        var sign_bit: u1 = 0;
        // Three words are enough to distinguish every in-range i128 from any
        // oversized value, even when the lower 128 bits are zero.
        var words: [3]u64 = .{ 0, 0, 0 };
        const result = try self.val.getValueBigintWords(&sign_bit, &words);
        if (result.len > 2) return error.InvalidArg;

        const lo: u128 = words[0];
        const hi: u128 = words[1];
        const magnitude: u128 = (hi << 64) | lo;
        if (sign_bit == 1) {
            if (magnitude == 0) return 0;
            if (magnitude > (@as(u128, 1) << 127)) return error.InvalidArg;
            return @bitCast(0 -% magnitude);
        }

        if (magnitude > @as(u128, @intCast(std.math.maxInt(i128)))) {
            return error.InvalidArg;
        }
        return @intCast(magnitude);
    }

    /// Converts the JavaScript BigInt to the low 128 bits as a Zig `i128`.
    ///
    /// This returns `BigInt.asIntN(128, b)`, i.e. the low 128 bits
    /// of the magnitude reinterpreted as a signed i128. This matches the
    /// ECMAScript `BigInt.asIntN` semantics defined at
    /// https://tc39.es/ecma262/#sec-bigint.asintn.
    ///
    /// Returns an error if N-API operations fail.
    pub fn toI128LowBits(self: BigInt) !i128 {
        var sign_bit: u1 = 0;
        // Pre-zeroed: NAPI writes only as many words as the BigInt has; unused
        // words stay 0. When the value is 0n NAPI returns word_count == 0, so
        // both words[0] and words[1] remain 0 — magnitude correctly becomes 0.
        // When the BigInt exceeds 128 bits, getValueBigintWords fills only the
        // two lower words (truncation to low 128 bits), giving BigInt.asIntN(128)
        // semantics for out-of-range values.
        var words: [2]u64 = .{ 0, 0 };
        _ = try self.val.getValueBigintWords(&sign_bit, &words);
        const lo: u128 = words[0];
        const hi: u128 = words[1];
        const magnitude: u128 = (hi << 64) | lo;
        if (sign_bit == 1) {
            // Negative: result = -magnitude interpreted as i128.
            // Use wrapping subtraction + bitcast to handle both minInt(i128)
            // (magnitude == 2^127, which doesn't fit in i128 as positive) and
            // out-of-range values (magnitude > 2^127, truncated to low 128 bits).
            // Guard: out-of-range negatives whose low 128 bits are all zero
            // (e.g. -2^128n → words [0, 0]) give magnitude == 0. asIntN(128)
            // of such values is 0n; return early rather than relying on the
            // `0 -% 0 == 0` coincidence below.
            if (magnitude == 0) return 0;
            return @bitCast(0 -% magnitude);
        }
        // Positive: bitcast u128 → i128 gives BigInt.asIntN(128) semantics.
        // In-range values have magnitude ≤ 2^127-1 so the sign bit is clear;
        // out-of-range values have the sign bit set, matching JS asIntN(128).
        return @bitCast(magnitude);
    }

    /// Converts the JavaScript BigInt to a Zig `i64`, panicking on failure.
    ///
    /// This is a convenience method for cases where the BigInt is guaranteed
    /// to be exactly representable as an `i64`.
    pub fn assertI64(self: BigInt) i64 {
        return self.toI64() catch @panic("BigInt.assertI64 failed");
    }

    /// Converts the JavaScript BigInt to a Zig `u64`, panicking on failure.
    ///
    /// This is a convenience method for cases where the BigInt is guaranteed
    /// to be exactly representable as a `u64`.
    pub fn assertU64(self: BigInt) u64 {
        return self.toU64() catch @panic("BigInt.assertU64 failed");
    }

    /// Converts the JavaScript BigInt to a Zig `i128`, panicking on failure.
    ///
    /// This is a convenience method for cases where the BigInt is guaranteed
    /// to be exactly representable as an `i128`.
    pub fn assertI128(self: BigInt) i128 {
        return self.toI128() catch @panic("BigInt.assertI128 failed");
    }

    /// Creates a JavaScript `BigInt` from a Zig integer value.
    ///
    /// Accepts `i64`, `u64`, and `comptime_int` values within this range.
    /// For `i128`/`u128` values, use `fromWords`.
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

    /// Creates a JavaScript `BigInt` from a sign bit and word array.
    ///
    /// `sign_bit` is 0 for non-negative, 1 for negative. `words` is the
    /// little-endian unsigned magnitude. The resulting BigInt equals
    /// `(sign_bit == 1 ? -1 : 1) * sum(words[i] << (64 * i))`.
    ///
    /// Use this for constructing BigInts whose magnitude exceeds `u64` (e.g.,
    /// i128 or larger). For `i64`/`u64` values, prefer `BigInt.from`.
    ///
    /// Panics if N-API operations fail (e.g., invalid environment).
    pub fn fromWords(sign_bit: u1, words: []const u64) BigInt {
        const e = context.env();
        const val = e.createBigintWords(sign_bit, words) catch
            @panic("BigInt.fromWords: createBigintWords failed");
        return .{ .val = val };
    }

    /// Returns the underlying `napi.Value` representation of this JavaScript BigInt.
    pub fn toValue(self: BigInt) napi.Value {
        return self.val;
    }
};
