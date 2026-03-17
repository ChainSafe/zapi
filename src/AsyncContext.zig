const c = @import("c.zig");
const status = @import("status.zig");
const NapiError = @import("status.zig").NapiError;
const Value = @import("Value.zig");
const argsTupleToRaw = @import("args.zig").tupleToRaw;

env: c.napi_env,
async_context: c.napi_async_context,

const AsyncContext = @This();

/// https://nodejs.org/api/n-api.html#napi_async_init
pub fn init(env: c.napi_env, async_resource: Value, async_resource_name: Value) NapiError!AsyncContext {
    var async_context: c.napi_async_context = undefined;
    try status.check(
        c.napi_async_init(env, async_resource.value, async_resource_name.value, &async_context),
    );
    return AsyncContext{ .env = env, .async_context = async_context };
}

/// https://nodejs.org/api/n-api.html#napi_async_destroy
pub fn destroy(self: AsyncContext) NapiError!void {
    try status.check(
        c.napi_async_destroy(self.env, self.async_context),
    );
}

/// https://nodejs.org/api/n-api.html#napi_make_callback
pub fn makeCallbackRaw(self: AsyncContext, recv: Value, func: Value, args: []const c.napi_value) NapiError!Value {
    var result: c.napi_value = undefined;
    try status.check(
        c.napi_make_callback(
            self.env,
            self.async_context,
            recv.value,
            func.value,
            args.len,
            if (args.len > 0) args.ptr else null,
            &result,
        ),
    );
    return Value{
        .env = self.env,
        .value = result,
    };
}

/// `args` must be a tuple containing only `napi.Value` objects.
pub fn makeCallback(self: AsyncContext, recv: Value, func: Value, args: anytype) NapiError!Value {
    var argv = argsTupleToRaw(args);
    return try self.makeCallbackRaw(recv, func, argv[0..]);
}

pub const CallbackScope = struct {
    env: c.napi_env,
    scope: c.napi_callback_scope,

    /// https://nodejs.org/api/n-api.html#napi_open_callback_scope
    pub fn open(env: c.napi_env, async_context: c.napi_async_context) NapiError!CallbackScope {
        var scope: c.napi_callback_scope = undefined;
        try status.check(
            c.napi_open_callback_scope(env, null, async_context, &scope),
        );
        return CallbackScope{ .env = env, .scope = scope };
    }

    /// https://nodejs.org/api/n-api.html#napi_close_callback_scope
    pub fn close(self: CallbackScope) NapiError!void {
        try status.check(
            c.napi_close_callback_scope(self.env, self.scope),
        );
    }
};

/// https://nodejs.org/api/n-api.html#napi_open_callback_scope
pub fn openCallbackScope(self: AsyncContext) NapiError!CallbackScope {
    return try CallbackScope.open(self.env, self.async_context);
}
