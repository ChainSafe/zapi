//! Namespace demonstrating scalar/string const and enum export.

pub const MAX_ITERATIONS: u32 = 90;
pub const EPSILON: f64 = 0.001;
pub const LIBRARY = "zapi";
pub const IS_FAST = true;

/// Exported to JS as a frozen plain object `{single: 1, double: 2}`.
pub const Precision = enum(u8) { single = 1, double = 2 };
