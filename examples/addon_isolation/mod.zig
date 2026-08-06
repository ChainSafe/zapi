const js = @import("zapi").js;
const Number = js.Number;

/// Matches `example_js_dsl.Counter`'s layout so the regression fails safely
/// instead of reinterpreting incompatible native memory.
pub const Counter = struct {
    pub const js_meta = js.class(.{});
    count: i32,

    pub fn init(start: Number) Counter {
        return .{ .count = start.assertI32() };
    }

    pub fn getCount(self: Counter) Number {
        return Number.from(self.count);
    }
};

pub fn incrementCounter(counter: *Counter) void {
    counter.count += 1;
}

comptime {
    js.exportModule(@This(), .{
        .identity = @import("zapi_addon_identity"),
    });
}
