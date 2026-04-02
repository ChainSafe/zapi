const napi = @import("../napi.zig");
const context = @import("context.zig");

pub const Date = struct {
    val: napi.Value,

    /// Returns the timestamp (milliseconds since Unix epoch) as f64.
    pub fn toTimestamp(self: Date) !f64 {
        return self.val.getDateValue();
    }

    pub fn assertTimestamp(self: Date) f64 {
        return self.toTimestamp() catch @panic("Date.assertTimestamp failed");
    }

    /// Creates a JS Date from a timestamp (milliseconds since Unix epoch).
    pub fn from(time: f64) Date {
        const e = context.env();
        const val = e.createDate(time) catch @panic("Date.from failed");
        return .{ .val = val };
    }

    pub fn toValue(self: Date) napi.Value {
        return self.val;
    }
};
