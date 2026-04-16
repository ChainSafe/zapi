const napi = @import("../napi.zig");

/// A generic Object wrapper that maps a Zig struct `T` to a JS object.
///
/// This function returns a new Zig type, `js.Object(T)`, specialized for a given
/// Zig struct `T`. This `js.Object(T)` type serves as a zero-cost wrapper
/// around a JavaScript object. It allows you to:
/// - Validate if a given `napi.Value` is a JS object.
/// - Read all properties from the JS object into a Zig struct `T`.
/// - Write all fields of a Zig struct `T` onto the JS object.
///
/// Each field of the Zig struct `T` must itself be a ZAPI DSL wrapper type
/// (i.e., a struct with a `.val: napi.Value` field) because the `get` and `set`
/// methods perform conversions based on these wrapper types.
pub fn Object(comptime T: type) type {
    const fields = @typeInfo(T).@"struct".fields;

    return struct {
        /// The underlying `napi.Value` representing the JavaScript object.
        val: napi.Value,

        const Self = @This();

        /// Validates if the given `napi.Value` is a JavaScript object.
        ///
        /// Returns an error (`error.TypeMismatch`) if the value is not an object.
        /// This is suitable for argument validation in DSL-wrapped functions
        /// where a `js.Object(T)` type is expected.
        pub fn validateArg(val: napi.Value) !void {
            if ((try val.typeof()) != .object) return error.TypeMismatch;
        }

        /// Reads all properties from the underlying JavaScript object into a new
        /// instance of the Zig struct `T`.
        ///
        /// This method iterates through the fields of `T` at compile time,
        /// retrieves the corresponding named properties from the JavaScript object,
        /// and converts them into the appropriate ZAPI DSL wrapper types for the
        /// fields of the Zig struct.
        /// Returns an error if any property cannot be retrieved or converted.
        pub fn get(self: Self) !T {
            var result: T = undefined;
            inline for (fields) |field| {
                const name: [:0]const u8 = field.name ++ "";
                const prop = try self.val.getNamedProperty(name);
                @field(result, field.name) = .{ .val = prop };
            }
            return result;
        }

        /// Writes all fields from a Zig struct `T` onto the underlying JavaScript
        /// object as named properties.
        ///
        /// This method iterates through the fields of `T` at compile time,
        /// extracts the underlying `napi.Value` from each ZAPI DSL wrapper field,
        /// and sets it as a named property on the JavaScript object.
        /// Returns an error if any property cannot be set.
        pub fn set(self: Self, value: T) !void {
            inline for (fields) |field| {
                const name: [:0]const u8 = field.name ++ "";
                const field_val = @field(value, field.name);
                try self.val.setNamedProperty(name, field_val.val);
            }
        }

        /// Returns the underlying `napi.Value` representation of this JavaScript object.
        pub fn toValue(self: Self) napi.Value {
            return self.val;
        }
    };
}
