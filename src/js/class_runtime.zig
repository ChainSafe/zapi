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

pub fn registerClass(comptime T: type, env: napi.Env, ctor: napi.Value) !void {
    const State = state(T);

    State.lock();
    defer State.unlock();

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

/// Per-thread marker set by `materializeClassInstance` to tell the generated
/// constructor "this `new` call comes from the DSL — don't allocate a placeholder,
/// I'll wrap with the real object after `napi_new_instance` returns."
/// Compared by identity against `internalCtorMarkerPtr(T)`.
threadlocal var materialize_target: ?*const anyopaque = null;

/// Captures the exact `this` object whose generated base constructor consumed
/// `materialize_target`. JS derived constructors are allowed to `return {}`
/// after `super()`, causing `napi_new_instance` to return that replacement
/// object. Materialization must reject that case instead of wrapping native
/// state onto an unrelated object with the wrong prototype.
///
/// Stored as a temporary N-API reference because nested JS construction can run
/// before `napi_new_instance` returns; keeping only the raw constructor callback
/// handle is not stable enough across that nested call stack.
threadlocal var materialized_instance: ?napi.Ref = null;

pub fn isMaterializing(comptime T: type) bool {
    return materialize_target == @as(?*const anyopaque, @ptrCast(internalCtorMarkerPtr(T)));
}

pub fn hasPendingMaterialization() bool {
    return materialize_target != null;
}

pub fn consumeMaterialization(comptime T: type, env: napi.Env, this_arg: napi.c.napi_value) !bool {
    if (!isMaterializing(T)) return false;
    const this_val = napi.Value{ .env = env.env, .value = this_arg };
    const this_ref = try env.createReference(this_val, 1);
    materialize_target = null;
    materialized_instance = this_ref;
    return true;
}

pub fn materializeClassInstance(comptime T: type, env: napi.Env, instance: T, preferred_ctor: ?napi.Value) !napi.Value {
    const ctor = preferred_ctor orelse try getConstructor(T, env);

    const obj_ptr = try std.heap.c_allocator.create(T);
    errdefer destroyNativeObject(T, obj_ptr);
    obj_ptr.* = instance;

    const prev = materialize_target;
    const prev_instance = materialized_instance;
    materialize_target = @ptrCast(internalCtorMarkerPtr(T));
    materialized_instance = null;
    defer materialize_target = prev;
    defer {
        if (materialized_instance) |ref| ref.delete() catch {};
        materialized_instance = prev_instance;
    }

    var js_instance_raw: napi.c.napi_value = null;
    try napi.status.check(napi.c.napi_new_instance(
        env.env,
        ctor.value,
        0,
        null,
        &js_instance_raw,
    ));

    const js_instance = napi.Value{ .env = env.env, .value = js_instance_raw };
    if (materialize_target != null) return error.InvalidMaterializationConstructor;
    const expected_instance_ref = materialized_instance orelse return error.InvalidMaterializationConstructor;
    const expected_instance = try expected_instance_ref.getValue();
    // The generated constructor must be the object that comes back from
    // `napi_new_instance`; otherwise a subclass returned a replacement object.
    if (!(try expected_instance.strictEquals(js_instance))) return error.InvalidMaterializationConstructor;

    try wrapTaggedObject(T, env, js_instance, obj_ptr, null);
    return js_instance;
}

fn getConstructor(comptime T: type, env: napi.Env) !napi.Value {
    const State = state(T);

    State.lock();
    defer State.unlock();

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
        var locked: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

        fn lock() void {
            while (locked.cmpxchgWeak(false, true, .acquire, .monotonic) != null) {
                std.atomic.spinLoopHint();
            }
        }

        fn unlock() void {
            locked.store(false, .release);
        }

        fn find(env_ptr: napi.c.napi_env) ?*Entry {
            var current = head;
            while (current) |entry| : (current = entry.next) {
                if (entry.env == env_ptr) return entry;
            }
            return null;
        }

        fn cleanupHook(entry: *Entry) void {
            lock();
            defer unlock();

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
