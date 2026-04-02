const napi = @import("../napi.zig");
const context = @import("context.zig");
const TypedarrayType = napi.value_types.TypedarrayType;

/// Generates a typed array wrapper for a specific element type and NAPI array type.
pub fn TypedArray(comptime Element: type, comptime array_type: TypedarrayType) type {
    return struct {
        val: napi.Value,

        const Self = @This();

        /// Returns a slice pointing directly into the V8 ArrayBuffer backing store.
        ///
        /// WARNING: This slice is only valid within the current N-API callback scope.
        /// The backing store may be moved or freed by the GC after the callback returns
        /// or after any JS call that could trigger GC. Do NOT store this slice across
        /// callbacks, async work boundaries, or JS function calls. For data that must
        /// outlive the callback, copy the slice contents to a heap allocation.
        pub fn toSlice(self: Self) ![]Element {
            const info = try self.val.getTypedarrayInfo();
            const byte_ptr: [*]u8 = info.data.ptr;
            const typed_ptr: [*]Element = @ptrCast(@alignCast(byte_ptr));
            return typed_ptr[0..info.length];
        }

        /// Creates a new JS TypedArray from a Zig slice by copying the data.
        pub fn from(slice: []const Element) Self {
            const e = context.env();
            const byte_len = slice.len * @sizeOf(Element);
            var buf_ptr: [*]u8 = undefined;
            const arraybuffer = e.createArrayBuffer(byte_len, &buf_ptr) catch
                @panic("TypedArray.from: createArrayBuffer failed");
            const dest: [*]Element = @ptrCast(@alignCast(buf_ptr));
            @memcpy(dest[0..slice.len], slice);
            const val = e.createTypedarray(array_type, slice.len, arraybuffer, 0) catch
                @panic("TypedArray.from: createTypedarray failed");
            return .{ .val = val };
        }

        pub fn toValue(self: Self) napi.Value {
            return self.val;
        }
    };
}

// Concrete typed array types
pub const Int8Array = TypedArray(i8, .int8);
pub const Uint8Array = TypedArray(u8, .uint8);
pub const Uint8ClampedArray = TypedArray(u8, .uint8_clamped);
pub const Int16Array = TypedArray(i16, .int16);
pub const Uint16Array = TypedArray(u16, .uint16);
pub const Int32Array = TypedArray(i32, .int32);
pub const Uint32Array = TypedArray(u32, .uint32);
pub const Float32Array = TypedArray(f32, .float32);
pub const Float64Array = TypedArray(f64, .float64);
pub const BigInt64Array = TypedArray(i64, .bigint64);
pub const BigUint64Array = TypedArray(u64, .biguint64);
