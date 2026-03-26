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
