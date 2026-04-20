const std = @import("std");
const napi = @import("../napi.zig");

/// Thread-local N-API environment, set by the generated callback wrappers.
///
/// SAFETY: DSL types (Number, String, etc.) and `js.env()` are only valid
/// within the synchronous scope of a JS callback. Do not store DSL types
/// across callbacks or use them from worker threads. For async work, use
/// `napi.AsyncWork` or `napi.ThreadSafeFunction` from the low-level API.
threadlocal var current_env: ?napi.Env = null;

/// Returns the active N-API environment for the current synchronous callback.
///
/// This function provides access to the N-API environment (`napi_env`) context
/// that is implicitly managed by the DSL's callback wrappers. It is essential
/// for any low-level N-API operations or manual creation of `napi.Value`s.
///
/// SAFETY: This function is only valid when called within the synchronous
/// execution scope of a JavaScript function, method, getter, or setter that
/// was exposed to JS via the ZAPI DSL. Calling it outside such a context
/// (e.g., from a background thread or a Zig-initiated function call) will
/// result in a panic. For asynchronous N-API work, use `napi.AsyncWork` or
/// `napi.ThreadSafeFunction` which provide explicit `napi_env` parameters.
pub fn env() napi.Env {
    return current_env orelse @panic("js.env() called outside of a JS callback context");
}

/// Returns the standard C allocator (`std.heap.c_allocator`) used by the DSL
/// for all native memory allocations related to JavaScript objects.
///
/// This allocator should be used when:
/// - Allocating native memory that will be wrapped by a JS object (e.g., for
///   `napi.Env.wrap()`).
/// - Allocating memory that will be freed by an N-API finalizer.
/// - Performing general-purpose allocations within the synchronous N-API callback
///   context.
///
/// It aligns with the memory management expectations of Node-API, and memory
/// allocated with it can generally be freed by `std.heap.c_allocator.free()`.
pub fn allocator() std.mem.Allocator {
    return std.heap.c_allocator;
}

/// Sets the thread-local N-API environment for the current context.
///
/// This function is primarily used internally by the ZAPI DSL's generated
/// wrappers to establish the correct `napi_env` before executing Zig callback
/// logic. Custom wrappers or advanced DSL integrations might use this to
/// temporarily change the active environment.
///
/// It returns the previously active `napi.Env`, allowing for proper restoration
/// using `restoreEnv` (typically with `defer`).
pub fn setEnv(e: napi.Env) ?napi.Env {
    const prev = current_env;
    current_env = e;
    return prev;
}

/// Restores the thread-local N-API environment to a previous state.
///
/// This function is typically used in conjunction with `setEnv` to ensure that
/// the `napi_env` is correctly reset after a temporary change. It is common
/// to see `defer restoreEnv(prev)` immediately after a `setEnv` call.
pub fn restoreEnv(prev: ?napi.Env) void {
    current_env = prev;
}

/// Thread-local JS `this` value, set by method/getter/setter callback wrappers.
///
/// This is the actual JavaScript receiver object for the current call, after JS
/// binding semantics have been applied. For example, if a method is invoked via
/// `obj1.method.call(obj2, ...)` or `obj1.method.bind(obj2)(...)`, then
/// `js.thisArg()` refers to `obj2`, not `obj1`.
///
/// In an instance method/getter/setter, the Zig `self` parameter is the native
/// object unwrapped from this same receiver. That means `self` and
/// `js.thisArg()` correspond to the same runtime receiver, but at different
/// levels:
/// - `self` is the unwrapped native Zig payload
/// - `js.thisArg()` is the original JS object carrying that payload
///
/// Only valid within instance method or getter/setter scope.
threadlocal var current_this: ?napi.Value = null;

/// Returns the active JavaScript receiver object for the current instance
/// method/getter/setter invocation.
pub fn thisArg() napi.Value {
    return current_this orelse @panic("js.thisArg() called outside of an instance method/getter/setter context");
}

pub fn setThis(t: napi.Value) ?napi.Value {
    const prev = current_this;
    current_this = t;
    return prev;
}

pub fn restoreThis(prev: ?napi.Value) void {
    current_this = prev;
}

test "allocator returns c_allocator" {
    const alloc = allocator();
    const mem = try alloc.alloc(u8, 16);
    defer alloc.free(mem);
    try std.testing.expect(mem.len == 16);
}

test "current_env is null by default" {
    try std.testing.expect(current_env == null);
}

test "restoreEnv with null preserves null state" {
    restoreEnv(null);
    try std.testing.expect(current_env == null);
}
