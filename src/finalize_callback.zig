const std = @import("std");
const c = @import("c.zig").c;
const Env = @import("Env.zig");

pub fn FinalizeCallback(comptime Data: type) type {
    return *const fn (Env, *Data, ?*anyopaque) void;
}

pub fn wrapFinalizeCallback(
    comptime Data: type,
    comptime finalize_cb: FinalizeCallback(Data),
) c.napi_finalize {
    const wrapper = struct {
        pub fn f(
            env: c.napi_env,
            data: ?*anyopaque,
            hint: ?*anyopaque,
        ) callconv(.c) void {
            if (data == null) return;
            return finalize_cb(
                Env{ .env = env },
                @ptrCast(@alignCast(data)),
                hint,
            );
        }
    };
    return wrapper.f;
}

/// Typed finalizer for externally backed buffers.
///
/// The C-ABI `napi_finalize` parameters (`?*anyopaque` data, `?*anyopaque` hint)
/// are unpacked into a single `[]Element` slice. By convention this helper
/// expects the hint pointer slot to carry the element count (set via
/// `@ptrFromInt(slice.len)` at creation time).
pub fn SliceFinalizeCallback(comptime Element: type) type {
    return *const fn (Env, []Element) void;
}

pub fn wrapSliceFinalizeCallback(
    comptime Element: type,
    comptime finalize_cb: SliceFinalizeCallback(Element),
) c.napi_finalize {
    const wrapper = struct {
        pub fn f(
            env: c.napi_env,
            data: ?*anyopaque,
            hint: ?*anyopaque,
        ) callconv(.c) void {
            if (data == null) return;
            const len: usize = @intFromPtr(hint);
            const ptr: [*]Element = @ptrCast(@alignCast(data));
            return finalize_cb(Env{ .env = env }, ptr[0..len]);
        }
    };
    return wrapper.f;
}
