const c = @import("c.zig").c;
const status = @import("status.zig");
const NapiError = @import("status.zig").NapiError;
const Value = @import("Value.zig");

env: c.napi_env,
ref_: c.napi_ref,

const Ref = @This();

pub fn create(env: c.napi_env, value: Value, initial_refcount: u32) NapiError!Ref {
    var ref_: c.napi_ref = undefined;
    try status.check(
        c.napi_create_reference(env, value.value, initial_refcount, &ref_),
    );
    return Ref{
        .env = env,
        .ref_ = ref_,
    };
}

/// https://nodejs.org/api/n-api.html#napi_delete_reference
pub fn delete(self: Ref) NapiError!void {
    try status.check(
        c.napi_delete_reference(self.env, self.ref_),
    );
}

/// https://nodejs.org/api/n-api.html#napi_reference_ref
pub fn ref(self: Ref) NapiError!u32 {
    var refcount: u32 = undefined;
    try status.check(
        c.napi_reference_ref(self.env, self.ref_, &refcount),
    );
    return refcount;
}

/// https://nodejs.org/api/n-api.html#napi_reference_unref
pub fn unref(self: Ref) NapiError!u32 {
    var refcount: u32 = undefined;
    try status.check(
        c.napi_reference_unref(self.env, self.ref_, &refcount),
    );
    return refcount;
}

/// https://nodejs.org/api/n-api.html#napi_get_reference_value
pub fn getValue(self: Ref) NapiError!Value {
    var value: c.napi_value = undefined;
    try status.check(
        c.napi_get_reference_value(self.env, self.ref_, &value),
    );
    return Value{
        .env = self.env,
        .value = value,
    };
}
