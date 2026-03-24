# README Restructure + Comprehensive Examples — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure README to lead with DSL, expand example module to cover all types and patterns.

**Architecture:** Two tasks: (1) expand example module + tests, (2) rewrite README. Examples first so README can reference working, tested code.

**Tech Stack:** Zig, Node.js N-API, Vitest, Markdown

---

## File Structure

```
examples/js_dsl/
├── mod.zig       (MODIFY — expand with all type/pattern sections)
└── mod.test.ts   (MODIFY — expand with comprehensive tests)
README.md         (MODIFY — full rewrite, DSL-first structure)
```

---

## Chunk 1: Expand Example Module and Tests

### Task 1: Expand examples/js_dsl/mod.zig with all sections

**Files:**
- Modify: `examples/js_dsl/mod.zig`

- [ ] **Step 1: Rewrite mod.zig with all sections**

Replace the entire file with the following. Note: existing `add`, `greet`, `findValue`, `Counter` are preserved but reorganized. `willThrow` is replaced by `safeDivide`. `isAbove` stays on Counter.

```zig
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

// ============================================================================
// Section 1: Basic Functions
// ============================================================================

/// Add two numbers.
pub fn add(a: Number, b: Number) Number {
    return Number.from(a.assertI32() + b.assertI32());
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
pub fn doubleBigInt(n: BigInt) BigInt {
    const val = n.assertI64();
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
    pub const js_class = true;
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
    pub const js_class = true;
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
/// Demonstrates dropping down to low-level napi.Env to call raw N-API methods.
pub fn getTypeOf(val: Value) !String {
    const e = js.env();
    // Use the low-level Env to coerce value to string via N-API
    const coerced = try e.coerceToString(val.toValue());
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
// Module Export
// ============================================================================

comptime {
    js.exportModule(@This());
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `zig build build-lib:example_js_dsl`
Expected: Builds successfully.

- [ ] **Step 3: Commit**

```bash
git add examples/js_dsl/mod.zig
git commit -m "feat(js): expand DSL example with all types and patterns"
```

---

### Task 2: Expand examples/js_dsl/mod.test.ts with comprehensive tests

**Files:**
- Modify: `examples/js_dsl/mod.test.ts`

- [ ] **Step 1: Rewrite mod.test.ts with all sections**

Replace the entire file:

```typescript
import { describe, it, expect } from "vitest";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const mod = require("../../zig-out/lib/example_js_dsl.node");

// Section 1: Basic Functions
describe("basic functions", () => {
	it("add two numbers", () => {
		expect(mod.add(1, 2)).toEqual(3);
	});

	it("add negative numbers", () => {
		expect(mod.add(-5, 3)).toEqual(-2);
	});

	it("greet returns formatted string", () => {
		expect(mod.greet("World")).toEqual("Hello, World!");
	});
});

// Section 2: Error Handling
describe("error handling", () => {
	it("safeDivide returns result", () => {
		expect(mod.safeDivide(10, 3)).toEqual(3);
	});

	it("safeDivide throws on zero", () => {
		expect(() => mod.safeDivide(10, 0)).toThrow();
	});

	it("findValue returns index when found", () => {
		expect(mod.findValue([10, 20, 30], 20)).toEqual(1);
	});

	it("findValue returns undefined when not found", () => {
		expect(mod.findValue([10, 20, 30], 99)).toBeUndefined();
	});
});

// Section 3: All Primitive Types
describe("primitive types", () => {
	it("doubleNumber", () => {
		expect(mod.doubleNumber(21)).toEqual(42);
	});

	it("toggleBool", () => {
		expect(mod.toggleBool(true)).toBe(false);
		expect(mod.toggleBool(false)).toBe(true);
	});

	it("reverseString", () => {
		expect(mod.reverseString("hello")).toEqual("olleh");
		expect(mod.reverseString("a")).toEqual("a");
	});

	it("doubleBigInt", () => {
		expect(mod.doubleBigInt(50n)).toEqual(100n);
	});

	it("tomorrow adds one day", () => {
		const now = new Date("2025-01-01T00:00:00Z");
		const result = mod.tomorrow(now);
		expect(result).toBeInstanceOf(Date);
		expect(result.toISOString()).toEqual("2025-01-02T00:00:00.000Z");
	});
});

// Section 4: Typed Objects
describe("typed objects", () => {
	it("formatConfig returns formatted string", () => {
		const config = { host: "localhost", port: 8080, verbose: true };
		expect(mod.formatConfig(config)).toEqual("localhost:8080 (verbose: true)");
	});

	it("formatConfig with verbose false", () => {
		const config = { host: "example.com", port: 443, verbose: false };
		expect(mod.formatConfig(config)).toEqual("example.com:443 (verbose: false)");
	});
});

// Section 5: Arrays
describe("arrays", () => {
	it("arraySum sums all elements", () => {
		expect(mod.arraySum([1, 2, 3, 4])).toEqual(10);
	});

	it("arraySum of empty array", () => {
		expect(mod.arraySum([])).toEqual(0);
	});

	it("arrayLength returns length", () => {
		expect(mod.arrayLength([10, 20, 30])).toEqual(3);
	});
});

// Section 6: TypedArrays
describe("typed arrays", () => {
	it("uint8Sum sums bytes", () => {
		const data = new Uint8Array([1, 2, 3, 4, 5]);
		expect(mod.uint8Sum(data)).toEqual(15);
	});

	it("float64Scale scales values", () => {
		const data = new Float64Array([1.0, 2.0, 3.0]);
		const result = mod.float64Scale(data, 2.5);
		expect(result).toBeInstanceOf(Float64Array);
		expect(Array.from(result)).toEqual([2.5, 5.0, 7.5]);
	});
});

// Section 7: Promises
describe("promises", () => {
	it("resolvedPromise resolves with value", async () => {
		const result = await mod.resolvedPromise(42);
		expect(result).toEqual(42);
	});
});

// Section 8: Callbacks
describe("callbacks", () => {
	it("applyCallback invokes function", () => {
		const result = mod.applyCallback(5, (n: number) => n * 3);
		expect(result).toEqual(15);
	});
});

// Section 9: Classes
describe("Counter class", () => {
	it("creates with initial value", () => {
		const c = new mod.Counter(5);
		expect(c.getCount()).toEqual(5);
	});

	it("increments", () => {
		const c = new mod.Counter(0);
		c.increment();
		c.increment();
		expect(c.getCount()).toEqual(2);
	});

	it("isAbove returns boolean", () => {
		const c = new mod.Counter(10);
		expect(c.isAbove(5)).toBe(true);
		expect(c.isAbove(15)).toBe(false);
	});
});

describe("Buffer class", () => {
	it("creates with size", () => {
		const b = new mod.Buffer(16);
		expect(b.getSize()).toEqual(16);
	});

	it("getByte returns zero-initialized data", () => {
		const b = new mod.Buffer(4);
		expect(b.getByte(0)).toEqual(0);
		expect(b.getByte(3)).toEqual(0);
	});

	it("getByte throws on out of bounds", () => {
		const b = new mod.Buffer(4);
		expect(() => b.getByte(4)).toThrow();
	});
});

// Section 10: Mixed DSL + N-API
describe("mixed DSL + N-API", () => {
	it("getTypeOf coerces value to string", () => {
		expect(mod.getTypeOf(42)).toEqual("42");
		expect(mod.getTypeOf(true)).toEqual("true");
		expect(mod.getTypeOf("hello")).toEqual("hello");
	});

	it("makeObject creates object with property", () => {
		const obj = mod.makeObject("x", 10);
		expect(obj).toEqual({ x: 10 });
	});
});
```

- [ ] **Step 2: Build and run tests**

Run: `zig build build-lib:example_js_dsl && npx vitest run examples/js_dsl/mod.test.ts`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add examples/js_dsl/mod.test.ts
git commit -m "test(js): add comprehensive DSL integration tests for all types"
```

---

## Chunk 2: Rewrite README

### Task 3: Rewrite README.md with DSL-first structure

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Rewrite README.md**

Replace the entire README. The structure is:

**Section 1 — Header:**
```markdown
# zapi

A Zig N-API wrapper library and CLI for building and publishing cross-platform Node.js native addons.

zapi provides two main components:

1. **Zig Library** (`src/`) - Write Node.js native addons in Zig with a high-level DSL that mirrors JavaScript's type system
2. **CLI Tool** (`ts/`) - Build tooling for cross-compiling and publishing multi-platform npm packages
```

**Section 2 — Installation:** Copy the existing Installation section from the current README verbatim (lines 14-28).

**Section 3 — Quick Start:** Use this exact code:
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

Then show JS usage:
```js
const mod = require('./my_module.node');
mod.add(1, 2); // 3
const c = new mod.Counter(0);
c.increment();
c.getCount(); // 1
```

**Section 4 — JS Types Reference:** Use the exact table from the spec (spec lines 72-84).

**Section 5 — Functions:** Three subsections with code examples:
- "Basic" — `pub fn add(a: Number, b: Number) Number`
- "Error Handling" — `pub fn safeDivide(a: Number, b: Number) !Number` with `if (divisor == 0) return error.DivisionByZero`
- "Nullable Returns" — `pub fn findValue(arr: Array, target: Number) ?Number` showing the return-null-for-undefined pattern

**Section 6 — Classes:** Show the pattern with a brief Counter example, then document the method resolution rules:
- `pub const js_class = true` — marker
- `pub fn init(...)` — constructor (must return `T` or `!T`)
- `pub fn method(self: *T, ...)` — mutable instance method
- `pub fn method(self: T, ...)` — immutable instance method
- `pub fn method(...)` — static method (no self)
- `pub fn deinit(self: *T)` — optional GC destructor

**Section 7 — Working with Types:** Four subsections:
- "Typed Objects" — `Object(Config)` example with struct definition
- "TypedArrays" — `Uint8Array`/`Float64Array` example
- "Promises" — `Promise(T)` with resolve/reject
- "Callbacks" — accepting `Function` and calling it

**Section 8 — Mixing DSL and N-API:** Show `js.env()` to access low-level Env:
```zig
pub fn advanced() !Value {
    const e = js.env();
    const obj = try e.createObject();
    // use low-level N-API methods...
    return .{ .val = obj };
}
```

**Section 9 — Advanced: Low-Level N-API:** Move the following sections from the current README under an "Advanced: Low-Level N-API" heading, preserving their content exactly:
- "Core Types" table (current lines 56-69)
- "Creating Functions" — Manual Style + Automatic Conversion + Argument Hints (current lines 70-116)
- "Creating Classes" (current lines 118-138)
- "Async Work" (current lines 140-166)
- "Thread-Safe Functions" (current lines 168-186)
- "Error Handling" (current lines 188-201)

Prefix this section with a note: "The DSL layer above handles most use cases. Drop down to the N-API layer when you need full control over handle scopes, async work, thread-safe functions, or other advanced features."

**Section 10 — CLI Tool:** Copy the entire CLI section from the current README verbatim (lines 205-365).

**Section 11 — Example + License:**
```markdown
## Examples

See the [examples/](examples/) directory for comprehensive examples including:
- All DSL types (Number, String, Boolean, BigInt, Date, Array, Object, TypedArrays, Promise)
- Error handling and nullable returns
- Classes with lifecycle management
- Callbacks and mixed DSL/N-API usage
- Low-level N-API with manual registration

## License

MIT
```

- [ ] **Step 2: Review the README renders correctly**

Run: `head -100 README.md` to spot-check formatting.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: restructure README with DSL-first documentation"
```

---

## Dependency Notes

- Task 1 and Task 2 are tightly coupled (examples + tests) but Task 1 must complete first (build must succeed before tests can run).
- Task 3 (README) is independent of Tasks 1-2 but benefits from having the examples finalized first so README snippets are verified.
