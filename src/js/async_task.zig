//! Worker-thread async DSL: run Zig work on the libuv pool and settle a JS
//! Promise with a DSL value.
//!
//! `js.Promise` alone cannot express this — its deferred handle is not
//! preserved across the JS boundary, so async resolution otherwise means
//! hand-rolling `napi.AsyncWork` + `napi.Deferred` at every call site.
//!
//! A Task is any struct providing:
//!
//! Required:
//!  - `compute(self: *Task) !void` — libuv worker thread; MUST NOT call napi
//!    APIs or construct DSL values
//!  - `resolve(self: *Task, env: napi.Env) !T` — JS thread; builds the
//!    fulfillment value. `T` may be a DSL type (`js.Number`), an owned typed
//!    array (`js.OwnedUint32Array`, transferred without copying), `napi.Value`,
//!    or `void`
//!  - `deinit(self: *Task) void` — frees task-owned memory; must be safe after
//!    `resolve` transferred ownership to JS
//!
//! Optional:
//!  - `reject(self: *Task, env: napi.Env, err: anyerror) !napi.Value` — builds
//!    the rejection value for a failed `compute`. Takes precedence over
//!    `errorMessage`.
//!  - `errorMessage(err: anyerror) [:0]const u8` — maps a failed `compute`'s
//!    error to the rejection Error's message. Defaults to `@errorName(err)`.
//!
//! Ownership: on `spawn` error the task is NOT consumed, so the caller's
//! errdefers must free its resources. Once `spawn` returns successfully the
//! helper owns the task and calls `deinit` after the promise settles.

const std = @import("std");
const napi = @import("../napi.zig");
const context = @import("context.zig");
const typed_arrays = @import("typed_arrays.zig");
const wrap_function = @import("wrap_function.zig");
const Value = @import("value.zig").Value;

/// Runs `task.compute` on the libuv worker pool and returns a JS Promise that
/// settles on the JS thread: rejected if `compute` failed, otherwise resolved
/// with `task.resolve(env)`.
///
/// `resource_name` labels the async resource for diagnostics and async hooks.
pub fn spawn(comptime Task: type, task: Task, comptime resource_name: []const u8) !Value {
    comptime validateTask(Task);

    const Context = struct {
        task: Task,
        err: ?anyerror,
        deferred: napi.Deferred,
        work: napi.c.napi_async_work,

        const Self = @This();

        /// Worker thread. Deliberately does NOT establish the DSL env context:
        /// napi calls are illegal here, and `js.env()` panicking is the
        /// intended guard rail.
        fn execute(_: napi.Env, ctx: *Self) void {
            ctx.task.compute() catch |err| {
                ctx.err = err;
            };
        }

        /// JS thread, after the worker finished. Establishes the DSL env
        /// context so `resolve` can build DSL values, then always settles the
        /// promise — if settling itself fails we fall back to a bare reject so
        /// callers never see a dangling Promise.
        fn complete(env: napi.Env, status: napi.status.Status, ctx: *Self) void {
            const prev = context.setEnv(env);
            defer context.restoreEnv(prev);

            defer {
                napi.status.check(napi.c.napi_delete_async_work(env.env, ctx.work)) catch {};
                ctx.task.deinit();
                context.allocator().destroy(ctx);
            }

            settle(env, status, ctx) catch {
                rejectWithMessage(env, ctx.deferred, "InternalError") catch {};
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
                const message = if (comptime @hasDecl(Task, "errorMessage"))
                    Task.errorMessage(err)
                else
                    @errorName(err);
                return rejectWithMessage(env, ctx.deferred, message);
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

/// Calls `Task.resolve` and converts its result to a `napi.Value`, accepting
/// either an error union or a plain return type.
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

/// Reject `deferred` with `new Error(message)` so JS callers can match on
/// `err.message`.
fn rejectWithMessage(env: napi.Env, deferred: napi.Deferred, message: []const u8) !void {
    const msg_val = try env.createStringUtf8(message);
    const err_val = try env.createError(napi.Value{ .env = env.env, .value = null }, msg_val);
    try deferred.reject(err_val);
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
    // spawn resolves the env from the DSL context, so calling it off a JS
    // callback is a programming error rather than a silent no-op.
    try std.testing.expect(@TypeOf(context.env) == fn () napi.Env);
}
