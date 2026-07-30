const std = @import("std");
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
            if (info.length == 0) return &.{};
            const byte_ptr: [*]u8 = info.data.ptr;
            const typed_ptr: [*]Element = @ptrCast(@alignCast(byte_ptr));
            return typed_ptr[0..info.length];
        }

        /// Creates a new JavaScript TypedArray backed by an *external* (native-heap)
        /// ArrayBuffer.
        ///
        /// The contents of `slice` are copied into a freshly allocated native buffer
        /// (via `context.allocator()`).
        ///
        /// V8 holds the pointer to manage the JS-side lifetime; the
        /// native buffer is freed by a finalizer when V8 collects the ArrayBuffer.
        pub fn fromExternal(slice: []const Element) !Self {
            const e = context.env();
            const buf = try context.allocator().dupe(Element, slice);

            const byte_len = slice.len * @sizeOf(Element);
            const len_hint: ?*anyopaque = @ptrFromInt(slice.len);
            const finalize_cb = comptime napi.wrapSliceFinalizeCallback(Element, externalFinalizer);
            const arraybuffer = e.createExternalArrayBuffer(std.mem.sliceAsBytes(buf), finalize_cb, len_hint) catch |err| {
                context.allocator().free(buf);
                return err;
            };

            _ = try e.adjustExternalMemory(@intCast(byte_len));
            const val = try e.createTypedarray(array_type, slice.len, arraybuffer, 0);
            return .{ .val = val };
        }

        /// Finalizer for buffers allocated by `fromExternal`. Frees the native
        /// allocation and reverses the matching `adjustExternalMemory` accounting.
        ///
        /// Caller is responsible for calling a matching `adjustExternalMemory` at
        /// the appropriate callsite to let V8 know about native heap memory usage.
        fn externalFinalizer(env: napi.Env, data: []Element) void {
            const byte_len = data.len * @sizeOf(Element);
            context.allocator().free(data);
            _ = env.adjustExternalMemory(-@as(i64, @intCast(byte_len))) catch {};
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

/// Allocator-backed elements whose ownership can be transferred to a JavaScript
/// TypedArray without copying the element data.
///
/// Like other Zig owning values, an OwnedTypedArray must not be copied or
/// deinitialized after transfer.
pub fn OwnedTypedArray(comptime Element: type, comptime array_type: TypedarrayType) type {
    return struct {
        allocator: std.mem.Allocator,
        data: []Element,

        const Self = @This();
        pub const owned_typed_array = {};
        pub const expected_array_type = array_type;

        /// Takes ownership of `data`, which must have been allocated by `allocator`.
        /// The allocator must remain valid until the value is deinitialized or
        /// finalized by JavaScript.
        pub fn fromOwnedSlice(allocator: std.mem.Allocator, data: []Element) Self {
            return .{
                .allocator = allocator,
                .data = data,
            };
        }

        /// Copies `data` into a new owned allocation.
        pub fn fromSlice(allocator: std.mem.Allocator, data: []const Element) !Self {
            return .fromOwnedSlice(allocator, try allocator.dupe(Element, data));
        }

        /// Releases data that has not been transferred to JavaScript.
        pub fn deinit(self: *Self) void {
            self.allocator.free(self.data);
            self.* = undefined;
        }

        /// Transfers ownership to a JavaScript TypedArray.
        ///
        /// This consumes the value even on failure; the caller must not
        /// deinitialize it afterwards. Unsupported external ArrayBuffers return
        /// `error.NoExternalBuffersAllowed` without a copy fallback.
        pub fn intoValue(self: Self, env: napi.Env) !napi.Value {
            const allocator = self.allocator;
            const data = self.data;

            if (data.len == 0) {
                defer allocator.free(data);
                const arraybuffer = try env.createArrayBuffer(0, null);
                return env.createTypedarray(array_type, 0, arraybuffer, 0);
            }

            const owner = try moveToHeap(self);
            const arraybuffer = env.createExternalArrayBuffer(
                std.mem.sliceAsBytes(data),
                finalize,
                owner,
            ) catch |err| {
                switch (err) {
                    error.NoExternalBuffersAllowed,
                    error.PendingException,
                    error.CannotRunJS,
                    => release(owner),
                    else => {},
                }
                return err;
            };

            return env.createTypedarray(array_type, data.len, arraybuffer, 0);
        }

        fn moveToHeap(self: Self) !*Self {
            const owner = self.allocator.create(Self) catch |err| {
                self.allocator.free(self.data);
                return err;
            };
            owner.* = self;
            return owner;
        }

        fn finalize(
            _: napi.c.napi_env,
            _: ?*anyopaque,
            finalize_hint: ?*anyopaque,
        ) callconv(.c) void {
            const owner: *Self =
                @ptrCast(@alignCast(finalize_hint orelse unreachable));
            release(owner);
        }

        fn release(owner: *Self) void {
            const allocator = owner.allocator;
            allocator.free(owner.data);
            allocator.destroy(owner);
        }
    };
}

/// Returns whether `T` is an OwnedTypedArray specialization.
pub fn isOwnedTypedArray(comptime T: type) bool {
    return @typeInfo(T) == .@"struct" and @hasDecl(T, "owned_typed_array");
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

/// Owned native elements transferable to a JavaScript `Int8Array`.
pub const OwnedInt8Array = OwnedTypedArray(i8, .int8);

/// Owned native elements transferable to a JavaScript `Uint8Array`.
pub const OwnedUint8Array = OwnedTypedArray(u8, .uint8);

/// Owned native elements transferable to a JavaScript `Uint8ClampedArray`.
pub const OwnedUint8ClampedArray = OwnedTypedArray(u8, .uint8_clamped);

/// Owned native elements transferable to a JavaScript `Int16Array`.
pub const OwnedInt16Array = OwnedTypedArray(i16, .int16);

/// Owned native elements transferable to a JavaScript `Uint16Array`.
pub const OwnedUint16Array = OwnedTypedArray(u16, .uint16);

/// Owned native elements transferable to a JavaScript `Int32Array`.
pub const OwnedInt32Array = OwnedTypedArray(i32, .int32);

/// Owned native elements transferable to a JavaScript `Uint32Array`.
pub const OwnedUint32Array = OwnedTypedArray(u32, .uint32);

/// Owned native elements transferable to a JavaScript `Float32Array`.
pub const OwnedFloat32Array = OwnedTypedArray(f32, .float32);

/// Owned native elements transferable to a JavaScript `Float64Array`.
pub const OwnedFloat64Array = OwnedTypedArray(f64, .float64);

/// Owned native elements transferable to a JavaScript `BigInt64Array`.
pub const OwnedBigInt64Array = OwnedTypedArray(i64, .bigint64);

/// Owned native elements transferable to a JavaScript `BigUint64Array`.
pub const OwnedBigUint64Array = OwnedTypedArray(u64, .biguint64);

test "TypedArray exposes expected subtype metadata" {
    try @import("std").testing.expect(Uint8Array.expected_array_type == .uint8);
    try @import("std").testing.expect(Float64Array.expected_array_type == .float64);
}

test "OwnedTypedArray fromSlice owns an independent copy" {
    var source = [_]u8{ 1, 2, 3 };
    var array = try OwnedUint8Array.fromSlice(std.testing.allocator, &source);
    defer array.deinit();

    source[0] = 9;
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, array.data);
}

test "OwnedTypedArray releases data when moving the owner to the heap fails" {
    const data = try std.testing.allocator.dupe(u8, &.{ 1, 2, 3 });

    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = 0,
    });
    const array = OwnedUint8Array.fromOwnedSlice(failing_allocator.allocator(), data);

    try std.testing.expectError(
        error.OutOfMemory,
        OwnedUint8Array.moveToHeap(array),
    );
    try std.testing.expectEqual(@as(usize, 1), failing_allocator.deallocations);
}
