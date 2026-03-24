const context = @import("js/context.zig");

pub const env = context.env;
pub const allocator = context.allocator;
pub const setEnv = context.setEnv;
pub const restoreEnv = context.restoreEnv;

pub const Number = @import("js/number.zig").Number;
pub const String = @import("js/string.zig").String;
pub const Boolean = @import("js/boolean.zig").Boolean;
pub const BigInt = @import("js/bigint.zig").BigInt;
pub const Date = @import("js/date.zig").Date;

// Complex types, Promise, exportModule — added in later chunks

test {
    @import("std").testing.refAllDecls(@This());
}
