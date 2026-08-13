const js = @import("zapi").js;

pub fn double(value: js.Number) js.Number {
    return js.Number.from(value.assertI32() * 2);
}

comptime {
    js.exportModule(@This(), .{});
}
