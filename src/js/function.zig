const napi = @import("../napi.zig");
const context = @import("context.zig");

pub const Function = struct {
    val: napi.Value,

    /// Calls the function with `undefined` as the receiver.
    /// `args` is a tuple where each element is either a DSL wrapper type
    /// (has `.val` field) or a raw `napi.Value`.
    pub fn call(self: Function, args: anytype) !napi.Value {
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

        return e.callFunctionRaw(self.val, recv, raw_args[0..]);
    }

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
