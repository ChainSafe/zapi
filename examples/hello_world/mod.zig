///! This is an example napi module that exercises various napi features.
const std = @import("std");
const napi = @import("napi");
const allocator = std.heap.page_allocator;

comptime {
    // The module must be registered with napi via `register`
    napi.module.register(exampleMod);
}

// This is the top-level module registration function for this module.
// It is called by napi when the module is loaded.
fn exampleMod(env: napi.Env, module: napi.Value) anyerror!void {
    // Example of a string property
    try module.setNamedProperty("helloWorld", try env.createStringUtf8(hello_world));

    // Example of a function.
    // Note: check the function signature of createFunction for more details.
    try module.setNamedProperty("add_manual", try env.createFunction(
        "add_manual",
        2,
        add_manual,
        null,
    ));

    // Example of a function, using the napi.createCallback helper to create a callback
    // Note: napi.createCallback is a convenience wrapper that is _not_ a core part of napi,
    // rather it is more of a "framework" for creating callbacks.
    try module.setNamedProperty("add", try env.createFunction(
        "add",
        2,
        napi.createCallback(2, add, .{}),
        null,
    ));

    // Example of a function, using the napi.createCallback helper to create a callback
    // with a custom options.
    // Note: this is named add_semimanual, since it uses the convenience wrapper but the
    // implementation still uses the napi.Env and napi.Value manually.
    try module.setNamedProperty("add_semimanual", try env.createFunction(
        "add_semimanual",
        2,
        napi.createCallback(2, add_semimanual, .{
            .args = .{ .env, .auto, .value },
            .returns = .value,
        }),
        null,
    ));

    // Example of a function that returns a string
    try module.setNamedProperty("surprise", try env.createFunction(
        "surprise",
        0,
        napi.createCallback(0, surprise, .{
            .returns = .string,
        }),
        null,
    ));

    try module.setNamedProperty("update", try env.createFunction(
        "update",
        1,
        napi.createCallback(1, S.update, .{
            .args = .{ .data, .auto },
        }),
        &s,
    ));

    // Example of a class
    try module.setNamedProperty(
        "Timer",
        try env.defineClass(
            "Timer",
            0,
            Timer_ctor,
            null,
            &[_]napi.c.napi_property_descriptor{ .{
                .utf8name = "reset",
                .method = napi.wrapCallback(0, Timer_reset),
            }, .{
                .utf8name = "read",
                .method = napi.wrapCallback(0, Timer_read),
            }, .{
                .utf8name = "lap",
                .method = napi.wrapCallback(0, Timer_lap),
            } },
        ),
    );

    // Example of using async work + promise
    try module.setNamedProperty("asyncAdd", try env.createFunction(
        "asyncAdd",
        2,
        asyncAdd,
        null,
    ));

    // Example of using threadsafe function
    try module.setNamedProperty("startThread", try env.createFunction(
        "startThread",
        1,
        startThread,
        null,
    ));
}

const hello_world = "Hello, world!";

comptime {
    // std.debug.assert(@TypeOf(&add_manual) == napi.Callback(2));
}

fn add_manual(env: napi.Env, cb: napi.CallbackInfo(2)) !napi.Value {
    const a = try cb.arg(0).getValueInt32();
    const b = try cb.arg(1).getValueInt32();

    return try env.createInt32(a + b);
}

// Functions that use the napi.createCallback helper to be transformed to napi.Callback

fn add(a: i32, b: i32) !i32 {
    return a + b;
}

fn add_semimanual(env: napi.Env, a: i32, b: napi.Value) !napi.Value {
    const b_int = try b.getValueInt32();

    const result = a + b_int;
    return try env.createInt32(result);
}

fn surprise() []const u8 {
    return "Surprise!";
}

const S = struct {
    a: i32,
    b: i32,

    pub fn update(self: *S, z: i32) i32 {
        self.a += z;
        self.b += z;

        return self.a + self.b;
    }
};

var s: S = S{
    .a = 1,
    .b = 2,
};

// Wrapped class example (std.time.Timer)

fn Timer_finalize(_: napi.Env, timer: *std.time.Timer, _: ?*anyopaque) void {
    std.debug.print("Destroying timer {any}\n", .{timer});
    allocator.destroy(timer);
}

fn Timer_ctor(env: napi.Env, cb: napi.CallbackInfo(0)) !napi.Value {
    const timer = try allocator.create(std.time.Timer);
    timer.* = try std.time.Timer.start();
    _ = try env.wrap(
        cb.this(),
        std.time.Timer,
        timer,
        Timer_finalize,
        null,
    );
    return cb.this();
}

fn Timer_reset(env: napi.Env, cb: napi.CallbackInfo(0)) !napi.Value {
    const timer = try env.unwrap(std.time.Timer, cb.this());
    timer.reset();
    return try env.getUndefined();
}

fn Timer_read(env: napi.Env, cb: napi.CallbackInfo(0)) !napi.Value {
    const timer = try env.unwrap(std.time.Timer, cb.this());
    return try env.createInt64(@intCast(timer.read()));
}

fn Timer_lap(env: napi.Env, cb: napi.CallbackInfo(0)) !napi.Value {
    const timer = try env.unwrap(std.time.Timer, cb.this());
    return try env.createInt64(@intCast(timer.lap()));
}

// Async work example

const AsyncAddData = struct {
    a: i32,
    b: i32,
    result: i32,
    deferred: napi.Deferred,
    work: napi.AsyncWork(AsyncAddData),
};

fn asyncAddExecute(_: napi.Env, data: *AsyncAddData) void {
    std.time.sleep(1_000_000_000); // 1 second
    data.result = data.a + data.b;
}

fn asyncAddComplete(env: napi.Env, status: napi.status.Status, data: *AsyncAddData) void {
    defer {
        data.work.delete() catch undefined;
        allocator.destroy(data);
    }

    if (status != .ok) {
        data.deferred.reject(env.createError(
            env.createStringUtf8(@tagName(status)) catch unreachable,
            env.createStringUtf8(@tagName(status)) catch unreachable,
        ) catch unreachable) catch unreachable;
        return;
    }

    data.deferred.resolve(env.createInt32(data.result) catch unreachable) catch unreachable;
}

fn asyncAdd(env: napi.Env, cb: napi.CallbackInfo(2)) !napi.Value {
    const a = try cb.arg(0).getValueInt32();
    const b = try cb.arg(1).getValueInt32();

    const data = try allocator.create(AsyncAddData);
    data.* = AsyncAddData{
        .a = a,
        .b = b,
        .result = 0,
        .deferred = try env.createPromise(),
        .work = undefined,
    };
    const work = try env.createAsyncWork(
        AsyncAddData,
        null,
        try env.createStringUtf8("asyncAdd"),
        asyncAddExecute,
        asyncAddComplete,
        data,
    );
    data.work = work;
    try work.queue();

    return data.deferred.getPromise();
}

// Threadsafe function example

const TsfnContext = struct {
    thread: std.Thread,
};

const TsfnData = struct {
    count: i32,
};

fn startThread(env: napi.Env, cb: napi.CallbackInfo(1)) !napi.Value {
    const context = try allocator.create(TsfnContext);

    // Create the thread-safe function
    const tsfn = try env.createThreadSafeFunction(
        TsfnContext,
        TsfnData,
        cb.arg(0),
        null,
        try env.createStringUtf8("TsfnResource"),
        0,
        1,
        context,
        finalizeTsfn,
        callJs,
    );

    // Start a thread
    context.thread = try std.Thread.spawn(.{}, threadMain, .{tsfn});

    return try env.getUndefined();
}

fn threadMain(tsfn: napi.ThreadSafeFunction(TsfnContext, TsfnData)) void {
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        const data = allocator.create(TsfnData) catch return;
        data.count = i;

        // Call into JS
        tsfn.call(data, .blocking) catch {};

        std.time.sleep(100 * std.time.ns_per_ms);
    }

    // Release the thread-safe function
    tsfn.release(.release) catch {};
}

fn callJs(env: napi.Env, cb: napi.Value, _: *TsfnContext, data: *TsfnData) void {
    defer allocator.destroy(data);

    _ = env.callFunction(
        cb,
        cb,
        .{env.createInt32(data.count) catch unreachable},
    ) catch {};
}

fn finalizeTsfn(_: napi.Env, context: *TsfnContext) void {
    defer {
        context.thread.join();
        allocator.destroy(context);
    }

    std.debug.print("TSFN Finalized\n", .{});
}
