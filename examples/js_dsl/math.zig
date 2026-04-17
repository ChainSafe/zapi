// examples/js_dsl/math.zig
const js = @import("zapi").js;
const Number = js.Number;

/// Multiply two numbers.
pub fn multiply(a: Number, b: Number) Number {
    return Number.from(a.assertI32() * b.assertI32());
}

/// Square a number.
pub fn square(a: Number) Number {
    const v = a.assertI32();
    return Number.from(v * v);
}

/// Nested sub-module for utility functions.
pub const utils = @import("utils.zig");
