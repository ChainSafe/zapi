//! Comprehensive DSL example demonstrating all zapi.js types and patterns.

const std = @import("std");
const js = @import("zapi").js;
const Number = js.Number;
const String = js.String;
const Boolean = js.Boolean;
const BigInt = js.BigInt;
const Date = js.Date;
const Array = js.Array;
const Object = js.Object;
const Function = js.Function;
const Value = js.Value;
const Uint8Array = js.Uint8Array;
const Float64Array = js.Float64Array;
const Promise = js.Promise;

/// Sub-module demonstrating nested namespaces.
pub const math = @import("math.zig");

// ============================================================================
// Section 1: Basic Functions
// ============================================================================

/// Add two numbers.
pub fn add(a: Number, b: Number) !Number {
    return Number.from(try a.toI32() + try b.toI32());
}

/// Return a greeting string.
pub fn greet(name: String) !String {
    var buf: [256]u8 = undefined;
    const slice = try name.toSlice(&buf);
    var result: [512]u8 = undefined;
    const greeting = "Hello, ";
    @memcpy(result[0..greeting.len], greeting);
    @memcpy(result[greeting.len .. greeting.len + slice.len], slice);
    const total_len = greeting.len + slice.len;
    result[total_len] = '!';
    return String.from(result[0 .. total_len + 1]);
}

// ============================================================================
// Section 2: Error Handling
// ============================================================================

/// Divide two numbers. Throws on division by zero.
pub fn safeDivide(a: Number, b: Number) !Number {
    const divisor = b.assertI32();
    if (divisor == 0) return error.DivisionByZero;
    return Number.from(@divTrunc(a.assertI32(), divisor));
}

/// Find index of target in array. Returns undefined if not found.
pub fn findValue(arr: Array, target: Number) ?Number {
    const len = arr.length() catch return null;
    const t = target.assertI32();
    var i: u32 = 0;
    while (i < len) : (i += 1) {
        const item = arr.getNumber(i) catch continue;
        if (item.assertI32() == t) return Number.from(i);
    }
    return null;
}

// ============================================================================
// Section 3: All Primitive Types
// ============================================================================

/// Double a number.
pub fn doubleNumber(n: Number) Number {
    return Number.from(n.assertI32() * 2);
}

/// Return a Number created from a u64 value just above i64 max.
pub fn largeUnsignedBoundary() Number {
    return Number.from(@as(u64, std.math.maxInt(i64)) + 1);
}

/// Negate a boolean.
pub fn toggleBool(b: Boolean) Boolean {
    return Boolean.from(!b.assertBool());
}

/// Reverse a string.
pub fn reverseString(s: String) !String {
    var buf: [256]u8 = undefined;
    const slice = try s.toSlice(&buf);
    var reversed: [256]u8 = undefined;
    for (slice, 0..) |ch, i| {
        reversed[slice.len - 1 - i] = ch;
    }
    return String.from(reversed[0..slice.len]);
}

/// Double a BigInt value.
pub fn doubleBigInt(n: BigInt) !BigInt {
    var lossless: bool = false;
    const val = try n.toI64(&lossless);
    return BigInt.from(val * 2);
}

/// Add one day (86400000ms) to a Date.
pub fn tomorrow(d: Date) Date {
    const ts = d.assertTimestamp();
    return Date.from(ts + 86_400_000.0);
}

// ============================================================================
// Section 4: Typed Objects
// ============================================================================

const Config = struct { host: String, port: Number, verbose: Boolean };

/// Format a config object as a string: "host:port (verbose: true/false)"
pub fn formatConfig(config: Object(Config)) !String {
    const c = try config.get();
    var host_buf: [128]u8 = undefined;
    const host = try c.host.toSlice(&host_buf);
    const port = c.port.assertI32();
    const verbose = c.verbose.assertBool();

    var result: [256]u8 = undefined;
    const written = std.fmt.bufPrint(&result, "{s}:{d} (verbose: {s})", .{
        host,
        port,
        if (verbose) "true" else "false",
    }) catch return error.FormatError;
    return String.from(written);
}

// ============================================================================
// Section 5: Arrays
// ============================================================================

/// Sum all numbers in an array.
pub fn arraySum(arr: Array) Number {
    const len = arr.length() catch return Number.from(@as(i32, 0));
    var sum: i32 = 0;
    var i: u32 = 0;
    while (i < len) : (i += 1) {
        const item = arr.getNumber(i) catch continue;
        sum += item.assertI32();
    }
    return Number.from(sum);
}

/// Return the length of an array.
pub fn arrayLength(arr: Array) !Number {
    const len = try arr.length();
    return Number.from(len);
}

// ============================================================================
// Section 6: TypedArrays
// ============================================================================

/// Sum all bytes in a Uint8Array.
pub fn uint8Sum(data: Uint8Array) !Number {
    const slice = try data.toSlice();
    var sum: i32 = 0;
    for (slice) |byte| {
        sum += @intCast(byte);
    }
    return Number.from(sum);
}

/// Scale all values in a Float64Array by a factor. Returns a new array.
pub fn float64Scale(data: Float64Array, factor: Number) !Float64Array {
    const slice = try data.toSlice();
    const f = factor.assertF64();
    const alloc = js.allocator();
    const scaled = try alloc.alloc(f64, slice.len);
    defer alloc.free(scaled);
    for (slice, 0..) |val, i| {
        scaled[i] = val * f;
    }
    return Float64Array.from(scaled);
}

// ============================================================================
// Section 7: Promises
// ============================================================================

/// Create a promise that resolves immediately with the given value.
pub fn resolvedPromise(val: Number) !Promise(Number) {
    var promise = try js.createPromise(Number);
    try promise.resolve(val);
    return promise;
}

// ============================================================================
// Section 8: Callbacks
// ============================================================================

/// Apply a callback function to a value and return the result.
pub fn applyCallback(val: Number, cb: Function) !Value {
    return try cb.call(.{val});
}

// ============================================================================
// Section 9: Classes
// ============================================================================

/// A simple counter class.
pub const Counter = struct {
    pub const js_meta = js.class(.{});
    count: i32,

    pub fn init(start: Number) Counter {
        return .{ .count = start.assertI32() };
    }

    pub fn increment(self: *Counter) void {
        self.count += 1;
    }

    pub fn getCount(self: Counter) Number {
        return Number.from(self.count);
    }

    pub fn isAbove(self: Counter, threshold: Number) Boolean {
        return Boolean.from(self.count > threshold.assertI32());
    }
};

/// A resource-owning buffer class demonstrating deinit.
pub const Buffer = struct {
    pub const js_meta = js.class(.{});
    data: []u8,

    pub fn init(size: Number) !Buffer {
        const len: usize = @intCast(size.assertI32());
        const alloc = js.allocator();
        const data = try alloc.alloc(u8, len);
        @memset(data, 0);
        return .{ .data = data };
    }

    pub fn getSize(self: Buffer) Number {
        return Number.from(@as(i32, @intCast(self.data.len)));
    }

    pub fn getByte(self: Buffer, index: Number) !Number {
        const i: usize = @intCast(index.assertI32());
        if (i >= self.data.len) return error.IndexOutOfBounds;
        return Number.from(@as(i32, @intCast(self.data[i])));
    }

    pub fn deinit(self: *Buffer) void {
        js.allocator().free(self.data);
    }
};

// ============================================================================
// Section 10: Mixed DSL + N-API
// ============================================================================

/// Return the JS typeof string for any value.
/// Demonstrates dropping down to low-level napi to call raw N-API methods.
pub fn getTypeOf(val: Value) !String {
    // Use the low-level napi.Value to coerce value to string via N-API
    const coerced = try val.toValue().coerceToString();
    // Then wrap it back into the DSL String type
    return .{ .val = coerced };
}

/// Create a JS object with a property, using low-level env for object creation.
pub fn makeObject(key: String, value: Number) !Value {
    const e = js.env();
    // Use low-level Env to create a plain JS object
    const obj = try e.createObject();
    // Use low-level property setting with DSL values
    var key_buf: [128]u8 = undefined;
    const key_slice = try key.toSlice(&key_buf);
    var name_buf: [129]u8 = undefined;
    @memcpy(name_buf[0..key_slice.len], key_slice);
    name_buf[key_slice.len] = 0;
    const name: [:0]const u8 = name_buf[0..key_slice.len :0];
    try obj.setNamedProperty(name, value.toValue());
    return .{ .val = obj };
}

// ============================================================================
// Section 11: Module Lifecycle (init/cleanup with env refcounting)
// ============================================================================

/// Tracks how many env registrations have occurred.
var module_init_count: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);

/// Captures the refcount value passed to init on the very first call.
var first_init_refcount: std.atomic.Value(u32) = std.atomic.Value(u32).init(999);

/// Tracks the current env refcount as seen by the DSL (exposed for testing).
var current_refcount: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);

/// Returns how many times init has been called.
pub fn getInitCount() Number {
    return Number.from(@as(i32, @intCast(module_init_count.load(.acquire))));
}

/// Returns the refcount value that was passed to init on the first call.
pub fn getFirstRefcount() Number {
    return Number.from(@as(i32, @intCast(first_init_refcount.load(.acquire))));
}

/// Returns the current env refcount.
pub fn getEnvRefcount() Number {
    return Number.from(@as(i32, @intCast(current_refcount.load(.acquire))));
}

// ============================================================================
// Section 13: Static Factory Methods + Optional Parameters
// ============================================================================

var factory_resource_init_count: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);
var factory_resource_deinit_count: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);

fn makeFactoryResource(byte: u8) !FactoryResource {
    const data = try js.allocator().alloc(u8, 1);
    data[0] = byte;
    _ = factory_resource_init_count.fetchAdd(1, .monotonic);
    return .{ .data = data };
}

pub fn getFactoryResourceInitCount() Number {
    return Number.from(@as(i32, @intCast(factory_resource_init_count.load(.acquire))));
}

pub fn getFactoryResourceDeinitCount() Number {
    return Number.from(@as(i32, @intCast(factory_resource_deinit_count.load(.acquire))));
}

/// A point class demonstrating static factories and optional params.
pub const Point = struct {
    pub const js_meta = js.class(.{});
    x: i32,
    y: i32,

    pub fn init() Point {
        return .{ .x = 0, .y = 0 };
    }

    /// Static factory: Point.create(x, y)
    pub fn create(x: Number, y: Number) Point {
        return .{ .x = x.assertI32(), .y = y.assertI32() };
    }

    /// Static factory with optional: Point.fromArray(arr, offset?)
    pub fn fromArray(arr: Array, offset: ?Number) !Point {
        const off: u32 = if (offset) |o| o.assertU32() else 0;
        const x_val = try arr.getNumber(off);
        const y_val = try arr.getNumber(off + 1);
        return .{ .x = x_val.assertI32(), .y = y_val.assertI32() };
    }

    /// Instance method
    pub fn getX(self: Point) Number {
        return Number.from(self.x);
    }

    pub fn getY(self: Point) Number {
        return Number.from(self.y);
    }

    /// Instance method with optional param
    pub fn translate(self: *Point, dx: Number, dy: ?Number) void {
        self.x += dx.assertI32();
        if (dy) |d| {
            self.y += d.assertI32();
        }
    }

    /// Demonstrates `js.thisArg()` by comparing the active JS receiver.
    pub fn hasReceiver(self: Point, other: Value) !Boolean {
        _ = self;
        return Boolean.from(try js.thisArg().strictEquals(other.toValue()));
    }
};

/// A resource-owning class used to verify placeholder cleanup in factory paths.
pub const FactoryResource = struct {
    pub const js_meta = js.class(.{});
    data: []u8,

    pub fn init() !FactoryResource {
        return makeFactoryResource(0);
    }

    pub fn withByte(value: Number) !FactoryResource {
        return makeFactoryResource(@intCast(value.assertU32()));
    }

    pub fn cloneWithByte(self: FactoryResource, value: Number) !FactoryResource {
        _ = self;
        return makeFactoryResource(@intCast(value.assertU32()));
    }

    pub fn getByte(self: FactoryResource) Number {
        return Number.from(@as(i32, @intCast(self.data[0])));
    }

    pub fn deinit(self: *FactoryResource) void {
        _ = factory_resource_deinit_count.fetchAdd(1, .monotonic);
        js.allocator().free(self.data);
    }
};

// ============================================================================
// Module Export
// ============================================================================

// ============================================================================
// Section 15: Getters and Setters
// ============================================================================

/// A settings class demonstrating computed getters and setters.
pub const Settings = struct {
    pub const js_meta = js.class(.{
        .properties = .{
            .volume = js.prop(.{ .get = true, .set = true }),
            .muted = js.prop(.{ .get = true, .set = true }),
            .label = js.prop(.{ .get = true, .set = false }),
            .kind = js.prop(.{ .get = "kindValue", .set = false }),
        },
    });

    _volume: i32,
    _muted: bool,
    _label: []const u8,
    _kind: []const u8,

    pub fn init() Settings {
        return .{
            ._volume = 50,
            ._muted = false,
            ._label = "default",
            ._kind = "settings",
        };
    }

    // Read-write getter/setter: obj.volume / obj.volume = 80
    pub fn volume(self: Settings) Number {
        return Number.from(self._volume);
    }

    pub fn setVolume(self: *Settings, value: Number) !void {
        const v = value.assertI32();
        if (v < 0 or v > 100) return error.VolumeOutOfRange;
        self._volume = v;
    }

    // Read-write getter/setter: obj.muted / obj.muted = true
    pub fn muted(self: Settings) Boolean {
        return Boolean.from(self._muted);
    }

    pub fn setMuted(self: *Settings, value: Boolean) void {
        self._muted = value.assertBool();
    }

    // Read-only getter: obj.label
    pub fn label(self: Settings) String {
        return String.from(self._label);
    }

    pub fn kindValue(self: Settings) String {
        return String.from(self._kind);
    }

    // Regular method (not a getter)
    pub fn reset(self: *Settings) void {
        self._volume = 50;
        self._muted = false;
    }
};

pub const Token = struct {
    pub const js_meta = js.class(.{});

    value: i32,

    pub fn init(value: Number) Token {
        return .{ .value = value.assertI32() };
    }

    pub fn getValue(self: Token) Number {
        return Number.from(self.value);
    }
};

pub const TokenIssuer = struct {
    pub const js_meta = js.class(.{});

    seed: i32,

    pub fn init(seed: Number) TokenIssuer {
        return .{ .seed = seed.assertI32() };
    }

    pub fn issue(self: TokenIssuer) Token {
        return .{ .value = self.seed * 2 };
    }
};

pub fn makeToken(value: Number) Token {
    return .{ .value = value.assertI32() + 1 };
}

comptime {
    js.exportModule(@This(), .{
        .init = struct {
            fn f(refcount: u32) !void {
                const count = module_init_count.fetchAdd(1, .monotonic);
                if (count == 0) {
                    first_init_refcount.store(refcount, .release);
                }
                current_refcount.store(refcount + 1, .release);
            }
        }.f,
        .cleanup = struct {
            fn f(refcount: u32) void {
                current_refcount.store(refcount, .release);
            }
        }.f,
    });
}
