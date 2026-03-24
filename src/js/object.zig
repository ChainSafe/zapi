const napi = @import("../napi.zig");

/// A generic Object wrapper that maps a Zig struct `T` to a JS object.
/// Each field of `T` must be a DSL wrapper type (i.e., a struct with a `.val: napi.Value` field).
pub fn Object(comptime T: type) type {
    const fields = @typeInfo(T).@"struct".fields;

    return struct {
        val: napi.Value,

        const Self = @This();

        /// Reads all properties from the JS object into a Zig struct.
        pub fn get(self: Self) !T {
            var result: T = undefined;
            inline for (fields) |field| {
                const name: [:0]const u8 = field.name ++ "";
                const prop = try self.val.getNamedProperty(name);
                @field(result, field.name) = .{ .val = prop };
            }
            return result;
        }

        /// Writes all fields of the Zig struct onto the JS object.
        pub fn set(self: Self, value: T) !void {
            inline for (fields) |field| {
                const name: [:0]const u8 = field.name ++ "";
                const field_val = @field(value, field.name);
                try self.val.setNamedProperty(name, field_val.val);
            }
        }

        pub fn toValue(self: Self) napi.Value {
            return self.val;
        }
    };
}
