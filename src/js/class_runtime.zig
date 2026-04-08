const std = @import("std");
const napi = @import("../napi.zig");

pub fn destroyNativeObject(comptime T: type, obj: *T) void {
    if (@hasDecl(T, "deinit")) {
        obj.deinit();
    }
    std.heap.c_allocator.destroy(obj);
}

pub fn destroyInternalPlaceholder(comptime T: type, obj: *T) void {
    std.heap.c_allocator.destroy(obj);
}

pub fn defaultFinalize(comptime T: type) @import("../finalize_callback.zig").FinalizeCallback(T) {
    return struct {
        fn f(_: napi.Env, obj: *T, _: ?*anyopaque) void {
            destroyNativeObject(T, obj);
        }
    }.f;
}

pub fn registerClass(comptime T: type, env: napi.Env, ctor: napi.Value) !void {
    const State = state(T);

    State.mutex.lock();
    defer State.mutex.unlock();

    if (State.find(env.env) != null) return;

    const entry = try std.heap.c_allocator.create(State.Entry);
    errdefer std.heap.c_allocator.destroy(entry);

    entry.* = .{
        .env = env.env,
        .ctor_ref = try env.createReference(ctor, 1),
        .next = State.head,
    };
    State.head = entry;

    try env.addEnvCleanupHook(State.Entry, entry, State.cleanupHook);
}

pub fn materializeClassInstance(comptime T: type, env: napi.Env, instance: T, preferred_ctor: ?napi.Value) !napi.Value {
    const ctor = preferred_ctor orelse try getConstructor(T, env);
    const internal_arg = try env.createExternal(@ptrCast(internalCtorMarkerPtr(T)), null, null);
    var raw_args = [_]napi.c.napi_value{internal_arg.value};

    var js_instance_raw: napi.c.napi_value = null;
    try napi.status.check(napi.c.napi_new_instance(
        env.env,
        ctor.value,
        1,
        &raw_args,
        &js_instance_raw,
    ));

    const js_instance = napi.Value{ .env = env.env, .value = js_instance_raw };
    const placeholder = try env.removeWrap(T, js_instance);
    destroyInternalPlaceholder(T, placeholder);

    const obj_ptr = try std.heap.c_allocator.create(T);
    errdefer std.heap.c_allocator.destroy(obj_ptr);
    obj_ptr.* = instance;

    try env.wrap(js_instance, T, obj_ptr, defaultFinalize(T), null, null);
    return js_instance;
}

fn getConstructor(comptime T: type, env: napi.Env) !napi.Value {
    const State = state(T);

    State.mutex.lock();
    defer State.mutex.unlock();

    const entry = State.find(env.env) orelse return error.ClassNotRegistered;
    return try entry.ctor_ref.getValue();
}

pub fn isInternalCtorArg(comptime T: type, value: napi.Value) bool {
    const raw = value.getValueExternal() catch return false;
    return raw == @as(*anyopaque, @ptrCast(internalCtorMarkerPtr(T)));
}

pub fn internalPlaceholderHint(comptime T: type) ?*anyopaque {
    return @ptrCast(&markers(T).placeholder_hint);
}

pub fn isInternalPlaceholderHint(comptime T: type, hint: ?*anyopaque) bool {
    return hint == internalPlaceholderHint(T);
}

fn state(comptime T: type) type {
    return struct {
        const Class = T;
        comptime {
            _ = Class;
        }

        const Entry = struct {
            env: napi.c.napi_env,
            ctor_ref: @import("../Ref.zig"),
            next: ?*Entry,
        };

        var head: ?*Entry = null;
        var mutex: std.Thread.Mutex = .{};

        fn find(env_ptr: napi.c.napi_env) ?*Entry {
            var current = head;
            while (current) |entry| : (current = entry.next) {
                if (entry.env == env_ptr) return entry;
            }
            return null;
        }

        fn cleanupHook(entry: *Entry) void {
            mutex.lock();
            defer mutex.unlock();

            var cursor = &head;
            while (cursor.*) |current| {
                if (current == entry) {
                    cursor.* = current.next;
                    current.ctor_ref.delete() catch {};
                    std.heap.c_allocator.destroy(current);
                    return;
                }
                cursor = &current.next;
            }
        }
    };
}

fn markers(comptime T: type) type {
    return struct {
        const Class = T;
        comptime {
            _ = Class;
        }

        var ctor_marker: u8 = 0;
        var placeholder_hint: u8 = 0;
    };
}

fn internalCtorMarker(comptime T: type) [*]const u8 {
    return internalCtorMarkerPtr(T);
}

fn internalCtorMarkerPtr(comptime T: type) *u8 {
    return &markers(T).ctor_marker;
}
