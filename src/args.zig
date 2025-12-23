const std = @import("std");
const c = @import("c.zig");
const Value = @import("Value.zig");

pub fn tupleToRaw(args: anytype) [@typeInfo(@TypeOf(args)).@"struct".fields.len]c.napi_value {
    const ArgsT = @TypeOf(args);
    const info = @typeInfo(ArgsT);

    if (info != .@"struct" or !info.@"struct".is_tuple) {
        @compileError("args must be a tuple of napi.Value");
    }

    const len = info.@"struct".fields.len;
    var argv: [len]c.napi_value = undefined;

    inline for (info.@"struct".fields, 0..) |field, i| {
        const arg = @field(args, field.name);
        if (@TypeOf(arg) != Value) {
            @compileError("Only napi.Value is supported in arguments tuple");
        }
        argv[i] = arg.value;
    }

    return argv;
}
