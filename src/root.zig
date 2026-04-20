const std = @import("std");

pub const napi = @import("napi.zig");
pub const js = @import("js.zig");

// Backwards-compatible flat exports: all existing napi symbols
// remain accessible at the top level.
pub usingnamespace @import("napi.zig");

test {
    std.testing.refAllDecls(@This());
}
