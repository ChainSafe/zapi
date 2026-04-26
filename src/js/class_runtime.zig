const std = @import("std");
const napi = @import("../napi.zig");

pub fn typeTag(comptime T: type) napi.c.napi_type_tag {
    return .{
        .lower = fnv1a64Parts(.{ "zapi:dsl:type-tag:lower:", @typeName(T) }),
        .upper = fnv1a64Parts(.{ "zapi:dsl:type-tag:upper:", @typeName(T) }),
    };
}

pub fn wrapTaggedObject(comptime T: type, env: napi.Env, object: napi.Value, native_object: *T, finalize_hint: ?*anyopaque) !void {
    const tag = typeTag(T);
    try env.wrap(object, T, native_object, defaultFinalize(T), finalize_hint, null);
    errdefer if (env.removeWrap(T, object)) |removed| {
        if (isInternalPlaceholderHint(T, finalize_hint)) {
            destroyInternalPlaceholder(T, removed);
        } else {
            destroyNativeObject(T, removed);
        }
    } else |_| {};
    if (!(try env.checkObjectTypeTag(object, tag))) {
        try env.typeTagObject(object, tag);
    }
}

/// Generates a deterministic 64-bit FNV-1a hash at compile-time.
/// This is used to create stable `napi_type_tag` values for DSL classes
/// based on their type names. FNV-1a is chosen for its simplicity, speed,
/// and suitability for non-cryptographic unique-ish identification.
///
/// The `parts` argument allows concatenating multiple compile-time strings
/// (e.g., prefixes and type names) into a single input for hashing.
fn fnv1a64Parts(comptime parts: anytype) u64 {
    var hash: u64 = 0xcbf29ce484222325;
    inline for (parts) |part| {
        inline for (part) |byte| {
            hash ^= byte;
            hash *%= 0x100000001b3;
        }
    }
    return hash;
}

pub fn destroyNativeObject(comptime T: type, obj: *T) void {
    if (@hasDecl(T, "deinit")) {
        obj.deinit();
    }
    std.heap.c_allocator.destroy(obj);
}

pub fn destroyInternalPlaceholder(comptime T: type, obj: *T) void {
    std.heap.c_allocator.destroy(obj);
}

pub fn defaultFinalize(comptime T: type) napi.FinalizeCallback(T) {
    return struct {
        fn f(_: napi.Env, obj: *T, hint: ?*anyopaque) void {
            if (isInternalPlaceholderHint(T, hint)) {
                destroyInternalPlaceholder(T, obj);
                return;
            }
            destroyNativeObject(T, obj);
        }
    }.f;
}

/// Caches `io` in `state(T).io` for later napi callbacks that can't
/// receive it as a parameter.
pub fn registerClass(comptime T: type, env: napi.Env, ctor: napi.Value, io: std.Io) !void {
    const State = state(T);
    State.io = io;

    try State.mutex.lock(io);
    defer State.mutex.unlock(io);

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
    const placeholder = try env.removeWrapChecked(T, js_instance, typeTag(T));
    destroyInternalPlaceholder(T, placeholder);

    const obj_ptr = try std.heap.c_allocator.create(T);
    obj_ptr.* = instance;

    try wrapTaggedObject(T, env, js_instance, obj_ptr, null);
    return js_instance;
}

fn getConstructor(comptime T: type, env: napi.Env) !napi.Value {
    const State = state(T);

    try State.mutex.lock(State.io);
    defer State.mutex.unlock(State.io);

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
            ctor_ref: napi.Ref,
            next: ?*Entry,
        };

        var head: ?*Entry = null;
        var mutex: std.Io.Mutex = .init;
        /// Set by `registerClass`; read by later callbacks.
        var io: std.Io = undefined;

        fn find(env_ptr: napi.c.napi_env) ?*Entry {
            var current = head;
            while (current) |entry| : (current = entry.next) {
                if (entry.env == env_ptr) return entry;
            }
            return null;
        }

        fn cleanupHook(entry: *Entry) void {
            // Napi callbacks have no way to propagate `error.Canceled`, so
            // this path must complete — use the uncancelable variant.
            mutex.lockUncancelable(io);
            defer mutex.unlock(io);

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
