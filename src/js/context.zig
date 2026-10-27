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
/// result in a panic. `js.spawn`'s completion callback establishes this
/// context, so a task's `resolve` may build DSL values; its `compute` runs on
/// a worker thread and deliberately does not. For raw asynchronous N-API work,
/// use `napi.AsyncWork` or `napi.ThreadSafeFunction`, which provide explicit
/// `napi_env` parameters.
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
/// using `restoreEnv` (typically with `defer`). Every `setEnv` must be paired
/// with exactly one `restoreEnv`, since the pair also scopes `js.scratch()`.
pub fn setEnv(e: napi.Env) ?napi.Env {
    const prev = current_env;
    current_env = e;
    scratch_depth += 1;
    return prev;
}

/// Restores the thread-local N-API environment to a previous state.
///
/// This function is typically used in conjunction with `setEnv` to ensure that
/// the `napi_env` is correctly reset after a temporary change. It is common
/// to see `defer restoreEnv(prev)` immediately after a `setEnv` call.
pub fn restoreEnv(prev: ?napi.Env) void {
    current_env = prev;
    scratch_depth -= 1;
    if (scratch_depth == 0) {
        _ = scratch_arena.reset(.{ .retain_with_limit = scratch_retain_limit });
    }
}

/// Per-thread arena behind `js.scratch()`. `scratch_depth` counts nested
/// `setEnv` scopes so the arena is reset only when the outermost one exits.
threadlocal var scratch_arena: std.heap.ArenaAllocator = .init(std.heap.c_allocator);
threadlocal var scratch_depth: u32 = 0;

/// Capacity kept across resets so steady-state calls don't hit the C allocator.
const scratch_retain_limit = 64 * 1024;

/// Returns an arena allocator for temporary allocations within the current
/// JS callback. Everything allocated from it is freed when the outermost
/// callback on this thread returns, so there is no need to call `free`.
///
/// Nested callbacks (Zig calls JS which calls back into Zig) share the arena,
/// so memory from an outer callback stays valid while inner ones run.
///
/// SAFETY: Valid in the same scope as `js.env()`. Never store scratch memory
/// past the callback, hand it to a finalizer, or use it from a worker thread
/// (e.g. `js.spawn`'s `compute`); use `js.allocator()` for those.
pub fn scratch() std.mem.Allocator {
    if (scratch_depth == 0) @panic("js.scratch() called outside of a JS callback context");
    return scratch_arena.allocator();
}

/// Frees this thread's scratch arena, including retained capacity. Called from
/// the env cleanup hook installed by `js.exportModule(...)`.
pub fn freeScratch() void {
    if (scratch_depth == 0) _ = scratch_arena.reset(.free_all);
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
    const prev = setEnv(.{ .env = null });
    restoreEnv(prev);
    try std.testing.expect(current_env == null);
}

test "scratch memory survives nested scopes and resets after the outermost" {
    const outer_prev = setEnv(.{ .env = null });
    const outer = try scratch().dupe(u8, "outer");

    const inner_prev = setEnv(.{ .env = null });
    _ = try scratch().alloc(u8, 1024);
    restoreEnv(inner_prev);

    _ = try scratch().dupe(u8, "XXXXX");
    try std.testing.expectEqualStrings("outer", outer);
    try std.testing.expectEqual(@as(u32, 1), scratch_depth);

    _ = try scratch().alloc(u8, 2 * scratch_retain_limit);
    restoreEnv(outer_prev);

    try std.testing.expectEqual(@as(u32, 0), scratch_depth);
    try std.testing.expect(scratch_arena.queryCapacity() <= scratch_retain_limit);

    freeScratch();
    try std.testing.expectEqual(@as(usize, 0), scratch_arena.queryCapacity());
}
