const napi = @import("../napi.zig");
const context = @import("context.zig");
const String = @import("string.zig").String;

/// A Promise wrapper parameterized on the resolve type `T`.
/// `T` must be a DSL wrapper type (has `.val` field) or `napi.Value`.
pub fn Promise(comptime T: type) type {
    return struct {
        val: napi.Value,
        deferred: napi.Deferred,

        const Self = @This();

        /// Resolves the promise with the given value.
        pub fn resolve(self: Self, value: T) !void {
            const raw = toNapiValue(value);
            try self.deferred.resolve(raw);
        }

        /// Rejects the promise with an error string.
        pub fn reject(self: Self, err: String) !void {
            try self.deferred.reject(err.val);
        }

        /// Returns the underlying JS promise value (to return to JS callers).
        pub fn toValue(self: Self) napi.Value {
            return self.val;
        }
    };
}

/// Creates a new Promise(T) and returns it. The caller should return
/// `promise.toValue()` to JS and later call `promise.resolve()` or `promise.reject()`.
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
