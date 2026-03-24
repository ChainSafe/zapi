const std = @import("std");
const napi = @import("../napi.zig");
const context = @import("context.zig");

pub const String = struct {
    val: napi.Value,

    /// Copies the string value into the provided buffer.
    /// Returns a slice of the buffer containing the string data.
    pub fn toSlice(self: String, buf: []u8) ![]const u8 {
        return self.val.getValueStringUtf8(buf);
    }

    /// Allocates a new slice and copies the string value into it.
    /// Caller owns the returned memory and must free it with the same allocator.
    pub fn toOwnedSlice(self: String, alloc: std.mem.Allocator) ![]const u8 {
        const str_len = try self.len();
        const buf = try alloc.alloc(u8, str_len);
        errdefer alloc.free(buf);
        const tmp = try alloc.alloc(u8, str_len + 1);
        defer alloc.free(tmp);
        const result = try self.val.getValueStringUtf8(tmp);
        @memcpy(buf, result[0..str_len]);
        return buf;
    }

    /// Returns the length of the string in bytes (UTF-8).
    pub fn len(self: String) !usize {
        var str_len: usize = 0;
        const status_code = napi.c.napi_get_value_string_utf8(
            self.val.env,
            self.val.value,
            null,
            0,
            &str_len,
        );
        try napi.status.check(status_code);
        return str_len;
    }

    /// Creates a JS String from a Zig string slice.
    pub fn from(value: []const u8) String {
        const e = context.env();
        const val = e.createStringUtf8(value) catch @panic("String.from failed");
        return .{ .val = val };
    }

    pub fn toValue(self: String) napi.Value {
        return self.val;
    }
};
