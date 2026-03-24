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

/// Untyped escape hatch: wraps a raw napi.Value and provides type-checking
/// and narrowing methods to convert into specific DSL wrapper types.
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

    // -- Narrowing methods --

    pub fn asNumber(self: Value) !Number {
        return .{ .val = self.val };
    }

    pub fn asString(self: Value) !String {
        return .{ .val = self.val };
    }

    pub fn asBoolean(self: Value) !Boolean {
        return .{ .val = self.val };
    }

    pub fn asBigInt(self: Value) !BigInt {
        return .{ .val = self.val };
    }

    pub fn asDate(self: Value) !Date {
        return .{ .val = self.val };
    }

    pub fn asArray(self: Value) !Array {
        return .{ .val = self.val };
    }

    pub fn asFunction(self: Value) !Function {
        return .{ .val = self.val };
    }

    pub fn asObject(self: Value, comptime T: type) !@import("object.zig").Object(T) {
        return .{ .val = self.val };
    }

    // -- TypedArray narrowing --

    pub fn asInt8Array(self: Value) !typed_arrays.Int8Array {
        return .{ .val = self.val };
    }

    pub fn asUint8Array(self: Value) !typed_arrays.Uint8Array {
        return .{ .val = self.val };
    }

    pub fn asUint8ClampedArray(self: Value) !typed_arrays.Uint8ClampedArray {
        return .{ .val = self.val };
    }

    pub fn asInt16Array(self: Value) !typed_arrays.Int16Array {
        return .{ .val = self.val };
    }

    pub fn asUint16Array(self: Value) !typed_arrays.Uint16Array {
        return .{ .val = self.val };
    }

    pub fn asInt32Array(self: Value) !typed_arrays.Int32Array {
        return .{ .val = self.val };
    }

    pub fn asUint32Array(self: Value) !typed_arrays.Uint32Array {
        return .{ .val = self.val };
    }

    pub fn asFloat32Array(self: Value) !typed_arrays.Float32Array {
        return .{ .val = self.val };
    }

    pub fn asFloat64Array(self: Value) !typed_arrays.Float64Array {
        return .{ .val = self.val };
    }

    pub fn asBigInt64Array(self: Value) !typed_arrays.BigInt64Array {
        return .{ .val = self.val };
    }

    pub fn asBigUint64Array(self: Value) !typed_arrays.BigUint64Array {
        return .{ .val = self.val };
    }

    pub fn toValue(self: Value) napi.Value {
        return self.val;
    }
};
