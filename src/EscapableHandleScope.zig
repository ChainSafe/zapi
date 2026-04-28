const c = @import("c.zig").c;
const status = @import("status.zig");
const NapiError = @import("status.zig").NapiError;
const Value = @import("Value.zig");

env: c.napi_env,
scope: c.napi_escapable_handle_scope,

const EscapableHandleScope = @This();

pub fn open(env: c.napi_env) NapiError!EscapableHandleScope {
    var scope: c.napi_escapable_handle_scope = undefined;
    try status.check(
        c.napi_open_escapable_handle_scope(env, &scope),
    );
    return EscapableHandleScope{
        .env = env,
        .scope = scope,
    };
}

/// https://nodejs.org/api/n-api.html#napi_close_escapable_handle_scope
pub fn close(self: EscapableHandleScope) NapiError!void {
    try status.check(
        c.napi_close_escapable_handle_scope(self.env, self.scope),
    );
}

/// https://nodejs.org/api/n-api.html#napi_escape_handle
pub fn escapeHandle(self: EscapableHandleScope, escapee: Value) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.napi_escape_handle(self.env, self.scope, escapee.value, &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}
