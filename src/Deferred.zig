const c = @import("c.zig");
const status = @import("status.zig");
const NapiError = @import("status.zig").NapiError;
const Value = @import("Value.zig");

env: c.napi_env,
deferred: c.napi_deferred,
promise: c.napi_value,

const Deferred = @This();

pub fn create(env: c.napi_env) NapiError!Deferred {
    var deferred: c.napi_deferred = undefined;
    var promise: c.napi_value = undefined;

    try status.check(
        c.napi_create_promise(env, &deferred, &promise),
    );

    return Deferred{
        .env = env,
        .deferred = deferred,
        .promise = promise,
    };
}

pub fn resolve(self: Deferred, value: Value) NapiError!void {
    try status.check(
        c.napi_resolve_deferred(self.env, self.deferred, value.value),
    );
}

pub fn reject(self: Deferred, value: Value) NapiError!void {
    try status.check(
        c.napi_reject_deferred(self.env, self.deferred, value.value),
    );
}

pub fn getPromise(self: Deferred) Value {
    return Value{
        .env = self.env,
        .value = self.promise,
    };
}
