const napi = @import("../napi.zig");
const context = @import("context.zig");
const Number = @import("number.zig").Number;
const String = @import("string.zig").String;
const Boolean = @import("boolean.zig").Boolean;

pub const Array = struct {
    /// The underlying `napi.Value` representing the JavaScript Array object.
    val: napi.Value,

    /// Validates if the given `napi.Value` is a JavaScript Array.
    ///
    /// Returns an error (`error.TypeMismatch`) if the value is not an array,
    /// suitable for argument validation in DSL-wrapped functions.
    pub fn validateArg(val: napi.Value) !void {
        if (!(try val.isArray())) return error.TypeMismatch;
    }

    /// Returns the element at `index` as an untyped `js.Value` wrapper.
    ///
    /// This method fetches an element from the JavaScript array and wraps it
    /// as a generic `js.Value`, allowing for runtime type checking and narrowing.
    /// Returns an error if the index is out of bounds or N-API operations fail.
    pub fn get(self: Array, index: u32) !@import("value.zig").Value {
        const element = try self.val.getElement(index);
        return .{ .val = element };
    }

    /// Returns the element at `index` narrowed to a `js.Number`.
    ///
    /// Returns `error.TypeMismatch` if the element at `index` is not a JavaScript
    /// number. Returns an error if the index is out of bounds or N-API operations fail.
    pub fn getNumber(self: Array, index: u32) !Number {
        const element = try self.val.getElement(index);
        if ((try element.typeof()) != .number) return error.TypeMismatch;
        return .{ .val = element };
    }

    /// Returns the element at `index` narrowed to a `js.String`.
    ///
    /// Returns `error.TypeMismatch` if the element at `index` is not a JavaScript
    /// string. Returns an error if the index is out of bounds or N-API operations fail.
    pub fn getString(self: Array, index: u32) !String {
        const element = try self.val.getElement(index);
        if ((try element.typeof()) != .string) return error.TypeMismatch;
        return .{ .val = element };
    }

    /// Returns the element at `index` narrowed to a `js.Boolean`.
    ///
    /// Returns `error.TypeMismatch` if the element at `index` is not a JavaScript
    /// boolean. Returns an error if the index is out of bounds or N-API operations fail.
    pub fn getBoolean(self: Array, index: u32) !Boolean {
        const element = try self.val.getElement(index);
        if ((try element.typeof()) != .boolean) return error.TypeMismatch;
        return .{ .val = element };
    }

    /// Returns the length of the JavaScript array.
    ///
    /// Returns an error if N-API operations fail.
    pub fn length(self: Array) !u32 {
        return self.val.getArrayLength();
    }

    /// Sets the element at `index` in the JavaScript array.
    ///
    /// This method accepts any ZAPI DSL wrapper type (e.g., `js.Number`, `js.String`)
    /// or a raw `napi.Value`. It extracts the underlying `napi.Value` and performs
    /// the assignment. Returns an error if the index is out of bounds or N-API
    /// operations fail.
    pub fn set(self: Array, index: u32, item: anytype) !void {
        const raw = toNapiValue(item);
        try self.val.setElement(index, raw);
    }

    /// Creates a new empty JavaScript array.
    ///
    /// Panics if N-API operations fail (e.g., invalid environment).
    pub fn create() Array {
        const e = context.env();
        const val = e.createArray() catch @panic("Array.create failed");
        return .{ .val = val };
    }

    /// Creates a new JavaScript array with a pre-allocated length.
    ///
    /// This can be more efficient for arrays where the final size is known in
    /// advance. The elements will be `undefined` initially. Panics if N-API
    /// operations fail (e.g., invalid environment).
    pub fn createWithLength(len: usize) Array {
        const e = context.env();
        const val = e.createArrayWithLength(len) catch @panic("Array.createWithLength failed");
        return .{ .val = val };
    }

    /// Returns the underlying `napi.Value` representation of this JavaScript Array.
    pub fn toValue(self: Array) napi.Value {
        return self.val;
    }
};

/// Internal helper to extract the raw `napi.Value` from a ZAPI DSL wrapper type
/// or pass through an already raw `napi.Value`.
///
/// This function is used by DSL `set` methods to handle arguments that can be
/// either DSL wrappers (like `js.Number`) or direct N-API values.
/// Compile-time error if the `item` does not have a `.val` field (for DSL wrappers)
/// or is not a `napi.Value`.
fn toNapiValue(item: anytype) napi.Value {
    const T = @TypeOf(item);
    if (T == napi.Value) return item;
    if (@hasField(T, "val")) return item.val;
    @compileError("Expected a DSL wrapper type (with .val field) or napi.Value, got " ++ @typeName(T));
}
