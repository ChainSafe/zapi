const std = @import("std");
const napi = @import("../napi.zig");
const ValueType = napi.value_types.ValueType;
const TypedarrayType = napi.value_types.TypedarrayType;
const Number = @import("number.zig").Number;
const String = @import("string.zig").String;
const Boolean = @import("boolean.zig").Boolean;
const BigInt = @import("bigint.zig").BigInt;
const Date = @import("date.zig").Date;
const Array = @import("array.zig").Array;
const Function = @import("function.zig").Function;
const typed_arrays = @import("typed_arrays.zig");

/// Error returned when a Value narrowing method finds a type mismatch.
pub const TypeError = error{TypeMismatch};

/// Untyped escape hatch: wraps a raw napi.Value and provides type-checking
/// and narrowing methods to convert into specific DSL wrapper types.
/// Narrowing methods validate the JS type at runtime and return
/// `error.TypeMismatch` if the value is not the expected type.
pub const Value = struct {
    /// The underlying `napi.Value` held by this wrapper.
    val: napi.Value,

    // -- Type checking --

    /// Returns `true` if the underlying JavaScript value is a number.
    /// Returns `false` if `typeof` operation fails (e.g., invalid environment).
    pub fn isNumber(self: Value) bool {
        return (self.val.typeof() catch return false) == .number;
    }

    /// Returns `true` if the underlying JavaScript value is a string.
    /// Returns `false` if `typeof` operation fails.
    pub fn isString(self: Value) bool {
        return (self.val.typeof() catch return false) == .string;
    }

    /// Returns `true` if the underlying JavaScript value is a bigint.
    /// Returns `false` if `typeof` operation fails.
    pub fn isBigInt(self: Value) bool {
        return (self.val.typeof() catch return false) == .bigint;
    }

    /// Returns `true` if the underlying JavaScript value is a boolean.
    /// Returns `false` if `typeof` operation fails.
    pub fn isBoolean(self: Value) bool {
        return (self.val.typeof() catch return false) == .boolean;
    }

    /// Returns `true` if the underlying JavaScript value is a symbol.
    /// Returns `false` if `typeof` operation fails.
    pub fn isSymbol(self: Value) bool {
        return (self.val.typeof() catch return false) == .symbol;
    }

    /// Returns `true` if the underlying JavaScript value is a function.
    /// Returns `false` if `typeof` operation fails.
    pub fn isFunction(self: Value) bool {
        return (self.val.typeof() catch return false) == .function;
    }

    /// Returns `true` if the underlying JavaScript value is an object (and not null).
    /// Returns `false` if `typeof` operation fails.
    pub fn isObject(self: Value) bool {
        return (self.val.typeof() catch return false) == .object;
    }

    /// Returns `true` if the underlying JavaScript value is `null`.
    /// Returns `false` if `typeof` operation fails.
    pub fn isNull(self: Value) bool {
        return (self.val.typeof() catch return false) == .null;
    }

    /// Returns `true` if the underlying JavaScript value is `undefined`.
    /// Returns `false` if `typeof` operation fails.
    pub fn isUndefined(self: Value) bool {
        return (self.val.typeof() catch return false) == .undefined;
    }

    /// Returns `true` if the underlying JavaScript value is a JavaScript `Array`.
    /// Returns `false` if N-API operation fails.
    pub fn isArray(self: Value) bool {
        return self.val.isArray() catch return false;
    }

    /// Returns `true` if the underlying JavaScript value is a JavaScript `Date`.
    /// Returns `false` if N-API operation fails.
    pub fn isDate(self: Value) bool {
        return self.val.isDate() catch return false;
    }

    /// Returns `true` if the underlying JavaScript value is a JavaScript `TypedArray`.
    /// Returns `false` if N-API operation fails.
    pub fn isTypedArray(self: Value) bool {
        return self.val.isTypedarray() catch return false;
    }

    /// Returns `true` if the underlying JavaScript value is a JavaScript `Promise`.
    /// Returns `false` if N-API operation fails.
    pub fn isPromise(self: Value) bool {
        return self.val.isPromise() catch return false;
    }

    // -- Narrowing methods (type-checked) --

    /// Narrows the `js.Value` to a `js.Number` if its underlying JavaScript type is `number`.
    /// Returns `error.TypeMismatch` if the value is not a number.
    pub fn asNumber(self: Value) !Number {
        try self.expectType(.number);
        return .{ .val = self.val };
    }

    /// Narrows the `js.Value` to a `js.String` if its underlying JavaScript type is `string`.
    /// Returns `error.TypeMismatch` if the value is not a string.
    pub fn asString(self: Value) !String {
        try self.expectType(.string);
        return .{ .val = self.val };
    }

    /// Narrows the `js.Value` to a `js.Boolean` if its underlying JavaScript type is `boolean`.
    /// Returns `error.TypeMismatch` if the value is not a boolean.
    pub fn asBoolean(self: Value) !Boolean {
        try self.expectType(.boolean);
        return .{ .val = self.val };
    }

    /// Narrows the `js.Value` to a `js.BigInt` if its underlying JavaScript type is `bigint`.
    /// Returns `error.TypeMismatch` if the value is not a bigint.
    pub fn asBigInt(self: Value) !BigInt {
        try self.expectType(.bigint);
        return .{ .val = self.val };
    }

    /// Narrows the `js.Value` to a `js.Date` if its underlying JavaScript value is an actual Date object.
    /// Returns `error.TypeMismatch` if the value is not a Date object.
    pub fn asDate(self: Value) !Date {
        if (!(self.val.isDate() catch return error.TypeMismatch)) return error.TypeMismatch;
        return .{ .val = self.val };
    }

    /// Narrows the `js.Value` to a `js.Array` if its underlying JavaScript value is an actual Array object.
    /// Returns `error.TypeMismatch` if the value is not an array.
    pub fn asArray(self: Value) !Array {
        if (!(self.val.isArray() catch return error.TypeMismatch)) return error.TypeMismatch;
        return .{ .val = self.val };
    }

    /// Narrows the `js.Value` to a `js.Function` if its underlying JavaScript type is `function`.
    /// Returns `error.TypeMismatch` if the value is not a function.
    pub fn asFunction(self: Value) !Function {
        try self.expectType(.function);
        return .{ .val = self.val };
    }

    /// Narrows the `js.Value` to a `js.Object(T)` if its underlying JavaScript type is `object`.
    /// Returns `error.TypeMismatch` if the value is not an object.
    /// The `comptime T` parameter defines the expected Zig struct shape for the
    /// mapped JavaScript object. Each field of `T` must be a ZAPI DSL wrapper type.
    pub fn asObject(self: Value, comptime T: type) !@import("object.zig").Object(T) {
        try self.expectType(.object);
        return .{ .val = self.val };
    }

    // -- TypedArray narrowing (validates isTypedArray + specific subtype) --

    /// Narrows the `js.Value` to a `js.Int8Array` if it is a JavaScript `Int8Array`.
    /// Returns `error.TypeMismatch` if the value is not an `Int8Array`.
    pub fn asInt8Array(self: Value) !typed_arrays.Int8Array {
        try self.expectTypedArrayOfType(.int8);
        return .{ .val = self.val };
    }

    /// Narrows the `js.Value` to a `js.Uint8Array` if it is a JavaScript `Uint8Array`.
    /// Returns `error.TypeMismatch` if the value is not a `Uint8Array`.
    pub fn asUint8Array(self: Value) !typed_arrays.Uint8Array {
        try self.expectTypedArrayOfType(.uint8);
        return .{ .val = self.val };
    }

    /// Narrows the `js.Value` to a `js.Uint8ClampedArray` if it is a JavaScript `Uint8ClampedArray`.
    /// Returns `error.TypeMismatch` if the value is not a `Uint8ClampedArray`.
    pub fn asUint8ClampedArray(self: Value) !typed_arrays.Uint8ClampedArray {
        try self.expectTypedArrayOfType(.uint8_clamped);
        return .{ .val = self.val };
    }

    /// Narrows the `js.Value` to a `js.Int16Array` if it is a JavaScript `Int16Array`.
    /// Returns `error.TypeMismatch` if the value is not an `Int16Array`.
    pub fn asInt16Array(self: Value) !typed_arrays.Int16Array {
        try self.expectTypedArrayOfType(.int16);
        return .{ .val = self.val };
    }

    /// Narrows the `js.Value` to a `js.Uint16Array` if it is a JavaScript `Uint16Array`.
    /// Returns `error.TypeMismatch` if the value is not a `Uint16Array`.
    pub fn asUint16Array(self: Value) !typed_arrays.Uint16Array {
        try self.expectTypedArrayOfType(.uint16);
        return .{ .val = self.val };
    }

    /// Narrows the `js.Value` to a `js.Int32Array` if it is a JavaScript `Int32Array`.
    /// Returns `error.TypeMismatch` if the value is not an `Int32Array`.
    pub fn asInt32Array(self: Value) !typed_arrays.Int32Array {
        try self.expectTypedArrayOfType(.int32);
        return .{ .val = self.val };
    }

    /// Narrows the `js.Value` to a `js.Uint32Array` if it is a JavaScript `Uint32Array`.
    /// Returns `error.TypeMismatch` if the value is not a `Uint32Array`.
    pub fn asUint32Array(self: Value) !typed_arrays.Uint32Array {
        try self.expectTypedArrayOfType(.uint32);
        return .{ .val = self.val };
    }

    /// Narrows the `js.Value` to a `js.Float32Array` if it is a JavaScript `Float32Array`.
    /// Returns `error.TypeMismatch` if the value is not a `Float32Array`.
    pub fn asFloat32Array(self: Value) !typed_arrays.Float32Array {
        try self.expectTypedArrayOfType(.float32);
        return .{ .val = self.val };
    }

    /// Narrows the `js.Value` to a `js.Float64Array` if it is a JavaScript `Float64Array`.
    /// Returns `error.TypeMismatch` if the value is not a `Float64Array`.
    pub fn asFloat64Array(self: Value) !typed_arrays.Float64Array {
        try self.expectTypedArrayOfType(.float64);
        return .{ .val = self.val };
    }

    /// Narrows the `js.Value` to a `js.BigInt64Array` if it is a JavaScript `BigInt64Array`.
    /// Returns `error.TypeMismatch` if the value is not a `BigInt64Array`.
    pub fn asBigInt64Array(self: Value) !typed_arrays.BigInt64Array {
        try self.expectTypedArrayOfType(.bigint64);
        return .{ .val = self.val };
    }

    /// Narrows the `js.Value` to a `js.BigUint64Array` if it is a JavaScript `BigUint64Array`.
    /// Returns `error.TypeMismatch` if the value is not a `BigUint64Array`.
    pub fn asBigUint64Array(self: Value) !typed_arrays.BigUint64Array {
        try self.expectTypedArrayOfType(.biguint64);
        return .{ .val = self.val };
    }

    /// Returns the underlying `napi.Value` representation of this untyped wrapper.
    pub fn toValue(self: Value) napi.Value {
        return self.val;
    }
};
