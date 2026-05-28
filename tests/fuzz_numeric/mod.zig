//! Fuzz harness addon: per-converter round-trip exports for numeric types.

const js = @import("zapi").js;

/// Round-trip JS number → f64 → JS number. Oracle: identity for all finite
/// numbers, NaN ↔ NaN, ±0 preserved.
pub fn rtNumberF64(n: js.Number) !js.Number {
    return js.Number.from(try n.toF64());
}

comptime {
    js.exportModule(@This(), .{});
}
