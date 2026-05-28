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

comptime {
    js.exportModule(@This(), .{});
}
