const napi = @import("napi");

comptime {
    napi.module.register(exampleMod);

    // registerDecls(.{
    //     .add = .{
    //         .value = add,
    //         .type = .{
    //             .args = .{ .auto, .bigint },
    //             .returns = .buffer,
    //         },
    //     },
    //     .foo = .{
    //         .value = hello_world,
    //         .type = .string,
    //     },
    // });
}

fn exampleMod(env: napi.Env, module: napi.Value) anyerror!void {
    const v = try env.createStringUtf8(hello_world);

    try module.setNamedProperty("foo", v);
    try module.setNamedProperty("add", try env.createFunction(
        "add",
        2,
        void,
        napi.createCallback(void, add, .{}),
        null,
    ));
    try module.setNamedProperty("add_semimanual", try env.createFunction(
        "add_semimanual",
        2,
        void,
        napi.createCallback(void, add_semimanual, .{
            .args = .{ .env, .auto, .value },
            .returns = .value,
        }),
        null,
    ));
    try module.setNamedProperty("surprise", try env.createFunction(
        "surprise",
        0,
        void,
        napi.createCallback(void, surprise, .{
            .returns = .string,
        }),
        null,
    ));
    try module.setNamedProperty("update", try env.createFunction(
        "update",
        1,
        S,
        napi.createCallback(S, S.update, .{
            .args = .{ .data, .auto },
        }),
        &s,
    ));

    try module.setNamedProperty(
        "Timer",
        try env.defineClass(
            "Timer",
            0,
            void,
            Timer_ctor,
            null,
            &[_]napi.c.napi_property_descriptor{ .{
                .utf8name = "reset",
                .method = napi.wrapCallback(0, void, Timer_reset),
            }, .{
                .utf8name = "read",
                .method = napi.wrapCallback(0, void, Timer_read),
            }, .{
                .utf8name = "lap",
                .method = napi.wrapCallback(0, void, Timer_lap),
            } },
        ),
    );
}

/// Example function that shows Env, Value param and Value return type.
fn add_semimanual(env: napi.Env, a: i32, b: napi.Value) napi.Value {
    const b_int = b.getValueInt32() catch |err| {
        env.throwError(@errorName(err), "Failed to get value of b") catch {};
        return napi.Value.nullptr;
    };

    const result = a + b_int;
    return env.createInt32(result) catch |err| {
        env.throwError(@errorName(err), "Failed to create result value") catch {};
        return napi.Value.nullptr;
    };
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

const hello_world = "Hello, world!";

const std = @import("std");

comptime {
    std.debug.assert(@TypeOf(&add_manual) == napi.Callback(void));
}

fn add_manual(env: napi.Env, cb: napi.CallbackInfo(void)) napi.Value {
    const a = cb.arg(0).getValueBool() catch |err| {
        env.throwError(@errorName(err), "MsgB") catch {};
        return napi.Value.nullptr;
    };

    const b = cb.arg(1).getValueInt32() catch |err| {
        env.throwError(@errorName(err), "MsgC") catch {};
        return napi.Value.nullptr;
    };

    const result = @intFromBool(a) + b; // add(a, b);
    return env.createInt32(result) catch |err| {
        env.throwError(@errorName(err), "MsgD") catch {};
        return napi.Value.nullptr;
    };
}

fn add(a: i32, b: i32) !i32 {
    return a + b;
}

fn surprise() []const u8 {
    return "Surprise!";
}

const allocator = std.heap.page_allocator;

fn Timer_finalize(_: napi.Env, timer: *std.time.Timer, _: ?*void) void {
    std.debug.print("Destroying timer {any}\n", .{timer});
    allocator.destroy(timer);
}

fn Timer_ctor(env: napi.Env, cb: napi.CallbackInfo(void)) napi.Value {
    const timer = allocator.create(std.time.Timer) catch unreachable;
    timer.* = std.time.Timer.start() catch unreachable;
    _ = env.wrap(
        cb.this(),
        std.time.Timer,
        void,
        Timer_finalize,
        timer,
        null,
    ) catch unreachable;
    return cb.this();
}

fn Timer_reset(env: napi.Env, cb: napi.CallbackInfo(void)) napi.Value {
    const timer = env.unwrap(std.time.Timer, cb.this()) catch unreachable;
    timer.reset();
    return env.getUndefined() catch unreachable;
}

fn Timer_read(env: napi.Env, cb: napi.CallbackInfo(void)) napi.Value {
    const timer = env.unwrap(std.time.Timer, cb.this()) catch unreachable;
    return env.createInt64(@bitCast(timer.read())) catch unreachable;
}

fn Timer_lap(env: napi.Env, cb: napi.CallbackInfo(void)) napi.Value {
    const timer = env.unwrap(std.time.Timer, cb.this()) catch unreachable;
    return env.createInt64(@bitCast(timer.lap())) catch unreachable;
}
