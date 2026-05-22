//! This example module demonstrates a public function with non-DSL parameters
//! being skipped by `zapi`'s `exportModule` functionality.
//!
//! `zapi` will only export zig functions as bindings if they:
//!
//! 1) are public functions (`pub fn`),
//! 2) use DSL-compatible parameters (eg. `js.Number`).
//!
//! In this scenario, even though `skipped` is public, it does not use
//! a DSL-compatible type for its `value` parameter and is therefore
//! not exported.
//!
//! If the user should want to export any other functions manually,
//! they would need to pass a custom `.register` to `js.exportModule`.
const js = @import("zapi").js;

const Number = js.Number;

pub fn exported(value: Number) Number {
    return Number.from(value.assertI32() + 1);
}

pub fn skipped(value: u32) u32 {
    return value + 1;
}

comptime {
    js.exportModule(@This(), .{});
}
