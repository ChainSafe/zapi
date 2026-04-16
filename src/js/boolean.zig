const napi = @import("../napi.zig");
const context = @import("context.zig");

pub const Boolean = struct {
    /// The underlying `napi.Value` representing the JavaScript boolean.
    val: napi.Value,

    /// Validates if the given `napi.Value` is a JavaScript boolean.
    ///
    /// Returns an error if the value is not a boolean, suitable for argument
    /// validation in DSL-wrapped functions.
    pub fn validateArg(val: napi.Value) !void {
        if ((try val.typeof()) != .boolean) return error.TypeMismatch;
    }

    /// Attempts to convert the JavaScript boolean to a Zig `bool`.
    pub fn toBool(self: Boolean) !bool {
        return self.val.getValueBool();
    }

    /// Converts the JavaScript boolean to a Zig `bool`, panicking on failure.
    ///
    /// This is a convenience method for cases where the boolean is guaranteed.
    pub fn assertBool(self: Boolean) bool {
        return self.toBool() catch @panic("Boolean.assertBool failed");
    }

    /// Creates a JavaScript `Boolean` from a Zig `bool` value.
    ///
    /// Panics if N-API operations fail (e.g., invalid environment).
    pub fn from(value: bool) Boolean {
        const e = context.env();
        const val = e.getBoolean(value) catch @panic("Boolean.from failed");
        return .{ .val = val };
    }

    /// Returns the underlying `napi.Value` representation of this JavaScript boolean.
    pub fn toValue(self: Boolean) napi.Value {
        return self.val;
    }
};
