const zapi = @import("zapi");

const greeting: []const u8 = "hello";

comptime {
    zapi.registerDecls(.{
        .add = .{ .value = add },
        .greeting = .{ .value = greeting },
    }, .{});
}

fn add(a: i32, b: i32) i32 {
    return a + b;
}
