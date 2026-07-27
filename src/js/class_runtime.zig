const std = @import("std");
const napi = @import("../napi.zig");
const context = @import("context.zig");
const class_meta = @import("class_meta.zig");

/// Returns a stable tag derived from the addon's salt and the Zig class name.
/// A class-level `.type_tag` salt replaces the module salt when present.
pub fn typeTag(comptime T: type, comptime module_salt: []const u8) napi.c.napi_type_tag {
    const salt = comptime class_meta.getTypeTagSalt(T) orelse module_salt;
    return typeTagFromParts(.{ salt, "::", @typeName(T) });
}

/// Tags `object`, then wraps `native_object` into it with a finalizer.
///
/// The wrap is done last so it is the only fallible step that transfers
/// ownership: once it succeeds N-API's finalizer owns `native_object`, and any
/// earlier failure leaves nothing wrapped, so the caller still owns and frees it.
pub fn wrapTaggedObject(
    comptime T: type,
    comptime module_salt: []const u8,
    env: napi.Env,
    object: napi.Value,
    native_object: *T,
) !void {
    const tag = typeTag(T, module_salt);
    if (!(try env.checkObjectTypeTag(object, tag))) {
        try env.typeTagObject(object, tag);
    }
    try env.wrap(object, T, native_object, defaultFinalize(T), null, null);
}

/// Builds a stable 128-bit Node-API type tag from a content identity using FNV-1a.
fn typeTagFromParts(comptime parts: anytype) napi.c.napi_type_tag {
    var hash: u128 = 0x6c62272e07bb0142_62b821756295c58d;
    inline for (parts) |part| {
        inline for (part) |byte| {
            hash ^= byte;
            hash *%= 0x0000000001000000_000000000000013B;
        }
    }
    return .{
        .lower = @truncate(hash),
        .upper = @truncate(hash >> 64),
    };
}

fn typeTagFromIdent(comptime ident: []const u8) napi.c.napi_type_tag {
    return typeTagFromParts(.{ident});
}

pub fn destroyNativeObject(comptime T: type, obj: *T) void {
    if (@hasDecl(T, "deinit")) {
        obj.deinit();
    }
    context.allocator().destroy(obj);
}

pub fn defaultFinalize(comptime T: type) napi.FinalizeCallback(T) {
    return struct {
        fn f(_: napi.Env, obj: *T, _: ?*anyopaque) void {
            destroyNativeObject(T, obj);
        }
    }.f;
}

pub fn registerClass(comptime T: type, env: napi.Env, ctor: napi.Value) !void {
    const State = state(T);

    State.lock();
    defer State.unlock();

    if (State.find(env.env) != null) return;

    const entry = try context.allocator().create(State.Entry);
    errdefer context.allocator().destroy(entry);

    entry.* = .{
        .env = env.env,
        .ctor_ref = try env.createReference(ctor, 1),
        .next = State.head,
    };
    errdefer entry.ctor_ref.delete() catch {};

    // Link only after the cleanup hook is registered: a hook failure must not
    // leave a freed entry reachable from the list head.
    try env.addEnvCleanupHook(State.Entry, entry, State.cleanupHook);
    State.head = entry;
}

/// Per-thread marker set by `materializeClassInstance` to tell the generated
/// constructor "this `new` call comes from the DSL; return the JS instance
/// without running `init`, and materialization will wrap the native object."
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

pub fn materializeClassInstance(
    comptime T: type,
    comptime module_salt: []const u8,
    env: napi.Env,
    instance: T,
    preferred_ctor: ?napi.Value,
) !napi.Value {
    const ctor = preferred_ctor orelse try getConstructor(T, env);

    const obj_ptr = try context.allocator().create(T);
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

    try wrapTaggedObject(T, module_salt, env, js_instance, obj_ptr);
    return js_instance;
}

fn getConstructor(comptime T: type, env: napi.Env) !napi.Value {
    const State = state(T);

    State.lock();
    defer State.unlock();

    const entry = State.find(env.env) orelse return error.ClassNotRegistered;
    return try entry.ctor_ref.getValue();
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
                    context.allocator().destroy(current);
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
    };
}

fn internalCtorMarkerPtr(comptime T: type) *u8 {
    return &markers(T).ctor_marker;
}

test "distinct type tag identities produce distinct tags" {
    try std.testing.expect(
        !std.meta.eql(
            typeTagFromIdent("addon@example::mod.Foo"),
            typeTagFromIdent("addon@example::mod.Bar"),
        ),
    );
}

test "module salts distinguish the same Zig class" {
    const Tagged = struct {
        pub const js_meta = class_meta.class(.{});
    };
    try std.testing.expect(
        !std.meta.eql(typeTag(Tagged, "addon-a"), typeTag(Tagged, "addon-b")),
    );
}

test "class salt overrides the module salt" {
    const Tagged = struct {
        pub const js_meta = class_meta.class(.{ .type_tag = "class-uuid" });
    };
    try std.testing.expectEqual(
        typeTag(Tagged, "addon-a"),
        typeTag(Tagged, "addon-b"),
    );
}

test "type tag identity hashing is deterministic" {
    try std.testing.expectEqual(
        typeTagFromIdent("addon@example::mod.Foo"),
        typeTagFromIdent("addon@example::mod.Foo"),
    );
}

test "type tag identity hashing matches the FNV-1a known vector" {
    try std.testing.expectEqual(
        napi.c.napi_type_tag{
            .lower = 9205288767444028904,
            .upper = 12488879969338687231,
        },
        typeTagFromIdent("napi@1.0.0::x::Foo"),
    );
}
