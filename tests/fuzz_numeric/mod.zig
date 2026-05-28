//! Fuzz harness addon: per-converter round-trip exports for numeric types.

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

comptime {
    js.exportModule(@This(), .{});
}
