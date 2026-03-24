const js = @import("zapi").js;
const Number = js.Number;
const String = js.String;
const Boolean = js.Boolean;
const Array = js.Array;

pub fn add(a: Number, b: Number) Number {
    return Number.from(a.assertI32() + b.assertI32());
}

pub fn greet(name: String) !String {
    var buf: [256]u8 = undefined;
    const slice = try name.toSlice(&buf);
    var result: [512]u8 = undefined;
    const greeting = "Hello, ";
    @memcpy(result[0..greeting.len], greeting);
    @memcpy(result[greeting.len .. greeting.len + slice.len], slice);
    const total_len = greeting.len + slice.len;
    result[total_len] = '!';
    return String.from(result[0 .. total_len + 1]);
}

pub fn findValue(arr: Array, target: Number) ?Number {
    const len = arr.length() catch return null;
    const t = target.assertI32();
    var i: u32 = 0;
    while (i < len) : (i += 1) {
        const item = arr.getNumber(i) catch continue;
        if (item.assertI32() == t) return Number.from(i);
    }
    return null;
}

pub fn willThrow() !Number {
    return error.IntentionalError;
}

pub const Counter = struct {
    pub const js_class = true;
    count: i32,

    pub fn init(start: Number) Counter {
        return .{ .count = start.assertI32() };
    }

    pub fn increment(self: *Counter) void {
        self.count += 1;
    }

    pub fn getCount(self: Counter) Number {
        return Number.from(self.count);
    }

    pub fn isAbove(self: Counter, threshold: Number) Boolean {
        return Boolean.from(self.count > threshold.assertI32());
    }
};

comptime {
    js.exportModule(@This());
}
