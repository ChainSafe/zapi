const std = @import("std");
const c = @import("c.zig").c;

version: c.napi_node_version,

const NodeVersion = @This();

pub fn getRelease(self: NodeVersion) [*:0]const u8 {
    return @ptrCast(self.version.release);
}

pub fn toSemanticVersion(self: NodeVersion) std.SemanticVersion {
    return std.SemanticVersion{
        .major = self.version.major,
        .minor = self.version.minor,
        .patch = self.version.patch,
    };
}
