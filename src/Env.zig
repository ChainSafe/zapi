const std = @import("std");
const c = @import("c.zig");
const status = @import("status.zig");
const NapiError = status.NapiError;
const TypedarrayType = @import("value_types.zig").TypedarrayType;
const TypeTag = @import("value_types.zig").TypeTag;
const Value = @import("Value.zig");
const Values = @import("Values.zig");

const CallbackInfo = @import("callback_info.zig").CallbackInfo;
const Callback = @import("callback.zig").Callback;
const wrapCallback = @import("callback.zig").wrapCallback;
const HandleScope = @import("HandleScope.zig");
const EscapableHandleScope = @import("EscapableHandleScope.zig");
const Ref = @import("Ref.zig");
const Deferred = @import("Deferred.zig");
const NodeVersion = @import("NodeVersion.zig");
const AsyncContext = @import("AsyncContext.zig");
const FinalizeCallback = @import("finalize_callback.zig").FinalizeCallback;
const wrapFinalizeCallback = @import("finalize_callback.zig").wrapFinalizeCallback;

env: c.napi_env,

pub const Env = @This();

//// Error handling
//// https://nodejs.org/api/n-api.html#error-handling

/// https://nodejs.org/api/n-api.html#napi_get_last_error_info
pub fn getLastErrorInfo(self: Env) NapiError!c.napi_extended_error_info {
    var error_info: c.napi_extended_error_info = undefined;
    try status.check(
        c.napi_get_last_error_info(self.env, @ptrCast(&error_info)),
    );
    return error_info;
}

//// Exceptions
//// https://nodejs.org/api/n-api.html#exceptions

/// https://nodejs.org/api/n-api.html#napi_throw
pub fn throw(self: Env, value: Value) NapiError!void {
    try status.check(
        c.napi_throw(self.env, value.value),
    );
}

/// https://nodejs.org/api/n-api.html#napi_throw_error
pub fn throwError(self: Env, code: [:0]const u8, message: [:0]const u8) NapiError!void {
    try status.check(
        c.napi_throw_error(self.env, code, message.ptr),
    );
}

/// https://nodejs.org/api/n-api.html#napi_throw_type_error
pub fn throwTypeError(self: Env, code: ?u8, message: [:0]const u8) NapiError!void {
    try status.check(
        c.napi_throw_type_error(self.env, @ptrCast(&code), message.ptr),
    );
}

/// https://nodejs.org/api/n-api.html#napi_throw_range_error
pub fn throwRangeError(self: Env, code: ?u8, message: [:0]const u8) NapiError!void {
    try status.check(
        c.napi_throw_range_error(self.env, @ptrCast(&code), message.ptr),
    );
}

/// https://nodejs.org/api/n-api.html#node_api_throw_syntax_error
pub fn throwSyntaxError(self: Env, code: ?u8, message: [:0]const u8) NapiError!void {
    try status.check(
        c.node_api_throw_syntax_error(self.env, @ptrCast(&code), message.ptr),
    );
}

/// https://nodejs.org/api/n-api.html#napi_create_error
pub fn createError(self: Env, code: Value, message: Value) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.napi_create_error(self.env, code.value, message.value, &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

/// https://nodejs.org/api/n-api.html#napi_create_type_error
pub fn createTypeError(self: Env, code: Value, message: Value) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.napi_create_type_error(self.env, code.value, message.value, &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

/// https://nodejs.org/api/n-api.html#napi_create_range_error
pub fn createRangeError(self: Env, code: Value, message: Value) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.napi_create_range_error(self.env, code.value, message.value, &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

/// https://nodejs.org/api/n-api.html#node_api_create_syntax_error
pub fn createSyntaxError(self: Env, code: Value, message: Value) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.node_api_create_syntax_error(self.env, code.value, message.value, &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

/// https://nodejs.org/api/n-api.html#napi_get_and_clear_last_exception
pub fn getAndClearLastException(self: Env) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.napi_get_and_clear_last_exception(self.env, &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

/// https://nodejs.org/api/n-api.html#napi_is_exception_pending
pub fn isExceptionPending(self: Env) NapiError!bool {
    var is_pending: bool = undefined;
    try status.check(
        c.napi_is_exception_pending(self.env, &is_pending),
    );
    return is_pending;
}

/// https://nodejs.org/api/n-api.html#napi_fatal_exception
pub fn fatalException(self: Env, value: Value) NapiError!void {
    try status.check(
        c.napi_fatal_exception(self.env, value.value),
    );
}

//// Fatal errors
//// https://nodejs.org/api/n-api.html#fatal-errors

/// https://nodejs.org/api/n-api.html#napi_fatal_error
pub fn fatalError(self: Env, location: []const u8, message: []const u8) NapiError!noreturn {
    _ = self;
    try status.check(
        c.napi_fatal_error(location.ptr, location.len, message.ptr, message.len),
    );
}

//// Object lifetime management
//// https://nodejs.org/api/n-api.html#object-lifetime-management

/// https://nodejs.org/api/n-api.html#napi_open_handle_scope
pub fn openHandleScope(self: Env) NapiError!HandleScope {
    return try HandleScope.open(self.env);
}

/// https://nodejs.org/api/n-api.html#napi_open_escapable_handle_scope
pub fn openEscapableHandleScope(self: Env) NapiError!EscapableHandleScope {
    return try EscapableHandleScope.open(self.env);
}

//// References to values with a lifespan longer than that of the native method
//// https://nodejs.org/api/n-api.html#references-to-values-with-a-lifespan-longer-than-that-of-the-native-method

/// https://nodejs.org/api/n-api.html#napi_create_reference
pub fn createReference(self: Env, value: Value, initial_refcount: u32) NapiError!Ref {
    return try Ref.create(self.env, value, initial_refcount);
}

//// Object creation functions
//// https://nodejs.org/api/n-api.html#object-creation-functions

/// https://nodejs.org/api/n-api.html#napi_create_array
pub fn createArray(self: Env) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.napi_create_array(self.env, &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

/// https://nodejs.org/api/n-api.html#napi_create_array_with_length
pub fn createArrayWithLength(self: Env, length: usize) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.napi_create_array_with_length(self.env, length, &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

/// https://nodejs.org/api/n-api.html#napi_create_arraybuffer
pub fn createArrayBuffer(self: Env, size: usize, out: ?*[*]u8) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.napi_create_arraybuffer(self.env, size, @ptrCast(out), &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

/// https://nodejs.org/api/n-api.html#napi_create_buffer
pub fn createBuffer(self: Env, size: usize, out: ?*[*]u8) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.napi_create_buffer(self.env, size, @ptrCast(out), &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

/// https://nodejs.org/api/n-api.html#napi_create_buffer_copy
pub fn createBufferCopy(self: Env, data: []const u8, out: ?*[*]u8) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.napi_create_buffer_copy(self.env, data.len, data.ptr, @ptrCast(out), &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

/// https://nodejs.org/api/n-api.html#napi_create_date
pub fn createDate(self: Env, time: f64) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.napi_create_date(self.env, time, &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

/// https://nodejs.org/api/n-api.html#napi_create_external
pub fn createExternal(self: Env, data: [*]const u8, finalize_cb: c.napi_finalize, finalize_hint: ?*anyopaque) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.napi_create_external(self.env, @constCast(@ptrCast(data)), finalize_cb, finalize_hint, &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

/// https://nodejs.org/api/n-api.html#napi_create_external_arraybuffer
pub fn createExternalArrayBuffer(self: Env, data: []const u8, finalize_cb: c.napi_finalize, finalize_hint: ?*anyopaque) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.napi_create_external_arraybuffer(self.env, @constCast(@ptrCast(data.ptr)), data.len, finalize_cb, finalize_hint, &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

/// https://nodejs.org/api/n-api.html#napi_create_external_buffer
pub fn createExternalBuffer(self: Env, data: []const u8, finalize_cb: c.napi_finalize, finalize_hint: ?*anyopaque) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.napi_create_external_buffer(self.env, data.len, @constCast(@ptrCast(data.ptr)), finalize_cb, finalize_hint, &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

/// https://nodejs.org/api/n-api.html#napi_create_object
pub fn createObject(self: Env) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.napi_create_object(self.env, &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

/// https://nodejs.org/api/n-api.html#napi_create_symbol
pub fn createSymbol(self: Env, description: Value) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.napi_create_symbol(self.env, description.value, &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

/// https://nodejs.org/api/n-api.html#node_api_symbol_for
pub fn symbolFor(self: Env, description: []const u8) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.node_api_symbol_for(self.env, description.ptr, description.len, &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

/// https://nodejs.org/api/n-api.html#napi_create_typedarray
pub fn createTypedarray(self: Env, array_type: TypedarrayType, length: usize, arraybuffer: Value, byte_offset: usize) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.napi_create_typedarray(self.env, @intFromEnum(array_type), length, arraybuffer.value, byte_offset, &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

/// https://nodejs.org/api/n-api.html#node_api_create_buffer_from_arraybuffer
pub fn createBufferFromArraybuffer(self: Env, arraybuffer: Value, byte_offset: usize, byte_length: usize) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.node_api_create_buffer_from_arraybuffer(self.env, arraybuffer.value, byte_offset, byte_length, &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

/// https://nodejs.org/api/n-api.html#napi_create_dataview
pub fn createDataView(self: Env, length: usize, arraybuffer: Value, byte_offset: usize) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.napi_create_dataview(self.env, length, arraybuffer.value, byte_offset, &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

//// Functions to convert from c types to napi
//// https://nodejs.org/api/n-api.html#functions-to-convert-from-c-types-to-node-api

/// https://nodejs.org/api/n-api.html#napi_create_int32
pub fn createInt32(self: Env, value: i32) NapiError!Value {
    var napi_value: c.napi_value = undefined;
    try status.check(
        c.napi_create_int32(self.env, value, &napi_value),
    );
    return Value{
        .env = self.env,
        .value = napi_value,
    };
}

/// https://nodejs.org/api/n-api.html#napi_create_uint32
pub fn createUint32(self: Env, value: u32) NapiError!Value {
    var napi_value: c.napi_value = undefined;
    try status.check(
        c.napi_create_uint32(self.env, value, &napi_value),
    );
    return Value{
        .env = self.env,
        .value = napi_value,
    };
}

/// https://nodejs.org/api/n-api.html#napi_create_int64
pub fn createInt64(self: Env, value: i64) NapiError!Value {
    var napi_value: c.napi_value = undefined;
    try status.check(
        c.napi_create_int64(self.env, value, &napi_value),
    );
    return Value{
        .env = self.env,
        .value = napi_value,
    };
}

/// https://nodejs.org/api/n-api.html#napi_create_double
pub fn createDouble(self: Env, value: f64) NapiError!Value {
    var napi_value: c.napi_value = undefined;
    try status.check(
        c.napi_create_double(self.env, value, &napi_value),
    );
    return Value{
        .env = self.env,
        .value = napi_value,
    };
}

/// https://nodejs.org/api/n-api.html#napi_create_bigint_int64
pub fn createBigintInt64(self: Env, value: i64) NapiError!Value {
    var napi_value: c.napi_value = undefined;
    try status.check(
        c.napi_create_bigint_int64(self.env, value, &napi_value),
    );
    return Value{
        .env = self.env,
        .value = napi_value,
    };
}

/// https://nodejs.org/api/n-api.html#napi_create_bigint_uint64
pub fn createBigintUint64(self: Env, value: u64) NapiError!Value {
    var napi_value: c.napi_value = undefined;
    try status.check(
        c.napi_create_bigint_uint64(self.env, value, &napi_value),
    );
    return Value{
        .env = self.env,
        .value = napi_value,
    };
}

/// https://nodejs.org/api/n-api.html#napi_create_bigint_words
pub fn createBigintWords(self: Env, sign_bit: u1, words: []const u64) NapiError!Value {
    var napi_value: c.napi_value = undefined;
    try status.check(
        c.napi_create_bigint_words(self.env, sign_bit, words.len, words.ptr, &napi_value),
    );
    return Value{
        .env = self.env,
        .value = napi_value,
    };
}

/// https://nodejs.org/api/n-api.html#napi_create_string_latin1
pub fn createStringLatin1(self: Env, str: []const u8) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.napi_create_string_latin1(self.env, str.ptr, str.len, &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

/// https://nodejs.org/api/n-api.html#napi_create_external_string_latin1
pub fn createExternalStringLatin1(self: Env, str: []const u8, finalize_cb: c.napi_finalize, finalize_hint: ?*anyopaque) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.node_api_create_external_string_latin1(self.env, str.ptr, str.len, finalize_cb, finalize_hint, &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

/// https://nodejs.org/api/n-api.html#napi_create_string_utf16
pub fn createStringUtf16(self: Env, str: []const u16) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.napi_create_string_utf16(self.env, str.ptr, str.len, &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

/// https://nodejs.org/api/n-api.html#napi_create_external_string_utf16
pub fn createExternalStringUtf16(self: Env, str: []const u16, finalize_cb: c.napi_finalize, finalize_hint: ?*anyopaque) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.node_api_create_external_string_utf16(self.env, str.ptr, str.len, finalize_cb, finalize_hint, &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

/// https://nodejs.org/api/n-api.html#napi_create_string_utf8
pub fn createStringUtf8(self: Env, str: []const u8) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.napi_create_string_utf8(self.env, str.ptr, str.len, &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

//// Functions to create optimized property keys
//// https://nodejs.org/api/n-api.html#functions-to-create-optimized-property-keys

/// https://nodejs.org/api/n-api.html#node_api_create_property_key_latin1
pub fn createPropertyKeyLatin1(self: Env, str: []const u8) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.node_api_create_property_key_latin1(self.env, str.ptr, str.len, &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

/// https://nodejs.org/api/n-api.html#node_api_create_property_key_utf16
pub fn createPropertyKeyUtf16(self: Env, str: []const u16) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.node_api_create_property_key_utf16(self.env, str.ptr, str.len, &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

/// https://nodejs.org/api/n-api.html#node_api_create_property_key_utf8
pub fn createPropertyKeyUtf8(self: Env, str: []const u8) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.node_api_create_property_key_utf8(self.env, str.ptr, str.len, &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

//// Functions to get global instances
//// https://nodejs.org/api/n-api.html#functions-to-get-global-instances

/// https://nodejs.org/api/n-api.html#napi_get_boolean
pub fn getBoolean(self: Env, in: bool) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.napi_get_boolean(self.env, in, &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

/// https://nodejs.org/api/n-api.html#napi_get_global
pub fn getGlobal(self: Env) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.napi_get_global(self.env, &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

/// https://nodejs.org/api/n-api.html#napi_get_null
pub fn getNull(self: Env) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.napi_get_null(self.env, &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

/// https://nodejs.org/api/n-api.html#napi_get_undefined
pub fn getUndefined(self: Env) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.napi_get_undefined(self.env, &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

//// Working with JavaScript functions
//// https://nodejs.org/api/n-api.html#working-with-javascript-functions

pub fn callFunction(self: Env, function: Value, recv: Value, args: Values) NapiError!Value {
    var result: c.napi_value = undefined;
    try status.check(
        c.napi_call_function(self.env, function.value, recv.value, args.values.len, args.values.ptr, &result),
    );
    return Value{
        .env = self.env,
        .value = result,
    };
}

pub fn createFunction(self: Env, utf8_name: []const u8, comptime argc: usize, comptime cb: Callback(argc), data: ?*anyopaque) NapiError!Value {
    var value: c.napi_value = undefined;
    const callback = wrapCallback(argc, cb);
    try status.check(
        c.napi_create_function(self.env, utf8_name.ptr, utf8_name.len, callback, data, &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

pub const CbInfo = struct {
    env: c.napi_env,
    args: []c.napi_value,
    this_arg: c.napi_value,
    data: ?*anyopaque,

    pub fn this(self: CbInfo) Value {
        return Value{
            .env = self.env,
            .value = self.this_arg,
        };
    }

    pub fn getArgs(self: CbInfo) Values {
        return Values{
            .env = self.env,
            .values = self.args,
        };
    }
};

pub fn getCbInfo(self: Env, cb_info: c.napi_callback_info, args: Values) NapiError!CbInfo {
    var info: CbInfo = .{
        .env = self.env,
        .args = args.values,
        .this_arg = undefined,
        .data = undefined,
    };
    var argc: usize = args.values.len;
    try status.check(
        c.napi_get_cb_info(self.env, cb_info, &argc, @ptrCast(&info.args), &info.this_arg, &info.data),
    );
    info.args = info.args[0..argc];
    return info;
}

pub fn getNewTarget(self: Env, cb_info: c.napi_callback_info) NapiError!Value {
    var new_target: c.napi_value = undefined;
    try status.check(
        c.napi_get_new_target(self.env, cb_info, &new_target),
    );
    return Value{
        .env = self.env,
        .value = new_target,
    };
}

pub fn newInstance(self: Env, constructor: Value, args: Values) NapiError!Value {
    var instance: c.napi_value = undefined;
    try status.check(
        c.napi_new_instance(self.env, constructor.value, args.values.len, args.values.ptr, &instance),
    );
    return Value{
        .env = self.env,
        .value = instance,
    };
}

pub fn defineClass(
    self: Env,
    utf8_name: []const u8,
    comptime argc: usize,
    comptime constructor: Callback(argc),
    data: ?*anyopaque,
    properties: []const c.napi_property_descriptor,
) NapiError!Value {
    const cb = wrapCallback(argc, constructor);
    var value: c.napi_value = undefined;
    try status.check(
        c.napi_define_class(self.env, utf8_name.ptr, utf8_name.len, cb, data, properties.len, properties.ptr, &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}

pub fn wrap(
    self: Env,
    object: Value,
    comptime Data: type,
    native_object: *Data,
    comptime finalize_cb: ?FinalizeCallback(Data),
    finalize_hint: ?*anyopaque,
) NapiError!Ref {
    var ref_: c.napi_ref = undefined;
    try status.check(
        c.napi_wrap(
            self.env,
            object.value,
            native_object,
            if (finalize_cb) |f| wrapFinalizeCallback(Data, f) else null,
            finalize_hint,
            &ref_,
        ),
    );
    return Ref{
        .env = self.env,
        .ref_ = ref_,
    };
}

pub fn unwrap(self: Env, comptime Data: type, object: Value) NapiError!*Data {
    var native_object: *Data = undefined;
    try status.check(
        c.napi_unwrap(self.env, object.value, @ptrCast(&native_object)),
    );
    return native_object;
}

pub fn removeWrap(self: Env, comptime Data: type, object: Value) NapiError!*Data {
    var native_object: *Data = undefined;
    try status.check(
        c.napi_remove_wrap(self.env, object.value, @ptrCast(&native_object)),
    );
    return native_object;
}

pub fn typeTagObject(self: Env, value: Value, type_tag: c.napi_type_tag) NapiError!void {
    try status.check(
        c.napi_type_tag_object(self.env, value.value, &type_tag),
    );
}

pub fn checkObjectTypeTag(self: Env, value: Value, type_tag: c.napi_type_tag) NapiError!bool {
    var result: bool = undefined;
    try status.check(
        c.napi_check_object_type_tag(self.env, value.value, &type_tag, &result),
    );
    return result;
}

pub fn addFinalizer(self: Env, object: Value, finalize_data: *anyopaque, finalize_cb: c.napi_finalize, finalize_hint: ?*anyopaque) NapiError!Ref {
    var ref_: c.napi_ref = undefined;
    try status.check(
        c.napi_add_finalizer(self.env, object.value, @ptrCast(finalize_data), finalize_cb, finalize_hint, &ref_),
    );
    return Ref{
        .env = self.env,
        .ref_ = ref_,
    };
}

//// Custom asynchronous operations
//// https://nodejs.org/api/n-api.html#custom-asynchronous-operations

pub fn asyncInit(self: Env, async_resource: Value, async_resource_name: Value) NapiError!AsyncContext {
    return try AsyncContext.init(self.env, async_resource, async_resource_name);
}

//// Version management
//// https://nodejs.org/api/n-api.html#version-management

/// https://nodejs.org/api/n-api.html#napi_get_node_version
pub fn getNodeVersion(self: Env) NapiError!NodeVersion {
    var version: c.napi_node_version = undefined;
    try status.check(
        c.napi_get_node_version(self.env, @ptrCast(&version)),
    );
    return NodeVersion{ .version = version };
}

/// https://nodejs.org/api/n-api.html#napi_get_version
pub fn getVersion(self: Env) NapiError!u32 {
    var version: u32 = undefined;
    try status.check(
        c.napi_get_version(self.env, &version),
    );
    return version;
}

//// Memory management
//// https://nodejs.org/api/n-api.html#memory-management

/// https://nodejs.org/api/n-api.html#napi_adjust_external_memory
pub fn adjustExternalMemory(self: Env, delta: i64) NapiError!i64 {
    var result: i64 = undefined;
    try status.check(
        c.napi_adjust_external_memory(self.env, delta, &result),
    );
    return result;
}

//// Promises
//// https://nodejs.org/api/n-api.html#promises

/// https://nodejs.org/api/n-api.html#napi_create_promise
pub fn createPromise(self: Env) NapiError!Deferred {
    return try Deferred.create(self.env);
}
