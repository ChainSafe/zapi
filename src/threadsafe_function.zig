const std = @import("std");
const c = @import("c.zig");
const status = @import("status.zig");
const NapiError = status.NapiError;
const Env = @import("Env.zig");
const Value = @import("Value.zig");

// Callback signature for calling into JS
// env: The environment of the main thread
// js_callback: The JS function passed to create (or undefined if none)
// context: The context data attached to the TSFN
// data: The data passed to call()
pub fn ThreadSafeCallJsCallback(comptime Context: type, comptime CallData: type) type {
    return *const fn (Env, Value, *Context, *CallData) void;
}

// Callback signature for finalization
pub fn FinalizeCallback(comptime Context: type) type {
    return *const fn (Env, *Context) void;
}

pub fn wrapCallJsCallback(
    comptime Context: type,
    comptime CallData: type,
    comptime cb: ThreadSafeCallJsCallback(Context, CallData),
) c.napi_threadsafe_function_call_js {
    const wrapper = struct {
        fn call(
            raw_env: c.napi_env,
            raw_js_callback: c.napi_value,
            raw_context: ?*anyopaque,
            raw_data: ?*anyopaque,
        ) callconv(.C) void {
            // If raw_env is null, the TSFN is being torn down.
            if (raw_env == null) return;
            // Context should be present if we customized it
            if (raw_context == null and Context != void) return;

            const env = Env{ .env = raw_env };
            const js_callback = Value{ .env = raw_env, .value = raw_js_callback };

            // Handle void context or data gracefully
            const context: *Context = if (Context == void) undefined else @ptrCast(@alignCast(raw_context));
            const data: *CallData = if (CallData == void) undefined else @ptrCast(@alignCast(raw_data));

            cb(env, js_callback, context, data);
        }
    };
    return wrapper.call;
}

pub fn wrapFinalizeCallback(
    comptime Context: type,
    comptime cb: FinalizeCallback(Context),
) c.napi_finalize {
    const wrapper = struct {
        fn call(
            raw_env: c.napi_env,
            raw_data: ?*anyopaque,
            hint: ?*anyopaque,
        ) callconv(.C) void {
            _ = hint;
            if (raw_data == null and Context != void) return;
            const env = Env{ .env = raw_env };
            const context: *Context = if (Context == void) undefined else @ptrCast(@alignCast(raw_data));
            cb(env, context);
        }
    };
    return wrapper.call;
}

pub const CallMode = enum(c.napi_threadsafe_function_call_mode) {
    blocking = c.napi_tsfn_blocking,
    non_blocking = c.napi_tsfn_nonblocking,
};

pub const ReleaseMode = enum(c.napi_threadsafe_function_release_mode) {
    release = c.napi_tsfn_release,
    block = c.napi_tsfn_abort,
};

pub fn ThreadSafeFunction(comptime Context: type, comptime CallData: type) type {
    return struct {
        tsfn: c.napi_threadsafe_function,

        const Self = @This();

        pub fn create(
            env: Env,
            func: ?Value,
            async_resource: ?Value,
            async_resource_name: Value,
            max_queue_size: usize,
            initial_thread_count: usize,
            context: *Context,
            comptime finalize_cb: ?FinalizeCallback(Context),
            comptime call_js_cb: ?ThreadSafeCallJsCallback(Context, CallData),
        ) NapiError!Self {
            var tsfn: c.napi_threadsafe_function = undefined;

            try status.check(c.napi_create_threadsafe_function(
                env.env,
                if (func) |f| f.value else null,
                if (async_resource) |r| r.value else null,
                async_resource_name.value,
                max_queue_size,
                initial_thread_count,
                context, // finalize_data
                if (finalize_cb) |cb| wrapFinalizeCallback(Context, cb) else null,
                context, // context
                if (call_js_cb) |cb| wrapCallJsCallback(Context, CallData, cb) else null,
                &tsfn,
            ));

            return Self{ .tsfn = tsfn };
        }

        pub fn getContext(self: Self) NapiError!*Context {
            if (Context == void) return error.VoidContext;
            var context: ?*anyopaque = undefined;
            try status.check(c.napi_get_threadsafe_function_context(self.tsfn, &context));
            return @ptrCast(@alignCast(context));
        }

        /// Calls the thread-safe function.
        /// `data` must persist until the callback runs (unless it's a value type fitting in pointer, but here we use pointers).
        /// If CallData is void, passed data is ignored.
        pub fn call(self: Self, data: *CallData, mode: CallMode) NapiError!void {
            try status.check(c.napi_call_threadsafe_function(self.tsfn, if (CallData == void) null else data, @intFromEnum(mode)));
        }

        pub fn acquire(self: Self) NapiError!void {
            try status.check(c.napi_acquire_threadsafe_function(self.tsfn));
        }

        pub fn release(self: Self, mode: ReleaseMode) NapiError!void {
            try status.check(c.napi_release_threadsafe_function(self.tsfn, @intFromEnum(mode)));
        }

        pub fn ref(self: Self, env: Env) NapiError!void {
            try status.check(c.napi_ref_threadsafe_function(env.env, self.tsfn));
        }

        pub fn unref(self: Self, env: Env) NapiError!void {
            try status.check(c.napi_unref_threadsafe_function(env.env, self.tsfn));
        }
    };
}
