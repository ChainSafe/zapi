const napi = @import("../napi.zig");
const context = @import("context.zig");
const Number = @import("number.zig").Number;
const String = @import("string.zig").String;
const Boolean = @import("boolean.zig").Boolean;

pub const Array = struct {
    val: napi.Value,

    pub fn validateArg(val: napi.Value) !void {
        if (!(try val.isArray())) return error.TypeMismatch;
    }

    /// Returns the element at `index` as an untyped Value.
    pub fn get(self: Array, index: u32) !@import("value.zig").Value {
        const element = try self.val.getElement(index);
        return .{ .val = element };
    }

    /// Returns the element at `index` narrowed to a Number.
    /// Returns error.TypeMismatch if the element is not a number.
    pub fn getNumber(self: Array, index: u32) !Number {
        const element = try self.val.getElement(index);
        if ((try element.typeof()) != .number) return error.TypeMismatch;
        return .{ .val = element };
    }

    /// Returns the element at `index` narrowed to a String.
    /// Returns error.TypeMismatch if the element is not a string.
    pub fn getString(self: Array, index: u32) !String {
        const element = try self.val.getElement(index);
        if ((try element.typeof()) != .string) return error.TypeMismatch;
        return .{ .val = element };
    }

    /// Returns the element at `index` narrowed to a Boolean.
    /// Returns error.TypeMismatch if the element is not a boolean.
    pub fn getBoolean(self: Array, index: u32) !Boolean {
        const element = try self.val.getElement(index);
        if ((try element.typeof()) != .boolean) return error.TypeMismatch;
        return .{ .val = element };
    }

    /// Returns the length of the array.
    pub fn length(self: Array) !u32 {
        return self.val.getArrayLength();
    }

    /// Sets the element at `index`. Accepts any DSL wrapper type (anything with
    /// a `.val` field of type `napi.Value`) or a raw `napi.Value`.
    pub fn set(self: Array, index: u32, item: anytype) !void {
        const raw = toNapiValue(item);
        try self.val.setElement(index, raw);
    }

    /// Creates a new empty JS array.
    pub fn create() Array {
        const e = context.env();
        const val = e.createArray() catch @panic("Array.create failed");
        return .{ .val = val };
    }

    /// Creates a new JS array with a pre-allocated length.
    pub fn createWithLength(len: usize) Array {
        const e = context.env();
        const val = e.createArrayWithLength(len) catch @panic("Array.createWithLength failed");
        return .{ .val = val };
    }

    pub fn toValue(self: Array) napi.Value {
        return self.val;
    }
};

/// Extracts the underlying `napi.Value` from a DSL wrapper (has `.val` field)
/// or passes through a raw `napi.Value`.
fn toNapiValue(item: anytype) napi.Value {
    const T = @TypeOf(item);
    if (T == napi.Value) return item;
    if (@hasField(T, "val")) return item.val;
    @compileError("Expected a DSL wrapper type (with .val field) or napi.Value, got " ++ @typeName(T));
}
