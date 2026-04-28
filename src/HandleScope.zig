const c = @import("c.zig").c;
const status = @import("status.zig");
const NapiError = @import("status.zig").NapiError;

env: c.napi_env,
scope: c.napi_handle_scope,

const HandleScope = @This();

pub fn open(env: c.napi_env) NapiError!HandleScope {
    var scope: c.napi_handle_scope = undefined;
    try status.check(
        c.napi_open_handle_scope(env, &scope),
    );
    return HandleScope{
        .env = env,
        .scope = scope,
    };
}

pub fn close(self: HandleScope) NapiError!void {
    try status.check(
        c.napi_close_handle_scope(self.env, self.scope),
    );
}
