const c = @import("c.zig");

/// https://nodejs.org/api/n-api.html#napi_status
pub const Status = enum(c.napi_status) {
    ok = c.napi_ok,
    invalid_arg = c.napi_invalid_arg,
    object_expected = c.napi_object_expected,
    string_expected = c.napi_string_expected,
    name_expected = c.napi_name_expected,
    function_expected = c.napi_function_expected,
    number_expected = c.napi_number_expected,
    boolean_expected = c.napi_boolean_expected,
    array_expected = c.napi_array_expected,
    generic_failure = c.napi_generic_failure,
    pending_exception = c.napi_pending_exception,
    cancelled = c.napi_cancelled,
    escape_called_twice = c.napi_escape_called_twice,
    handle_scope_mismatch = c.napi_handle_scope_mismatch,
    callback_scope_mismatch = c.napi_callback_scope_mismatch,
    queue_full = c.napi_queue_full,
    closing = c.napi_closing,
    bigint_expected = c.napi_bigint_expected,
    date_expected = c.napi_date_expected,
    arraybuffer_expected = c.napi_arraybuffer_expected,
    detachable_arraybuffer_expected = c.napi_detachable_arraybuffer_expected,
    would_deadlock = c.napi_would_deadlock,
    no_external_buffers_allowed = c.napi_no_external_buffers_allowed,
    cannot_run_js = c.napi_cannot_run_js,
};

pub const NapiError = error{
    InvalidArg,
    ObjectExpected,
    StringExpected,
    NameExpected,
    FunctionExpected,
    NumberExpected,
    BooleanExpected,
    ArrayExpected,
    GenericFailure,
    PendingException,
    Cancelled,
    EscapeCalledTwice,
    HandleScopeMismatch,
    CallbackScopeMismatch,
    QueueFull,
    Closing,
    BigIntExpected,
    DateExpected,
    ArrayBufferExpected,
    DetachableArrayBufferExpected,
    WouldDeadlock,
    NoExternalBuffersAllowed,
    CannotRunJS,
};

pub fn check(code: c_uint) NapiError!void {
    switch (@as(Status, @enumFromInt(code))) {
        .ok => return,
        .invalid_arg => return error.InvalidArg,
        .object_expected => return error.ObjectExpected,
        .string_expected => return error.StringExpected,
        .name_expected => return error.NameExpected,
        .function_expected => return error.FunctionExpected,
        .number_expected => return error.NumberExpected,
        .boolean_expected => return error.BooleanExpected,
        .array_expected => return error.ArrayExpected,
        .generic_failure => return error.GenericFailure,
        .pending_exception => return error.PendingException,
        .cancelled => return error.Cancelled,
        .escape_called_twice => return error.EscapeCalledTwice,
        .handle_scope_mismatch => return error.HandleScopeMismatch,
        .callback_scope_mismatch => return error.CallbackScopeMismatch,
        .queue_full => return error.QueueFull,
        .closing => return error.Closing,
        .bigint_expected => return error.BigIntExpected,
        .date_expected => return error.DateExpected,
        .arraybuffer_expected => return error.ArrayBufferExpected,
        .detachable_arraybuffer_expected => return error.DetachableArrayBufferExpected,
        .would_deadlock => return error.WouldDeadlock,
        .no_external_buffers_allowed => return error.NoExternalBuffersAllowed,
        .cannot_run_js => return error.CannotRunJS,
    }
}

const std = @import("std");

pub fn exec(comptime napi_func: anytype, napi_args: std.meta.ArgsTuple(@TypeOf(napi_func))) NapiError!void {
    try check(
        @call(.auto, napi_func, napi_args),
    );
}

/// Returns true if the error is an instance of NapiError.
pub fn isNapiError(err: anyerror) bool {
    inline for (comptime std.meta.fields(NapiError)) |field| {
        if (err == @field(NapiError, field.name)) return true;
    }
    return false;
}
