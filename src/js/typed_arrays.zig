const napi = @import("../napi.zig");
const context = @import("context.zig");
const TypedarrayType = napi.value_types.TypedarrayType;

/// Generates a typed array wrapper for a specific element type and NAPI array type.
///
/// This comptime function returns a new Zig type, `js.TypedArray(Element, array_type)`,
/// specialized for a given native element type (`Element`) and a specific N-API
/// TypedArray kind (`array_type`). It provides a zero-cost wrapper around a
/// JavaScript TypedArray.
///
/// Consumers should generally use the concrete aliases provided (e.g., `js.Uint8Array`)
/// rather than instantiating this factory directly.
pub fn TypedArray(comptime Element: type, comptime array_type: TypedarrayType) type {
    return struct {
        /// The underlying `napi.Value` representing the JavaScript TypedArray.
        val: napi.Value,

        const Self = @This();
        /// The N-API TypedArray type that this wrapper expects, e.g., `.uint8`.
        pub const expected_array_type = array_type;

        /// Validates if the given `napi.Value` is a JavaScript TypedArray of the
        /// expected type.
        ///
        /// Returns an error (`error.TypeMismatch`) if the value is not a TypedArray
        /// or if its type does not match `expected_array_type`. Suitable for
        /// argument validation in DSL-wrapped functions.
        pub fn validateArg(val: napi.Value) !void {
            if (!(try val.isTypedarray())) return error.TypeMismatch;
            const info = try val.getTypedarrayInfo();
            if (info.array_type != array_type) return error.TypeMismatch;
        }

        /// Returns a slice pointing directly into the V8 ArrayBuffer backing store.
        ///
        /// WARNING: This slice is only valid within the current N-API callback scope.
        /// The backing store may be moved or freed by the GC after the callback returns
        /// or after any JS call that could trigger GC. Do NOT store this slice across
        /// callbacks, async work boundaries, or JS function calls. For data that must
        /// outlive the callback, copy the slice contents to a heap allocation. Returns
        /// `error.TypeMismatch` if the underlying TypedArray is not of the expected type.
        pub fn toSlice(self: Self) ![]Element {
            const info = try self.val.getTypedarrayInfo();
            if (info.array_type != array_type) return error.TypeMismatch;
            const byte_ptr: [*]u8 = info.data.ptr;
            const typed_ptr: [*]Element = @ptrCast(@alignCast(byte_ptr));
            return typed_ptr[0..info.length];
        }

        /// Creates a new JavaScript TypedArray from a Zig slice by copying the data.
        ///
        /// This function allocates a new `ArrayBuffer` in V8, copies the contents
        /// of the provided Zig `slice` into it, and then creates a TypedArray view
        /// over this buffer. Panics if N-API operations fail (e.g., invalid environment)
        /// or memory allocation fails.
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

        /// Allocates a new JavaScript TypedArray of the given length backed by
        /// freshly allocated V8 memory. The contents are uninitialized.
        ///
        /// Use `toSlice()` on the returned value to get a writable slice into
        /// the V8 ArrayBuffer backing store, then fill it before returning to JS.
        ///
        /// This is the zero-copy construction path for when the size is known
        /// upfront and the producer can write directly into a target buffer
        /// (e.g. serialization). For cases where data already exists in a Zig
        /// slice, use `from(slice)` instead.
        ///
        /// WARNING: The same lifetime caveats as `toSlice()` apply — the backing
        /// store is only valid within the current N-API callback scope.
        pub fn alloc(len: usize) !Self {
            const e = context.env();
            const byte_len = len * @sizeOf(Element);
            var buf_ptr: [*]u8 = undefined;
            const arraybuffer = try e.createArrayBuffer(byte_len, &buf_ptr);
            const val = try e.createTypedarray(array_type, len, arraybuffer, 0);
            return .{ .val = val };
        }

        /// Returns the underlying `napi.Value` representation of this JavaScript TypedArray.
        pub fn toValue(self: Self) napi.Value {
            return self.val;
        }
    };
}

// Concrete typed array types
/// Wrapper around JavaScript `Int8Array`.
pub const Int8Array = TypedArray(i8, .int8);

/// Wrapper around JavaScript `Uint8Array`.
pub const Uint8Array = TypedArray(u8, .uint8);

/// Wrapper around JavaScript `Uint8ClampedArray`.
pub const Uint8ClampedArray = TypedArray(u8, .uint8_clamped);

/// Wrapper around JavaScript `Int16Array`.
pub const Int16Array = TypedArray(i16, .int16);

/// Wrapper around JavaScript `Uint16Array`.
pub const Uint16Array = TypedArray(u16, .uint16);

/// Wrapper around JavaScript `Int32Array`.
pub const Int32Array = TypedArray(i32, .int32);

/// Wrapper around JavaScript `Uint32Array`.
pub const Uint32Array = TypedArray(u32, .uint32);

/// Wrapper around JavaScript `Float32Array`.
pub const Float32Array = TypedArray(f32, .float32);

/// Wrapper around JavaScript `Float64Array`.
pub const Float64Array = TypedArray(f64, .float64);

/// Wrapper around JavaScript `BigInt64Array`.
pub const BigInt64Array = TypedArray(i64, .bigint64);

/// Wrapper around JavaScript `BigUint64Array`.
pub const BigUint64Array = TypedArray(u64, .biguint64);

test "TypedArray exposes expected subtype metadata" {
    try @import("std").testing.expect(Uint8Array.expected_array_type == .uint8);
    try @import("std").testing.expect(Float64Array.expected_array_type == .float64);
}
