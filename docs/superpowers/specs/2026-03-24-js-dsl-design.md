# zapi JS DSL — High-Level Design

## Overview

A high-level DSL layer (`zapi.js`) on top of the existing N-API wrapper (`zapi.napi`) that aligns with JavaScript's type system. The goal is to let Zig authors write functions whose signatures directly mirror what JS consumers see — no N-API boilerplate, no JS runtime layer.

**Inspired by:** [Zigar](https://github.com/chung-leong/zigar/wiki) — but with zero JS runtime overhead. All conversion and registration happens at Zig compile time.

## Design Principles

- **JS-aligned types** — Zig function signatures mirror JS function signatures
- **Zero-cost wrappers** — All JS types are `struct { val: napi.Value }`, same size as a pointer
- **`pub` = exported** — Public functions and marked structs are automatically exposed to JS
- **Three tiers** — High-level DSL, granular re-export, low-level manual. Each drops down to the next.
- **Pure comptime** — All registration and conversion glue generated at compile time
- **No JS runtime** — No JavaScript shim or runtime layer on the JS side

## Import Structure

```zig
// High-level DSL
const js = @import("zapi").js;

// Low-level (unchanged)
const napi = @import("zapi").napi;
```

`zapi.js` is the DSL namespace. `zapi.napi` is the existing low-level namespace. They are fully separate — no cross-contamination. DSL types wrap `napi.Value` internally, so mixing levels is possible when needed.

## JS Type System

All types are zero-cost wrappers over `napi.Value`. Each provides typed conversion and assertion methods.

### Number

```zig
pub const Number = struct {
    val: napi.Value,

    // Narrowing — returns error on overflow/type mismatch
    pub fn toI32(self: Number) !i32 { ... }
    pub fn toU32(self: Number) !u32 { ... }
    pub fn toF64(self: Number) !f64 { ... }
    pub fn toI64(self: Number) !i64 { ... }

    // Assertion — panics on failure
    pub fn assertI32(self: Number) i32 { ... }
    pub fn assertF64(self: Number) f64 { ... }

    // Construction
    pub fn from(value: anytype) Number { ... }
};
```

### String

```zig
pub const String = struct {
    val: napi.Value,

    pub fn toSlice(self: String, buf: []u8) ![]const u8 { ... }
    pub fn toOwnedSlice(self: String, allocator: Allocator) ![]const u8 { ... }
    pub fn len(self: String) !usize { ... }

    pub fn from(value: []const u8) String { ... }
};
```

### BigInt

```zig
pub const BigInt = struct {
    val: napi.Value,

    pub fn toI64(self: BigInt) !i64 { ... }
    pub fn toU64(self: BigInt) !u64 { ... }
    pub fn toI128(self: BigInt) !i128 { ... }

    pub fn from(value: anytype) BigInt { ... }
};
```

### Boolean

```zig
pub const Boolean = struct {
    val: napi.Value,

    pub fn toBool(self: Boolean) !bool { ... }
    pub fn from(value: bool) Boolean { ... }
};
```

### Date

```zig
pub const Date = struct {
    val: napi.Value,

    pub fn toTimestamp(self: Date) !f64 { ... }  // ms since epoch
    pub fn from(timestamp: f64) Date { ... }
};
```

### Array

```zig
pub const Array = struct {
    val: napi.Value,

    pub fn get(self: Array, index: u32) !Value { ... }
    pub fn getNumber(self: Array, index: u32) !Number { ... }
    pub fn getString(self: Array, index: u32) !String { ... }
    pub fn length(self: Array) !u32 { ... }
    pub fn set(self: Array, index: u32, value: anytype) !void { ... }
};
```

### Object(T)

Comptime-generated accessors from a Zig struct definition.

```zig
pub fn Object(comptime T: type) type {
    return struct {
        val: napi.Value,

        pub fn get(self: @This()) !T { ... }
        pub fn set(self: @This(), value: T) !void { ... }
        // + per-field accessors generated at comptime
    };
}
```

### Function

```zig
pub const Function = struct {
    val: napi.Value,

    pub fn call(self: Function, args: anytype) !Value { ... }
};
```

### TypedArrays

Map directly to Zig slices. One type per JS TypedArray variant.

```zig
pub const Uint8Array = struct {
    val: napi.Value,
    pub fn toSlice(self: Uint8Array) ![]u8 { ... }
    pub fn from(data: []const u8) Uint8Array { ... }
};

pub const Float64Array = struct {
    val: napi.Value,
    pub fn toSlice(self: Float64Array) ![]f64 { ... }
    pub fn from(data: []const f64) Float64Array { ... }
};

// Same pattern for: Int8Array, Uint8ClampedArray, Int16Array, Uint16Array,
// Int32Array, Uint32Array, Float32Array, BigInt64Array, BigUint64Array
```

### Promise(T)

Async return type. JS consumer can `await` or `.catch()`.

```zig
pub fn Promise(comptime T: type) type {
    return struct {
        val: napi.Value,
        deferred: napi.Deferred,

        pub fn resolve(self: @This(), value: T) !void { ... }
        pub fn reject(self: @This(), err: String) !void { ... }
    };
}
```

### Value (untyped escape hatch)

For dynamic or unknown types.

```zig
pub const Value = struct {
    val: napi.Value,

    pub fn asNumber(self: Value) !Number { ... }
    pub fn asString(self: Value) !String { ... }
    pub fn asArray(self: Value) !Array { ... }
    pub fn isNumber(self: Value) bool { ... }
    pub fn isString(self: Value) bool { ... }
    // ...
};
```

## Env Access — Thread-Local Mechanism

Since types are zero-cost (just `napi.Value`), they need `Env` for N-API calls. A thread-local stores the current env, set by the generated callback wrapper.

```zig
threadlocal var current_env: ?napi.Env = null;

pub fn env() napi.Env {
    return current_env orelse @panic("js.env() called outside of a JS callback context");
}
```

- All `from` constructors and conversion methods use `js.env()` internally
- Users can call `js.env()` explicitly for low-level access
- Safe because N-API callbacks always run on the JS main thread
- `defer` restores previous env for nested/re-entrant call safety

## Allocator

`js.allocator()` returns `std.heap.c_allocator`, backed by N-API's underlying C allocator (`malloc`/`free`). Available anywhere within a callback context, no need to pass as a parameter.

```zig
pub fn allocator() Allocator {
    return std.heap.c_allocator;
}
```

## Module Registration

### Tier 1 — High-level DSL

`exportModule(@This())` scans pub decls at comptime and generates all registration.

```zig
const js = @import("zapi").js;

pub fn add(a: js.Number, b: js.Number) js.Number {
    return js.Number.from(a.assertI32() + b.assertI32());
}

comptime { js.exportModule(@This()); }
```

What `exportModule` does at comptime:
1. Iterates `@typeInfo(module).@"struct".decls`
2. For each `pub fn` — generates N-API callback wrapper via `wrapFunction`
3. For each `pub const` struct with `js_class = true` — generates class definition
4. Generates the `napi_register_module_v1` entry point

### Tier 2 — Granular re-export

Pick and choose from multiple modules:

```zig
const js = @import("zapi").js;

pub const add = @import("math.zig").add;
pub const Counter = @import("counter.zig").Counter;

comptime { js.exportModule(@This()); }
```

### Tier 3 — Low-level (unchanged)

```zig
const napi = @import("zapi").napi;

fn initModule(env: napi.Env, exports: napi.Value) !napi.Value {
    try exports.setNamedProperty("add", try env.createFunction(
        napi.createCallback(2, rawAdd, .{}), null,
    ));
    return exports;
}

comptime { napi.registerModule(initModule); }
```

## Callback Wrapping

One generic comptime function template handles all exported functions. No per-function wrapper generation — Zig's comptime generics instantiate per unique signature.

```zig
fn wrapFunction(comptime func: anytype) napi.CallbackFn {
    return struct {
        fn callback(raw_env: napi.c.napi_env, info: napi.c.napi_callback_info) callconv(.c) napi.c.napi_value {
            const prev = current_env;
            current_env = napi.Env.from(raw_env);
            defer current_env = prev;

            // comptime: inspect @typeInfo(@TypeOf(func)).@"fn"
            // comptime: generate arg extraction + type conversion
            // comptime: call func with converted args
            // comptime: convert return value back to napi.Value
        }
    }.callback;
}
```

## Class Lifecycle

Structs with `pub const js_class = true` become JS classes.

```zig
pub const Counter = struct {
    pub const js_class = true;

    count: i32,

    pub fn init(start: Number) !Counter { ... }      // → JS constructor
    pub fn increment(self: *Counter) void { ... }     // → instance method (mutable)
    pub fn getCount(self: Counter) Number { ... }     // → instance method (immutable)
    pub fn reset() void { ... }                       // → static method (no self)
    pub fn deinit(self: *Counter) void { ... }        // → GC destructor (optional)
};
```

**Method resolution rules:**
- `pub fn init(...)` → JS constructor
- `pub fn method(self: *T, ...)` → mutable instance method
- `pub fn method(self: T, ...)` → immutable instance method
- `pub fn method(...)` (no self) → static method
- `pub fn deinit(self: *T)` → N-API finalize callback, called on GC
- Non-pub functions → internal, not exposed

**Memory:** The DSL allocates the struct instance and ties its lifetime to the JS object. `deinit` is called on GC. If no `deinit` is provided, a default finalizer frees the allocation.

## Error Handling

- `!T` return → Zig error becomes a thrown JS exception. Error name becomes the message (e.g., `error.InvalidNumber` → `Error("InvalidNumber")`). The JS user sees a normal thrown error — never `undefined`.
- `?T` return → `null` in Zig maps to `undefined` in JS
- `!?T` → error throws, `null` returns `undefined`
- Zig panics (e.g., `assertI32` on a float) → caught by wrapper, thrown as JS `TypeError`
- Custom messages: `js.throwError("custom message")` for explicit control

## Complete Example

```zig
const js = @import("zapi").js;
const Number = js.Number;
const String = js.String;
const Boolean = js.Boolean;
const Array = js.Array;
const Object = js.Object;
const Uint8Array = js.Uint8Array;
const Promise = js.Promise;

pub fn add(a: Number, b: Number) Number {
    return Number.from(a.assertI32() + b.assertI32());
}

pub fn concat(a: String, b: String) !String {
    var buf_a: [512]u8 = undefined;
    var buf_b: [512]u8 = undefined;
    const sa = try a.toSlice(&buf_a);
    const sb = try b.toSlice(&buf_b);
    var result: [1024]u8 = undefined;
    const len = sa.len + sb.len;
    @memcpy(result[0..sa.len], sa);
    @memcpy(result[sa.len..len], sb);
    return String.from(result[0..len]);
}

pub fn findIndex(arr: Array, target: Number) ?Number {
    const len = arr.length() catch return null;
    const t = target.assertI32();
    for (0..len) |i| {
        const item = arr.getNumber(@intCast(i)) catch continue;
        if (item.assertI32() == t) return Number.from(i);
    }
    return null;
}

const Config = struct { host: String, port: Number, verbose: Boolean };

pub fn connect(config: Object(Config)) !String {
    const c = try config.get();
    _ = c;
    return String.from("connected");
}

pub fn fetchData(url: String) !Promise(Uint8Array) {
    _ = url;
    const promise = try js.createPromise(Uint8Array);
    return promise;
}

pub const Counter = struct {
    pub const js_class = true;

    count: i32,
    history: []i32,

    pub fn init(start: Number) !Counter {
        return .{
            .count = start.assertI32(),
            .history = try js.allocator().alloc(i32, 100),
        };
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

    pub fn deinit(self: *Counter) void {
        js.allocator().free(self.history);
    }
};

comptime { js.exportModule(@This()); }
```

**JS usage:**

```js
const mod = require('./my_module');

mod.add(1, 2);                          // 3
mod.concat("hello ", "world");          // "hello world"
mod.findIndex([10, 20, 30], 20);        // 1
mod.findIndex([10, 20, 30], 99);        // undefined
mod.connect({ host: "localhost", port: 8080, verbose: true }); // "connected"

const data = await mod.fetchData("http://...");  // Uint8Array

const c = new mod.Counter(0);
c.increment();
c.getCount();    // 1
c.isAbove(0);    // true
```
