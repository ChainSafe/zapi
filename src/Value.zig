const c = @import("c.zig");
const status = @import("status.zig");
const NapiError = @import("status.zig").NapiError;
const TypedarrayType = @import("value_types.zig").TypedarrayType;
const ValueType = @import("value_types.zig").ValueType;
const KeyCollectionMode = @import("value_types.zig").KeyCollectionMode;
const KeyFilter = @import("value_types.zig").KeyFilter;
const KeyConversion = @import("value_types.zig").KeyConversion;

env: c.napi_env,
value: c.napi_value,

const Value = @This();

pub const nullptr = Value{
    .env = null,
    .value = null,
};

/// https://nodejs.org/api/n-api.html#napi_is_array
pub fn isArray(self: Value) NapiError!bool {
    var is_array: bool = undefined;
    try status.check(
        c.napi_is_array(self.env, self.value, &is_array),
    );
    return is_array;
}

/// https://nodejs.org/api/n-api.html#napi_is_arraybuffer
pub fn isArrayBuffer(self: Value) NapiError!bool {
    var is_array_buffer: bool = undefined;
    try status.check(
        c.napi_is_arraybuffer(self.env, self.value, &is_array_buffer),
    );
    return is_array_buffer;
}

/// https://nodejs.org/api/n-api.html#napi_is_buffer
pub fn isBuffer(self: Value) NapiError!bool {
    var is_buffer: bool = undefined;
    try status.check(
        c.napi_is_buffer(self.env, self.value, &is_buffer),
    );
    return is_buffer;
}

/// https://nodejs.org/api/n-api.html#napi_is_date
pub fn isDate(self: Value) NapiError!bool {
    var is_date: bool = undefined;
    try status.check(
        c.napi_is_date(self.env, self.value, &is_date),
    );
    return is_date;
}

/// https://nodejs.org/api/n-api.html#napi_is_error
pub fn isError(self: Value) NapiError!bool {
    var is_error: bool = undefined;
    try status.check(
        c.napi_is_error(self.env, self.value, &is_error),
    );
    return is_error;
}

/// https://nodejs.org/api/n-api.html#napi_is_typedarray
pub fn isTypedarray(self: Value) NapiError!bool {
    var is_typedarray: bool = undefined;
    try status.check(
        c.napi_is_typedarray(self.env, self.value, &is_typedarray),
    );
    return is_typedarray;
}

/// https://nodejs.org/api/n-api.html#napi_is_dataview
pub fn isDataview(self: Value) NapiError!bool {
    var is_dataview: bool = undefined;
    try status.check(
        c.napi_is_dataview(self.env, self.value, &is_dataview),
    );
    return is_dataview;
}

/// https://nodejs.org/api/n-api.html#napi_is_detached_arraybuffer
pub fn isDetachedArrayBuffer(self: Value) NapiError!bool {
    var is_detached: bool = undefined;
    try status.check(
        c.napi_is_detached_arraybuffer(self.env, self.value, &is_detached),
    );
    return is_detached;
}

pub fn isPromise(self: Value) NapiError!bool {
    var is_promise: bool = undefined;
    try status.check(
        c.napi_is_promise(self.env, self.value, &is_promise),
    );
    return is_promise;
}

//// Functions to convert from Node-API to C types
//// https://nodejs.org/api/n-api.html#functions-to-convert-from-node-api-to-c-types

/// https://nodejs.org/api/n-api.html#napi_get_array_length
pub fn getArrayLength(self: Value) NapiError!u32 {
    var length: u32 = undefined;
    try status.check(
        c.napi_get_array_length(self.env, self.value, &length),
    );
    return length;
}

/// https://nodejs.org/api/n-api.html#napi_get_arraybuffer_info
pub fn getArrayBufferInfo(self: Value) NapiError![]u8 {
    var data: [*]u8 = undefined;
    var byte_length: usize = undefined;
    try status.check(
        c.napi_get_arraybuffer_info(self.env, self.value, @ptrCast(&data), &byte_length),
    );
    return data[0..byte_length];
}

/// https://nodejs.org/api/n-api.html#napi_get_buffer_info
pub fn getBufferInfo(self: Value) NapiError![]u8 {
    var data: [*]u8 = undefined;
    var byte_length: usize = undefined;
    try status.check(
        c.napi_get_buffer_info(self.env, self.value, @ptrCast(&data), &byte_length),
    );
    return data[0..byte_length];
}

/// https://nodejs.org/api/n-api.html#napi_get_prototype
pub fn getPrototype(self: Value) NapiError!Value {
    var val: c.napi_value = undefined;
    try status.check(c.napi_get_prototype(self.env, self.value, &val));
    return .{
        .env = self.env,
        .value = val,
    };
}

pub const TypedarrayInfo = struct {
    array_type: TypedarrayType,
    length: usize,
    data: []u8,
    arraybuffer: Value,
    byte_offset: usize,
};

/// https://nodejs.org/api/n-api.html#napi_get_typedarray_info
pub fn getTypedarrayInfo(self: Value) NapiError!TypedarrayInfo {
    var info: TypedarrayInfo = undefined;
    var data: [*]u8 = undefined;
    try status.check(
        c.napi_get_typedarray_info(self.env, self.value, @ptrCast(&info.array_type), &info.length, @ptrCast(&data), @ptrCast(&info.arraybuffer), &info.byte_offset),
    );
    info.data = data[0 .. info.length * info.array_type.elementSize()];
    return info;
}

pub const DataViewInfo = struct {
    byte_length: usize,
    data: []u8,
    arraybuffer: Value,
    byte_offset: usize,
};

/// https://nodejs.org/api/n-api.html#napi_get_dataview_info
pub fn getDataviewInfo(self: Value) NapiError!DataViewInfo {
    var info: DataViewInfo = undefined;
    var data: [*]u8 = undefined;
    try status.check(
        c.napi_get_dataview_info(self.env, self.value, &info.byte_length, @ptrCast(&data), @ptrCast(&info.arraybuffer), &info.byte_offset),
    );
    info.data = data[0..info.byte_length];
    return info;
}

/// https://nodejs.org/api/n-api.html#napi_get_date_value
pub fn getDateValue(self: Value) NapiError!f64 {
    var time: f64 = undefined;
    try status.check(
        c.napi_get_date_value(self.env, self.value, &time),
    );
    return time;
}

/// https://nodejs.org/api/n-api.html#napi_get_value_bool
pub fn getValueBool(self: Value) NapiError!bool {
    var boolean: bool = undefined;
    try status.check(
        c.napi_get_value_bool(self.env, self.value, &boolean),
    );
    return boolean;
}

/// https://nodejs.org/api/n-api.html#napi_get_value_double
pub fn getValueDouble(self: Value) NapiError!f64 {
    var number: f64 = undefined;
    try status.check(
        c.napi_get_value_double(self.env, self.value, &number),
    );
    return number;
}

/// https://nodejs.org/api/n-api.html#napi_get_value_bigint_int64
pub fn getValueBigintInt64(self: Value, lossless: ?*bool) NapiError!i64 {
    var bigint: i64 = undefined;
    try status.check(
        c.napi_get_value_bigint_int64(self.env, self.value, &bigint, lossless),
    );
    return bigint;
}

/// https://nodejs.org/api/n-api.html#napi_get_value_bigint_uint64
pub fn getValueBigintUint64(self: Value, lossless: ?*bool) NapiError!u64 {
    var bigint: u64 = undefined;
    try status.check(
        c.napi_get_value_bigint_uint64(self.env, self.value, &bigint, lossless),
    );
    return bigint;
}

/// https://nodejs.org/api/n-api.html#napi_get_value_bigint_words
pub fn getValueBigintWords(self: Value, sign_bit: *u1, words: []u64) NapiError![]u64 {
    var word_count: usize = words.len;
    try status.check(
        c.napi_get_value_bigint_words(self.env, self.value, @alignCast(@ptrCast(sign_bit)), &word_count, @ptrCast(words)),
    );
    return words[0..word_count];
}

/// https://nodejs.org/api/n-api.html#napi_get_value_external
pub fn getValueExternal(self: Value) NapiError!*anyopaque {
    var data: *anyopaque = undefined;
    try status.check(
        c.napi_get_value_external(self.env, self.value, @ptrCast(&data)),
    );
    return data;
}

/// https://nodejs.org/api/n-api.html#napi_get_value_int32
pub fn getValueInt32(self: Value) NapiError!i32 {
    var number: i32 = undefined;
    try status.check(
        c.napi_get_value_int32(self.env, self.value, &number),
    );
    return number;
}

/// https://nodejs.org/api/n-api.html#napi_get_value_int64
pub fn getValueInt64(self: Value) NapiError!i64 {
    var number: i64 = undefined;
    try status.check(
        c.napi_get_value_int64(self.env, self.value, &number),
    );
    return number;
}

/// https://nodejs.org/api/n-api.html#napi_get_value_string_latin1
pub fn getValueStringLatin1(self: Value, buffer: []u8) NapiError![]const u8 {
    var length: usize = undefined;
    try status.check(
        c.napi_get_value_string_latin1(self.env, self.value, buffer.ptr, buffer.len, &length),
    );
    return buffer[0..length];
}

/// https://nodejs.org/api/n-api.html#napi_get_value_string_utf8
pub fn getValueStringUtf8(self: Value, buffer: []u8) NapiError![]const u8 {
    var length: usize = undefined;
    try status.check(
        c.napi_get_value_string_utf8(self.env, self.value, buffer.ptr, buffer.len, &length),
    );
    return buffer[0..length];
}

/// https://nodejs.org/api/n-api.html#napi_get_value_string_utf16
pub fn getValueStringUtf16(self: Value, buffer: []u16) NapiError![]const u16 {
    var length: usize = undefined;
    try status.check(
        c.napi_get_value_string_utf16(self.env, self.value, buffer.ptr, buffer.len, &length),
    );
    return buffer[0..length];
}

/// https://nodejs.org/api/n-api.html#napi_get_value_uint32
pub fn getValueUint32(self: Value) NapiError!u32 {
    var number: u32 = undefined;
    try status.check(
        c.napi_get_value_uint32(self.env, self.value, &number),
    );
    return number;
}

//// Working with JavaScript values and abstract operations
//// https://nodejs.org/api/n-api.html#working-with-javascript-values-and-abstract-operations

/// https://nodejs.org/api/n-api.html#napi_coerce_to_bool
pub fn coerceToBool(self: Value) NapiError!Value {
    var boolean: c.napi_value = undefined;
    try status.check(
        c.napi_coerce_to_bool(self.env, self.value, &boolean),
    );
    return Value{
        .env = self.env,
        .value = boolean,
    };
}

/// https://nodejs.org/api/n-api.html#napi_coerce_to_number
pub fn coerceToNumber(self: Value) NapiError!Value {
    var number: c.napi_value = undefined;
    try status.check(
        c.napi_coerce_to_number(self.env, self.value, &number),
    );
    return Value{
        .env = self.env,
        .value = number,
    };
}

/// https://nodejs.org/api/n-api.html#napi_coerce_to_object
pub fn coerceToObject(self: Value) NapiError!Value {
    var object: c.napi_value = undefined;
    try status.check(
        c.napi_coerce_to_object(self.env, self.value, &object),
    );
    return Value{
        .env = self.env,
        .value = object,
    };
}

/// https://nodejs.org/api/n-api.html#napi_coerce_to_string
pub fn coerceToString(self: Value) NapiError!Value {
    var string: c.napi_value = undefined;
    try status.check(
        c.napi_coerce_to_string(self.env, self.value, &string),
    );
    return Value{
        .env = self.env,
        .value = string,
    };
}

/// https://nodejs.org/api/n-api.html#napi_typeof
pub fn typeof(self: Value) NapiError!ValueType {
    var value_type: ValueType = undefined;
    try status.check(
        c.napi_typeof(self.env, self.value, @ptrCast(&value_type)),
    );
    return value_type;
}

/// https://nodejs.org/api/n-api.html#napi_instanceof
pub fn instanceof(self: Value, constructor: Value) NapiError!bool {
    var is_instance: bool = undefined;
    try status.check(
        c.napi_instanceof(self.env, self.value, constructor.value, &is_instance),
    );
    return is_instance;
}

/// https://nodejs.org/api/n-api.html#napi_strict_equals
pub fn strictEquals(self: Value, b: Value) NapiError!bool {
    var result: bool = undefined;
    try status.check(
        c.napi_strict_equals(self.env, self.value, b.value, &result),
    );
    return result;
}

/// https://nodejs.org/api/n-api.html#napi_detach_arraybuffer
pub fn detachArrayBuffer(self: Value) NapiError!void {
    try status.check(
        c.napi_detach_arraybuffer(self.env, self.value),
    );
}

//// Working with JavaScript properties
//// https://nodejs.org/api/n-api.html#working-with-javascript-properties

pub fn getPropertyNames(self: Value) NapiError!Value {
    var names: c.napi_value = undefined;
    try status.check(
        c.napi_get_property_names(self.env, self.value, &names),
    );
    return Value{
        .env = self.env,
        .value = names,
    };
}

pub fn getAllPropertyNames(self: Value, mode: KeyCollectionMode, filter: KeyFilter, conversion: KeyConversion) NapiError!Value {
    var names: c.napi_value = undefined;
    try status.check(
        c.napi_get_all_property_names(self.env, self.value, @intFromEnum(mode), @intFromEnum(filter), @intFromEnum(conversion), &names),
    );
    return Value{
        .env = self.env,
        .value = names,
    };
}

pub fn setProperty(self: Value, key: Value, value: Value) NapiError!void {
    try status.check(
        c.napi_set_property(self.env, self.value, key.value, value.value),
    );
}

pub fn getProperty(self: Value, key: Value) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.napi_get_property(self.env, self.value, key.value, &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

pub fn hasProperty(self: Value, key: Value) NapiError!bool {
    var has: bool = undefined;
    try status.check(
        c.napi_has_property(self.env, self.value, key.value, &has),
    );
    return has;
}

pub fn deleteProperty(self: Value, key: Value) NapiError!bool {
    var deleted: bool = undefined;
    try status.check(
        c.napi_delete_property(self.env, self.value, key.value, &deleted),
    );
    return deleted;
}

pub fn hasOwnProperty(self: Value, key: Value) NapiError!bool {
    var has: bool = undefined;
    try status.check(
        c.napi_has_own_property(self.env, self.value, key.value, &has),
    );
    return has;
}

pub fn setNamedProperty(self: Value, utf8_name: [:0]const u8, value: Value) NapiError!void {
    try status.check(
        c.napi_set_named_property(self.env, self.value, utf8_name.ptr, value.value),
    );
}

pub fn getNamedProperty(self: Value, utf8_name: [:0]const u8) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.napi_get_named_property(self.env, self.value, utf8_name.ptr, &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

pub fn hasNamedProperty(self: Value, utf8_name: [:0]const u8) NapiError!bool {
    var has: bool = undefined;
    try status.check(
        c.napi_has_named_property(self.env, self.value, utf8_name.ptr, &has),
    );
    return has;
}

pub fn setElement(self: Value, index: u32, value: Value) NapiError!void {
    try status.check(
        c.napi_set_element(self.env, self.value, index, value.value),
    );
}

pub fn getElement(self: Value, index: u32) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.napi_get_element(self.env, self.value, index, &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

pub fn hasElement(self: Value, index: u32) NapiError!bool {
    var has: bool = undefined;
    try status.check(
        c.napi_has_element(self.env, self.value, index, &has),
    );
    return has;
}

pub fn deleteElement(self: Value, index: u32) NapiError!bool {
    var deleted: bool = undefined;
    try status.check(
        c.napi_delete_element(self.env, self.value, index, &deleted),
    );
    return deleted;
}

pub fn defineProperties(self: Value, properties: []const c.napi_property_descriptor) NapiError!void {
    try status.check(
        c.napi_define_properties(self.env, self.value, properties.len, properties.ptr),
    );
}

pub fn objectFreeze(self: Value) NapiError!void {
    try status.check(
        c.napi_object_freeze(self.env, self.value),
    );
}

pub fn objectSeal(self: Value) NapiError!void {
    try status.check(
        c.napi_object_seal(self.env, self.value),
    );
}
