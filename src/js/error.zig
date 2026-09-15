const napi = @import("../napi.zig");

/// Builds `new Error(message)`, the value JS sees as a thrown or rejected error.
///
/// `env` is explicit so this is usable outside a DSL callback — notably in a
/// task's `reject`, which runs in an async completion callback.
pub fn errorWithMessage(env: napi.Env, message: []const u8) !napi.Value {
    const msg_val = try env.createStringUtf8(message);
    return env.createError(napi.Value{ .env = env.env, .value = null }, msg_val);
}
