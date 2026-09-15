//! Worker-thread async DSL: run Zig work on the libuv pool, settle a JS Promise.
//!
//! A Task is any struct providing:
//!  - `compute(*Task) !void` — worker thread; must not call napi
//!  - `resolve(*Task, napi.Env) !T` — JS thread; `T` may be a DSL type, an owned
//!    typed array, `napi.Value`, or `void`
//!  - `deinit(*Task) void` — must be safe after `resolve` transferred ownership
//!  - optional `reject(*Task, napi.Env, anyerror) !napi.Value`, else the
//!    rejection is `Error(@errorName(err))`
//!
//! `spawn` failing leaves the task to the caller; succeeding transfers ownership.

const std = @import("std");
const napi = @import("../napi.zig");
const context = @import("context.zig");
const typed_arrays = @import("typed_arrays.zig");
const wrap_function = @import("wrap_function.zig");
const js_error = @import("error.zig");
const Value = @import("value.zig").Value;

/// Runs `task.compute` on the libuv worker pool, returning a JS Promise that
/// settles with `task.resolve(env)`. `resource_name` labels the async resource.
pub fn spawn(comptime Task: type, task: Task, comptime resource_name: []const u8) !Value {
    comptime validateTask(Task);

    const Context = struct {
        task: Task,
        err: ?anyerror,
        deferred: napi.Deferred,
        work: napi.c.napi_async_work,

        const Self = @This();

        /// Worker thread. No DSL env context on purpose: napi is illegal here.
        fn execute(_: napi.Env, ctx: *Self) void {
            ctx.task.compute() catch |err| {
                ctx.err = err;
            };
        }

        /// JS thread. Sets the DSL env context so `resolve` can build DSL values.
        fn complete(env: napi.Env, status: napi.status.Status, ctx: *Self) void {
            const prev = context.setEnv(env);
            defer context.restoreEnv(prev);

            defer {
                napi.status.check(napi.c.napi_delete_async_work(env.env, ctx.work)) catch {};
                ctx.task.deinit();
                context.allocator().destroy(ctx);
            }

            settle(env, status, ctx) catch {
                rejectAfterFailedSettle(env, ctx.deferred) catch {};
            };
        }

        fn settle(env: napi.Env, status: napi.status.Status, ctx: *Self) !void {
            if (status != .ok) {
                // libuv's async work itself failed (e.g. cancelled), not compute.
                return rejectWithMessage(env, ctx.deferred, @tagName(status));
            }
            if (ctx.err) |err| {
                if (comptime @hasDecl(Task, "reject")) {
                    return ctx.deferred.reject(try ctx.task.reject(env, err));
                }
                return rejectWithMessage(env, ctx.deferred, @errorName(err));
            }
            try ctx.deferred.resolve(try resolveValue(&ctx.task, env));
        }
    };

    const env = context.env();
    const allocator = context.allocator();

    const ctx = try allocator.create(Context);
    errdefer allocator.destroy(ctx);

    ctx.* = .{
        .task = task,
        .err = null,
        .deferred = undefined,
        .work = undefined,
    };

    const resource = try env.createStringUtf8(resource_name);
    const cleanup_value = try env.getUndefined();

    // Until queue succeeds, this function owns the unqueued work handle.
    const work = try env.createAsyncWork(
        Context,
        null,
        resource,
        Context.execute,
        Context.complete,
        ctx,
    );
    errdefer work.delete() catch |err| {
        std.log.err("zapi: failed to delete unqueued async work ({s}): {s}", .{ resource_name, @errorName(err) });
    };
    ctx.work = work.work;

    ctx.deferred = try env.createPromise();
    // Settle the unreturned Promise so Node can release its deferred handle.
    errdefer ctx.deferred.resolve(cleanup_value) catch |err| {
        std.log.err("zapi: failed to settle unreturned async promise ({s}): {s}", .{ resource_name, @errorName(err) });
    };

    try work.queue();

    return .{ .val = ctx.deferred.getPromise() };
}

/// Converts `Task.resolve`'s result, which may or may not be an error union.
fn resolveValue(task: anytype, env: napi.Env) !napi.Value {
    const result = @TypeOf(task.*).resolve(task, env);
    const value = if (comptime @typeInfo(@TypeOf(result)) == .error_union) try result else result;
    return toNapiValue(@TypeOf(value), value, env);
}

fn toNapiValue(comptime T: type, value: T, env: napi.Env) !napi.Value {
    if (T == napi.Value) return value;
    if (T == void) return env.getUndefined();
    if (comptime typed_arrays.isOwnedTypedArray(T)) {
        var owned = value;
        defer owned.deinit();
        return owned.intoValue(env);
    }
    if (comptime wrap_function.isDslType(T)) return value.val;
    @compileError("zapi: `resolve` cannot return " ++ @typeName(T) ++
        " — return a DSL type (e.g. `js.Number`), an owned typed array, `napi.Value`, or `void`");
}

/// A failed N-API call may leave a pending exception, which fails every later
/// call — including a fresh reject — and would strand the promise unsettled.
fn rejectAfterFailedSettle(env: napi.Env, deferred: napi.Deferred) !void {
    if (try env.isExceptionPending()) {
        return deferred.reject(try env.getAndClearLastException());
    }
    return rejectWithMessage(env, deferred, "InternalError");
}

/// Rejects with `new Error(message)` so JS can match on `err.message`.
fn rejectWithMessage(env: napi.Env, deferred: napi.Deferred, message: []const u8) !void {
    try deferred.reject(try js_error.errorWithMessage(env, message));
}

fn validateTask(comptime Task: type) void {
    if (@typeInfo(Task) != .@"struct") {
        @compileError("zapi: async task `" ++ @typeName(Task) ++ "` must be a struct");
    }
    for ([_][]const u8{ "compute", "resolve", "deinit" }) |decl| {
        if (!@hasDecl(Task, decl)) {
            @compileError("zapi: async task `" ++ @typeName(Task) ++
                "` is missing the required `" ++ decl ++ "` declaration");
        }
    }
}

test "validateTask accepts a well-formed task" {
    const Task = struct {
        pub fn compute(_: *@This()) !void {}
        pub fn resolve(_: *@This(), _: napi.Env) !void {}
        pub fn deinit(_: *@This()) void {}
    };
    comptime validateTask(Task);
    try std.testing.expect(@hasDecl(Task, "compute"));
}

test "spawn requires a JS callback context" {
    try std.testing.expect(@TypeOf(context.env) == fn () napi.Env);
}
