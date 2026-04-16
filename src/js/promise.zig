const napi = @import("../napi.zig");
const context = @import("context.zig");
const String = @import("string.zig").String;

/// A Promise wrapper parameterized on the resolve type `T`.
///
/// This comptime function returns a new Zig type, `js.Promise(T)`, specialized
/// for a given return type `T`. It is used to create and manage JavaScript
/// `Promise` objects from Zig. `T` must be a ZAPI DSL wrapper type (e.g.,
/// `js.Number`, `js.String`) or a raw `napi.Value`.
///
/// IMPORTANT: When returning `js.Promise(T)` from a DSL function, the promise
/// must be resolved or rejected *before* the function returns. The `deferred`
/// handle is not preserved across the JS boundary — only the `.val` (the JS
/// promise object) is returned to the caller. For async resolution (e.g., from
/// a worker thread), store the `Deferred` handle separately and use `napi.AsyncWork`
/// or `napi.ThreadSafeFunction` from the low-level N-API layer.
pub fn Promise(comptime T: type) type {
    return struct {
        /// The underlying `napi.Value` representing the JavaScript Promise object.
        val: napi.Value,
        /// The N-API `deferred` object used to resolve or reject the promise.
        deferred: napi.Deferred,

        const Self = @This();

        /// Resolves the promise with the given value.
        ///
        /// The `value` must be a ZAPI DSL wrapper type or a raw `napi.Value`.
        /// Returns an error if N-API operations fail (e.g., promise already resolved).
        pub fn resolve(self: Self, value: T) !void {
            const raw = toNapiValue(value);
            try self.deferred.resolve(raw);
        }

        /// Rejects the promise with any JavaScript value (typically an Error object).
        ///
        /// The `err` must be a ZAPI DSL wrapper type or a raw `napi.Value`.
        /// Use `rejectWithMessage` for convenience when you only have a string.
        /// Returns an error if N-API operations fail (e.g., promise already resolved).
        pub fn reject(self: Self, err: anytype) !void {
            const raw = toNapiValue(err);
            try self.deferred.reject(raw);
        }

        /// Convenience method: rejects the promise with a new JavaScript `Error`
        /// object created from a message string.
        ///
        /// This ensures that `.message` and `.stack` properties are correctly
        /// populated in JavaScript `catch` blocks. Panics if N-API operations fail
        /// (e.g., invalid environment or string conversion issues).
        pub fn rejectWithMessage(self: Self, message: String) !void {
            const e = context.env();
            const error_obj = try e.createError(
                try e.createStringUtf8("Error"),
                message.val,
            );
            try self.deferred.reject(error_obj);
        }

        /// Returns the underlying `napi.Value` representation of this JavaScript Promise.
        ///
        /// This is the value that should be returned from a DSL-wrapped function
        /// to JavaScript callers.
        pub fn toValue(self: Self) napi.Value {
            return self.val;
        }
    };
}

/// Creates a new JavaScript `Promise(T)` and its associated deferred control object.
///
/// The caller should return `promise.toValue()` to JavaScript and later call
/// `promise.resolve()` or `promise.reject()` to complete the promise. The `comptime T`
/// parameter defines the expected resolution type of the promise.
///
/// Panics if N-API operations fail (e.g., invalid environment).
pub fn createPromise(comptime T: type) !Promise(T) {
    const e = context.env();
    const deferred = try e.createPromise();
    const val = deferred.getPromise();
    return .{ .val = val, .deferred = deferred };
}

fn toNapiValue(item: anytype) napi.Value {
    const T = @TypeOf(item);
    if (T == napi.Value) return item;
    if (@hasField(T, "val")) return item.val;
    @compileError("Expected a DSL wrapper type (with .val field) or napi.Value, got " ++ @typeName(T));
}
