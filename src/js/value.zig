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
    val: napi.Value,

    // -- Type checking --

    pub fn isNumber(self: Value) bool {
        return (self.val.typeof() catch return false) == .number;
    }

    pub fn isString(self: Value) bool {
        return (self.val.typeof() catch return false) == .string;
    }

    pub fn isBigInt(self: Value) bool {
        return (self.val.typeof() catch return false) == .bigint;
    }

    pub fn isBoolean(self: Value) bool {
        return (self.val.typeof() catch return false) == .boolean;
    }

    pub fn isSymbol(self: Value) bool {
        return (self.val.typeof() catch return false) == .symbol;
    }

    pub fn isFunction(self: Value) bool {
        return (self.val.typeof() catch return false) == .function;
    }

    pub fn isObject(self: Value) bool {
        return (self.val.typeof() catch return false) == .object;
    }

    pub fn isNull(self: Value) bool {
        return (self.val.typeof() catch return false) == .null;
    }

    pub fn isUndefined(self: Value) bool {
        return (self.val.typeof() catch return false) == .undefined;
    }

    pub fn isArray(self: Value) bool {
        return self.val.isArray() catch return false;
    }

    pub fn isDate(self: Value) bool {
        return self.val.isDate() catch return false;
    }

    pub fn isTypedArray(self: Value) bool {
        return self.val.isTypedarray() catch return false;
    }

    pub fn isPromise(self: Value) bool {
        return self.val.isPromise() catch return false;
    }

    // -- Narrowing methods (type-checked) --

    fn expectType(self: Value, expected: ValueType) !void {
        const actual = try self.val.typeof();
        if (actual != expected) return error.TypeMismatch;
    }

    pub fn asNumber(self: Value) !Number {
        try self.expectType(.number);
        return .{ .val = self.val };
    }

    pub fn asString(self: Value) !String {
        try self.expectType(.string);
        return .{ .val = self.val };
    }

    pub fn asBoolean(self: Value) !Boolean {
        try self.expectType(.boolean);
        return .{ .val = self.val };
    }

    pub fn asBigInt(self: Value) !BigInt {
        try self.expectType(.bigint);
        return .{ .val = self.val };
    }

    pub fn asDate(self: Value) !Date {
        if (!(self.val.isDate() catch return error.TypeMismatch)) return error.TypeMismatch;
        return .{ .val = self.val };
    }

    pub fn asArray(self: Value) !Array {
        if (!(self.val.isArray() catch return error.TypeMismatch)) return error.TypeMismatch;
        return .{ .val = self.val };
    }

    pub fn asFunction(self: Value) !Function {
        try self.expectType(.function);
        return .{ .val = self.val };
    }

    pub fn asObject(self: Value, comptime T: type) !@import("object.zig").Object(T) {
        try self.expectType(.object);
        return .{ .val = self.val };
    }

    // -- TypedArray narrowing (validates isTypedArray + specific subtype) --

    fn expectTypedArrayOfType(self: Value, expected: TypedarrayType) !void {
        if (!(self.val.isTypedarray() catch return error.TypeMismatch)) return error.TypeMismatch;
        const info = self.val.getTypedarrayInfo() catch return error.TypeMismatch;
        if (info.array_type != expected) return error.TypeMismatch;
    }

    pub fn asInt8Array(self: Value) !typed_arrays.Int8Array {
        try self.expectTypedArrayOfType(.int8);
        return .{ .val = self.val };
    }

    pub fn asUint8Array(self: Value) !typed_arrays.Uint8Array {
        try self.expectTypedArrayOfType(.uint8);
        return .{ .val = self.val };
    }

    pub fn asUint8ClampedArray(self: Value) !typed_arrays.Uint8ClampedArray {
        try self.expectTypedArrayOfType(.uint8_clamped);
        return .{ .val = self.val };
    }

    pub fn asInt16Array(self: Value) !typed_arrays.Int16Array {
        try self.expectTypedArrayOfType(.int16);
        return .{ .val = self.val };
    }

    pub fn asUint16Array(self: Value) !typed_arrays.Uint16Array {
        try self.expectTypedArrayOfType(.uint16);
        return .{ .val = self.val };
    }

    pub fn asInt32Array(self: Value) !typed_arrays.Int32Array {
        try self.expectTypedArrayOfType(.int32);
        return .{ .val = self.val };
    }

    pub fn asUint32Array(self: Value) !typed_arrays.Uint32Array {
        try self.expectTypedArrayOfType(.uint32);
        return .{ .val = self.val };
    }

    pub fn asFloat32Array(self: Value) !typed_arrays.Float32Array {
        try self.expectTypedArrayOfType(.float32);
        return .{ .val = self.val };
    }

    pub fn asFloat64Array(self: Value) !typed_arrays.Float64Array {
        try self.expectTypedArrayOfType(.float64);
        return .{ .val = self.val };
    }

    pub fn asBigInt64Array(self: Value) !typed_arrays.BigInt64Array {
        try self.expectTypedArrayOfType(.bigint64);
        return .{ .val = self.val };
    }

    pub fn asBigUint64Array(self: Value) !typed_arrays.BigUint64Array {
        try self.expectTypedArrayOfType(.biguint64);
        return .{ .val = self.val };
    }

    pub fn toValue(self: Value) napi.Value {
        return self.val;
    }
};
