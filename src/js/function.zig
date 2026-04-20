const napi = @import("../napi.zig");
const context = @import("context.zig");

pub const Function = struct {
    /// The underlying `napi.Value` representing the JavaScript function object.
    val: napi.Value,

    /// Validates if the given `napi.Value` is a JavaScript function.
    ///
    /// Returns an error (`error.TypeMismatch`) if the value is not a function,
    /// suitable for argument validation in DSL-wrapped functions.
    pub fn validateArg(val: napi.Value) !void {
        if ((try val.typeof()) != .function) return error.TypeMismatch;
    }

    /// Calls the JavaScript function with `undefined` as the receiver (`this`).
    ///
    /// The `args` parameter must be a tuple where each element is either a ZAPI
    /// DSL wrapper type (e.g., `js.Number`, `js.String`) or a raw `napi.Value`.
    /// This method extracts the underlying `napi.Value` from each argument before
    /// making the call.
    /// Returns a `js.Value` wrapper for the JavaScript function's return value.
    /// Returns an error if the function call fails or N-API operations encounter an issue.
    pub fn call(self: Function, args: anytype) !@import("value.zig").Value {
        const e = context.env();
        const recv = try e.getUndefined();
        const ArgsType = @TypeOf(args);
        const args_info = @typeInfo(ArgsType);

        if (args_info != .@"struct" or !args_info.@"struct".is_tuple) {
            @compileError("Function.call expects a tuple of arguments");
        }

        const fields = args_info.@"struct".fields;
        var raw_args: [fields.len]napi.c.napi_value = undefined;

        inline for (fields, 0..) |field, i| {
            const arg = @field(args, field.name);
            raw_args[i] = toRawValue(arg);
        }

        const result = try e.callFunctionRaw(self.val, recv, raw_args[0..]);
        return .{ .val = result };
    }

    /// Returns the underlying `napi.Value` representation of this JavaScript function.
    pub fn toValue(self: Function) napi.Value {
        return self.val;
    }
};

fn toRawValue(item: anytype) napi.c.napi_value {
    const T = @TypeOf(item);
    if (T == napi.Value) return item.value;
    if (@hasField(T, "val")) return item.val.value;
    @compileError("Expected a DSL wrapper type (with .val field) or napi.Value, got " ++ @typeName(T));
}
