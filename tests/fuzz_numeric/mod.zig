//! Fuzz harness addon: per-converter round-trip exports for numeric types.

const std = @import("std");
const js = @import("zapi").js;

/// Round-trip JS number → f64 → JS number. Oracle: identity for all finite
/// numbers, NaN ↔ NaN, ±0 preserved.
pub fn rtNumberF64(n: js.Number) !js.Number {
    return js.Number.from(try n.toF64());
}

/// Round-trip via ToInt32 (`value | 0` semantics).
pub fn rtNumberI32(n: js.Number) !js.Number {
    return js.Number.from(try n.toI32());
}

/// Round-trip via ToUint32 (`value >>> 0` semantics).
pub fn rtNumberU32(n: js.Number) !js.Number {
    return js.Number.from(try n.toU32());
}

/// Round-trip via NAPI int64. Returns a JS BigInt so the result is lossless
/// in JS (a JS number cannot represent all of i64 exactly).
pub fn rtNumberI64(n: js.Number) !js.BigInt {
    return js.BigInt.from(try n.toI64());
}

/// Round-trip via NAPI int64. The `lossless` flag is discarded; the result
/// equals BigInt.asIntN(64, b) regardless. See `losslessI64` (Task 6) for
/// flag-exposing variants.
pub fn rtBigIntI64(b: js.BigInt) !js.BigInt {
    var lossless: bool = false;
    return js.BigInt.from(try b.toI64(&lossless));
}

/// Round-trip via NAPI uint64. Result equals BigInt.asUintN(64, b).
pub fn rtBigIntU64(b: js.BigInt) !js.BigInt {
    var lossless: bool = false;
    return js.BigInt.from(try b.toU64(&lossless));
}

/// Returns `{ value: BigInt, lossless: Boolean }` exposing toI64's lossless
/// out-parameter to the fuzzer.
pub fn losslessI64(b: js.BigInt) !js.Value {
    var lossless: bool = false;
    const v = try b.toI64(&lossless);
    const value = js.BigInt.from(v);
    const flag = js.Boolean.from(lossless);
    const obj = try js.env().createObject();
    try obj.setNamedProperty("value", value.toValue());
    try obj.setNamedProperty("lossless", flag.toValue());
    return .{ .val = obj };
}

/// Returns `{ value: BigInt, lossless: Boolean }` for toU64.
pub fn losslessU64(b: js.BigInt) !js.Value {
    var lossless: bool = false;
    const v = try b.toU64(&lossless);
    const value = js.BigInt.from(v);
    const flag = js.Boolean.from(lossless);
    const obj = try js.env().createObject();
    try obj.setNamedProperty("value", value.toValue());
    try obj.setNamedProperty("lossless", flag.toValue());
    return .{ .val = obj };
}

/// Round-trip JS BigInt → i128 → JS BigInt via fromWords.
///
/// In-domain (b ∈ [-2^127, 2^127)) this is identity. Out-of-domain behavior
/// is determined by `BigInt.toI128` (currently: truncates to low 128 bits).
/// The fuzzer surfaces any mismatch against the oracle in fuzz.test.ts.
pub fn rtBigIntI128(b: js.BigInt) !js.BigInt {
    const v = try b.toI128();
    const is_negative = v < 0;
    const magnitude: u128 = if (is_negative)
        @as(u128, @intCast(-(v + 1))) + 1 // safe for i128.minInt
    else
        @as(u128, @intCast(v));
    const words = [_]u64{
        @truncate(magnitude),
        @truncate(magnitude >> 64),
    };
    return js.BigInt.fromWords(if (is_negative) 1 else 0, &words);
}

/// Round-trip via getValueBigintWords → createBigintWords (via fromWords).
/// Identity for any BigInt that fits in the addon's word buffer (64 words =
/// 4096 bits is the practical cap).
///
/// Implementation notes:
///   - We pass a 64-word buffer to `getValueBigintWords`. The `src/Value.zig`
///     wrapper now clamps the returned slice to `@min(word_count, buffer.len)`,
///     so oversized BigInts silently truncate. The 64-word cap covers all
///     entries in `edgeBigInts` (the largest, `1n << 256n`, is 5 words).
///   - Sign bit and the populated word slice are forwarded to `fromWords`.
pub fn rtBigIntWords(b: js.BigInt) !js.BigInt {
    var sign_bit: u1 = 0;
    var buf: [64]u64 = @splat(0);
    const slice = try b.toValue().getValueBigintWords(&sign_bit, &buf);
    return js.BigInt.fromWords(sign_bit, slice);
}

comptime {
    js.exportModule(@This(), .{});
}
