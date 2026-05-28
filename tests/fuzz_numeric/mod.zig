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

comptime {
    js.exportModule(@This(), .{});
}
