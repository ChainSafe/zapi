# README Restructure + Comprehensive Examples — Design

## Overview

Restructure the README to lead with the high-level JS DSL as the default usage path, move low-level N-API to an "Advanced" section, and expand the DSL example module with comprehensive coverage of all types and patterns.

## README Structure

The README is reorganized top-to-bottom with DSL-first ordering:

### 1. Header + Tagline

```markdown
# zapi

A Zig N-API wrapper library and CLI for building and publishing cross-platform Node.js native addons.

zapi provides two main components:

1. **Zig Library** (`src/`) - Write Node.js native addons in Zig with a high-level DSL that mirrors JavaScript's type system
2. **CLI Tool** (`ts/`) - Build tooling for cross-compiling and publishing multi-platform npm packages
```

### 2. Installation

Unchanged from current README.

### 3. Quick Start

Show the DSL approach as the default:

```zig
const js = @import("zapi").js;

pub fn add(a: js.Number, b: js.Number) js.Number {
    return js.Number.from(a.assertI32() + b.assertI32());
}

pub const Counter = struct {
    pub const js_class = true;
    count: i32,

    pub fn init(start: js.Number) Counter {
        return .{ .count = start.assertI32() };
    }

    pub fn increment(self: *Counter) void {
        self.count += 1;
    }

    pub fn getCount(self: Counter) js.Number {
        return js.Number.from(self.count);
    }
};

comptime { js.exportModule(@This()); }
```

JS usage:
```js
const mod = require('./my_module.node');
mod.add(1, 2); // 3
const c = new mod.Counter(0);
c.increment();
c.getCount(); // 1
```

### 4. JS Types Reference

Table of all DSL types with brief description and key methods:

| Type | JS Equivalent | Key Methods |
|------|--------------|-------------|
| `Number` | `number` | `toI32()`, `toF64()`, `assertI32()`, `from(anytype)` |
| `String` | `string` | `toSlice(buf)`, `toOwnedSlice(alloc)`, `len()`, `from([]const u8)` |
| `Boolean` | `boolean` | `toBool()`, `assertBool()`, `from(bool)` |
| `BigInt` | `bigint` | `toI64()`, `toU64()`, `toI128()`, `from(anytype)` |
| `Date` | `Date` | `toTimestamp()`, `from(f64)` |
| `Array` | `Array` | `get(i)`, `getNumber(i)`, `length()`, `set(i, val)` |
| `Object(T)` | `object` | `get()`, `set(value)` |
| `Function` | `Function` | `call(args)` |
| `Value` | `any` | `isNumber()`, `asNumber()`, etc. |
| `Uint8Array` etc. | `TypedArray` | `toSlice()`, `from(slice)` |
| `Promise(T)` | `Promise` | `resolve(value)`, `reject(err)` |

### 5. Functions

Three patterns:

**Basic** — direct parameter/return mapping:
```zig
pub fn add(a: Number, b: Number) Number {
    return Number.from(a.assertI32() + b.assertI32());
}
```

**Error handling** — `!T` maps to thrown JS exception:
```zig
pub fn safeDivide(a: Number, b: Number) !Number {
    const divisor = b.assertI32();
    if (divisor == 0) return error.DivisionByZero;
    return Number.from(@divTrunc(a.assertI32(), divisor));
}
```

**Nullable returns** — `?T` maps to `undefined`:
```zig
pub fn findIndex(arr: Array, target: Number) ?Number {
    // returns Number or undefined
}
```

### 6. Classes

Show the pattern:
- `pub const js_class = true` — marker
- `pub fn init(...)` — constructor
- `pub fn method(self: *T, ...)` — mutable instance method
- `pub fn method(self: T, ...)` — immutable instance method
- `pub fn method(...)` — static method (no self)
- `pub fn deinit(self: *T)` — optional GC destructor

### 7. Working with Types

Subsections for each complex type pattern:

**Typed Objects** — `Object(T)` with struct mapping:
```zig
const Config = struct { host: String, port: Number };
pub fn connect(config: Object(Config)) !String { ... }
```

**TypedArrays** — processing binary data:
```zig
pub fn sum(data: Float64Array) Number { ... }
```

**Promises** — async returns:
```zig
pub fn fetchData(url: String) !Promise(String) { ... }
```

**Callbacks** — accepting JS functions:
```zig
pub fn forEach(arr: Array, callback: Function) !void { ... }
```

### 8. Mixing DSL and N-API

Show how to drop down:
```zig
pub fn advanced(val: Value) !Number {
    const e = js.env(); // access low-level Env
    // use e.createInt32(), e.throwTypeError(), etc.
}
```

### 9. Advanced: Low-Level N-API

Current README sections moved here:
- Manual callback style
- `createCallback` with hints
- `defineClass` manual registration
- AsyncWork
- ThreadSafeFunction
- Error handling

### 10. CLI Tool

Unchanged from current README. All CLI docs stay as-is.

### 11. License

Unchanged.

## Example Module

Single file `examples/js_dsl/mod.zig` with clearly commented sections. Single test file `examples/js_dsl/mod.test.ts`.

### Section 1: Basic Functions

```zig
// --- Basic Functions ---
pub fn add(a: Number, b: Number) Number
pub fn greet(name: String) !String
```

### Section 2: Error Handling

```zig
// --- Error Handling ---
pub fn safeDivide(a: Number, b: Number) !Number  // throws on zero
pub fn findValue(arr: Array, target: Number) ?Number  // returns undefined if not found
```

### Section 3: All Primitive Types

```zig
// --- All Types ---
pub fn doubleNumber(n: Number) Number
pub fn toggleBool(b: Boolean) Boolean
pub fn reverseString(s: String) !String
pub fn doubleBigInt(n: BigInt) BigInt
pub fn tomorrow(d: Date) Date
```

### Section 4: Typed Objects

```zig
// --- Typed Objects ---
const Config = struct { host: String, port: Number, verbose: Boolean };
pub fn formatConfig(config: Object(Config)) !String
```

### Section 5: Arrays

```zig
// --- Arrays ---
pub fn arraySum(arr: Array) Number
pub fn arrayLength(arr: Array) !Number
```

### Section 6: TypedArrays

```zig
// --- TypedArrays ---
pub fn uint8Sum(data: Uint8Array) !Number
pub fn float64Scale(data: Float64Array, factor: Number) Float64Array
```

### Section 7: Promises

```zig
// --- Promises ---
pub fn delayedValue(val: Number) !Promise(Number)
```

Note: Since Promise resolution requires async dispatch (out of DSL scope), this example will create a promise and resolve it synchronously to demonstrate the API. The test verifies the promise resolves.

### Section 8: Callbacks

```zig
// --- Callbacks ---
pub fn applyCallback(val: Number, cb: Function) !Value
```

### Section 9: Classes

```zig
// --- Classes ---
pub const Counter = struct { ... }  // existing
pub const Buffer = struct {         // new: resource-owning class with deinit
    pub const js_class = true;
    data: []u8,
    pub fn init(size: Number) !Buffer  // allocates
    pub fn getSize(self: Buffer) Number
    pub fn getByte(self: Buffer, index: Number) !Number
    pub fn deinit(self: *Buffer) void  // frees
};
```

### Section 10: Mixed DSL + N-API

```zig
// --- Mixed DSL + N-API ---
pub fn getTypeOf(val: Value) !String  // uses js.env() for low-level access
```

### Test File

`examples/js_dsl/mod.test.ts` — one `describe` block per section, covering:
- Basic function calls
- Error throwing and catching
- Undefined returns
- Each primitive type round-trip
- Object field extraction
- Array operations
- TypedArray data processing
- Promise resolution
- Callback invocation
- Class construction, methods, lifecycle
- Mixed mode type checking
