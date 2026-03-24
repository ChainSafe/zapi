const napi = @import("napi.zig");
const context = @import("js/context.zig");
const typed_arrays = @import("js/typed_arrays.zig");

// Context
pub const env = context.env;
pub const allocator = context.allocator;
pub const setEnv = context.setEnv;
pub const restoreEnv = context.restoreEnv;

// Primitive types
pub const Number = @import("js/number.zig").Number;
pub const String = @import("js/string.zig").String;
pub const Boolean = @import("js/boolean.zig").Boolean;
pub const BigInt = @import("js/bigint.zig").BigInt;
pub const Date = @import("js/date.zig").Date;

// Complex types
pub const Array = @import("js/array.zig").Array;
pub const Object = @import("js/object.zig").Object;
pub const Function = @import("js/function.zig").Function;
pub const Value = @import("js/value.zig").Value;

// TypedArrays
pub const TypedArray = typed_arrays.TypedArray;
pub const Int8Array = typed_arrays.Int8Array;
pub const Uint8Array = typed_arrays.Uint8Array;
pub const Uint8ClampedArray = typed_arrays.Uint8ClampedArray;
pub const Int16Array = typed_arrays.Int16Array;
pub const Uint16Array = typed_arrays.Uint16Array;
pub const Int32Array = typed_arrays.Int32Array;
pub const Uint32Array = typed_arrays.Uint32Array;
pub const Float32Array = typed_arrays.Float32Array;
pub const Float64Array = typed_arrays.Float64Array;
pub const BigInt64Array = typed_arrays.BigInt64Array;
pub const BigUint64Array = typed_arrays.BigUint64Array;

// Promise
pub const Promise = @import("js/promise.zig").Promise;
pub const createPromise = @import("js/promise.zig").createPromise;

/// Throws a JS Error with the given message.
pub fn throwError(message: [:0]const u8) void {
    const e = context.env();
    e.throwError("", message) catch {};
}

test {
    // Reference all sub-modules so their tests run, but avoid refAllDecls
    // which would force-link free functions (throwError) against C symbols
    // unavailable in the native test runner.
    _ = @import("js/context.zig");
    _ = @import("js/number.zig");
    _ = @import("js/string.zig");
    _ = @import("js/boolean.zig");
    _ = @import("js/bigint.zig");
    _ = @import("js/date.zig");
    _ = @import("js/array.zig");
    _ = @import("js/object.zig");
    _ = @import("js/function.zig");
    _ = @import("js/typed_arrays.zig");
    _ = @import("js/promise.zig");
    _ = @import("js/value.zig");
}
