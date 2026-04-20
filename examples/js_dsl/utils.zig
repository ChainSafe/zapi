// examples/js_dsl/utils.zig
const js = @import("zapi").js;
const Number = js.Number;

/// Clamp a number between min and max.
pub fn clamp(val: Number, min_val: Number, max_val: Number) Number {
    const v = val.assertI32();
    const lo = min_val.assertI32();
    const hi = max_val.assertI32();
    if (v < lo) return Number.from(lo);
    if (v > hi) return Number.from(hi);
    return Number.from(v);
}
