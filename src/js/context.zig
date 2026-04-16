const std = @import("std");
const napi = @import("../napi.zig");

/// Thread-local N-API environment, set by the generated callback wrappers.
///
/// SAFETY: DSL types (Number, String, etc.) and `js.env()` are only valid
/// within the synchronous scope of a JS callback. Do not store DSL types
/// across callbacks or use them from worker threads. For async work, use
/// `napi.AsyncWork` or `napi.ThreadSafeFunction` from the low-level API.
threadlocal var current_env: ?napi.Env = null;

pub fn env() napi.Env {
    return current_env orelse @panic("js.env() called outside of a JS callback context");
}

pub fn allocator() std.mem.Allocator {
    return std.heap.c_allocator;
}

pub fn setEnv(e: napi.Env) ?napi.Env {
    const prev = current_env;
    current_env = e;
    return prev;
}

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
