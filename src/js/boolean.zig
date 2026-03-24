const napi = @import("../napi.zig");
const context = @import("context.zig");

pub const Boolean = struct {
    val: napi.Value,

    pub fn toBool(self: Boolean) !bool {
        return self.val.getValueBool();
    }

    pub fn assertBool(self: Boolean) bool {
        return self.toBool() catch @panic("Boolean.assertBool failed");
    }

    pub fn from(value: bool) Boolean {
        const e = context.env();
        const val = e.getBoolean(value) catch @panic("Boolean.from failed");
        return .{ .val = val };
    }

    pub fn toValue(self: Boolean) napi.Value {
        return self.val;
    }
};
