const napi = @import("../napi.zig");
const context = @import("context.zig");

pub const Date = struct {
    /// The underlying `napi.Value` representing the JavaScript Date object.
    val: napi.Value,

    /// Validates if the given `napi.Value` is a JavaScript Date object.
    ///
    /// Returns an error (`error.TypeMismatch`) if the value is not a Date,
    /// suitable for argument validation in DSL-wrapped functions.
    pub fn validateArg(val: napi.Value) !void {
        if (!(try val.isDate())) return error.TypeMismatch;
    }

    /// Attempts to convert the JavaScript Date object's internal timestamp to a Zig `f64`.
    ///
    /// The timestamp represents milliseconds since the Unix epoch. Returns an
    /// error if N-API operations fail.
    pub fn toTimestamp(self: Date) !f64 {
        return self.val.getDateValue();
    }

    /// Converts the JavaScript Date object's timestamp to a Zig `f64`, panicking on failure.
    ///
    /// This is a convenience method for cases where the conversion is guaranteed.
    pub fn assertTimestamp(self: Date) f64 {
        return self.toTimestamp() catch @panic("Date.assertTimestamp failed");
    }

    /// Creates a JavaScript `Date` object from a timestamp (milliseconds since Unix epoch).
    ///
    /// Panics if N-API operations fail (e.g., invalid environment).
    pub fn from(time: f64) Date {
        const e = context.env();
        const val = e.createDate(time) catch @panic("Date.from failed");
        return .{ .val = val };
    }

    /// Returns the underlying `napi.Value` representation of this JavaScript Date object.
    pub fn toValue(self: Date) napi.Value {
        return self.val;
    }
};
