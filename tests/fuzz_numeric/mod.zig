//! Fuzz harness addon: per-converter round-trip exports for numeric types.
//!
//! Each export is a single converter end-to-end (JS → Zig → JS). The JS-side
//! fast-check harness compares each result against an ECMAScript/NAPI-spec
//! oracle. See docs/superpowers/specs/2026-05-28-fuzz-testing-design.md.

const js = @import("zapi").js;

/// Smoke-test export: confirms the addon loads and exportModule wires through.
pub fn ping() js.Number {
    return js.Number.from(@as(i32, 42));
}

comptime {
    js.exportModule(@This(), .{});
}
