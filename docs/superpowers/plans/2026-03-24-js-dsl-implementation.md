# JS DSL Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a high-level DSL layer (`zapi.js`) with JS-aligned wrapper types and comptime auto-export, on top of the existing N-API bindings.

**Architecture:** Zero-cost wrapper types over `napi.Value` accessed via `@import("zapi").js`. Thread-local `Env` set by a single comptime-generated callback wrapper. `exportModule(@This())` scans pub decls to auto-register functions and classes. Existing low-level API stays untouched under `@import("zapi").napi` with backwards-compatible flat re-exports.

**Tech Stack:** Zig (comptime metaprogramming), Node.js N-API, Vitest (JS integration tests)

---

## File Structure

```
src/
├── root.zig              (MODIFY — add js/napi namespaces + backwards compat)
├── napi.zig              (CREATE — renamed from current root.zig contents)
├── js.zig                (CREATE — DSL entry point: re-exports all js types + env/allocator/exportModule)
├── js/
│   ├── context.zig       (CREATE — thread-local env, allocator, env()/allocator() accessors)
│   ├── number.zig        (CREATE — Number wrapper type)
│   ├── string.zig        (CREATE — String wrapper type)
│   ├── boolean.zig       (CREATE — Boolean wrapper type)
│   ├── bigint.zig        (CREATE — BigInt wrapper type)
│   ├── date.zig          (CREATE — Date wrapper type)
│   ├── array.zig         (CREATE — Array wrapper type)
│   ├── object.zig        (CREATE — Object(T) generic wrapper)
│   ├── function.zig      (CREATE — Function wrapper type)
│   ├── typed_arrays.zig  (CREATE — all TypedArray wrapper types)
│   ├── promise.zig       (CREATE — Promise(T) wrapper type)
│   ├── value.zig         (CREATE — Value untyped escape hatch)
│   ├── wrap_function.zig (CREATE — comptime wrapFunction: converts DSL fn → napi callback)
│   ├── export_module.zig (CREATE — comptime exportModule: scans pub decls, generates registration)
│   └── wrap_class.zig    (CREATE — comptime class wrapping: constructor, methods, finalizer)
examples/
│   └── js_dsl/
│       ├── mod.zig       (CREATE — DSL example module)
│       └── mod.test.ts   (CREATE — JS integration tests for DSL example)
build.zig                 (MODIFY — add js_dsl example module + import)
```

---

## Chunk 1: Foundation — Namespace Restructure, Context, and Primitive Types

### Task 1: Restructure root.zig into namespaces

**Files:**
- Create: `src/napi.zig`
- Modify: `src/root.zig`

- [ ] **Step 1: Create src/napi.zig with current root.zig contents**

Copy the entire contents of `src/root.zig` into `src/napi.zig`. This becomes the low-level namespace.

```zig
// src/napi.zig — this is the existing root.zig contents, unchanged
const std = @import("std");

pub const c = @import("c.zig");
pub const AsyncContext = @import("AsyncContext.zig");
pub const Env = @import("Env.zig");
pub const Value = @import("Value.zig");
pub const Deferred = @import("Deferred.zig");
pub const EscapableHandleScope = @import("EscapableHandleScope.zig");
pub const HandleScope = @import("HandleScope.zig");
pub const NodeVersion = @import("NodeVersion.zig");
pub const status = @import("status.zig");
pub const module = @import("module.zig");
pub const CallbackInfo = @import("callback_info.zig").CallbackInfo;
pub const Callback = @import("callback.zig").Callback;
pub const value_types = @import("value_types.zig");

pub const createCallback = @import("create_callback.zig").createCallback;
pub const registerDecls = @import("register_decls.zig").registerDecls;
pub const wrapFinalizeCallback = @import("finalize_callback.zig").wrapFinalizeCallback;
pub const wrapCallback = @import("callback.zig").wrapCallback;

pub const AsyncWork = @import("async_work.zig").AsyncWork;
pub const ThreadSafeFunction = @import("threadsafe_function.zig").ThreadSafeFunction;
pub const CallMode = @import("threadsafe_function.zig").CallMode;
pub const ReleaseMode = @import("threadsafe_function.zig").ReleaseMode;

test {
    @import("std").testing.refAllDecls(@This());
}
```

- [ ] **Step 2: Rewrite src/root.zig with namespace re-exports**

```zig
// src/root.zig
const std = @import("std");

/// Low-level N-API bindings.
pub const napi = @import("napi.zig");

/// High-level JS-aligned DSL layer.
pub const js = @import("js.zig");

/// Backwards-compatible flat re-exports (deprecated, will be removed).
pub usingnamespace @import("napi.zig");

test {
    std.testing.refAllDecls(@This());
}
```

- [ ] **Step 3: Run existing tests to verify backwards compatibility**

Run: `zig build test`
Expected: All existing tests pass — nothing broken by the restructure.

- [ ] **Step 4: Commit**

```bash
git add src/root.zig src/napi.zig
git commit -m "refactor: restructure root.zig into napi/js namespaces with backwards compat"
```

---

### Task 2: Create js context — thread-local env and allocator

**Files:**
- Create: `src/js/context.zig`

- [ ] **Step 1: Write inline test for context**

```zig
// src/js/context.zig
const std = @import("std");
const napi = @import("../napi.zig");

threadlocal var current_env: ?napi.Env = null;

/// Get the current N-API environment. Only valid inside a JS callback context.
/// Not safe to call from AsyncWork execute callbacks or other non-JS threads.
pub fn env() napi.Env {
    return current_env orelse @panic("js.env() called outside of a JS callback context");
}

/// Returns std.heap.c_allocator, backed by the C allocator (malloc/free).
pub fn allocator() std.mem.Allocator {
    return std.heap.c_allocator;
}

/// Set the current env. Called by wrapFunction before invoking user code.
/// Returns the previous env for restoration via defer.
pub fn setEnv(e: napi.Env) ?napi.Env {
    const prev = current_env;
    current_env = e;
    return prev;
}

/// Restore a previous env. Called via defer after user code returns.
pub fn restoreEnv(prev: ?napi.Env) void {
    current_env = prev;
}

test "allocator returns c_allocator" {
    const alloc = allocator();
    const mem = try alloc.alloc(u8, 16);
    defer alloc.free(mem);
    try std.testing.expect(mem.len == 16);
}

test "current_env is null by default" {
    // In test context (no Node.js), current_env should be null
    try std.testing.expect(current_env == null);
}

test "restoreEnv with null preserves null state" {
    restoreEnv(null);
    try std.testing.expect(current_env == null);
}
```

Note: Full env round-trip tests require a running Node.js environment. The unit tests here verify the allocator and null-state behavior. Real env testing happens in the integration test (Task 10).

- [ ] **Step 2: Run test to verify**

Run: `zig build test`
Expected: PASS (context tests compile and pass)

- [ ] **Step 3: Commit**

```bash
git add src/js/context.zig
git commit -m "feat(js): add thread-local env and allocator context"
```

---

### Task 3: Create Number type

**Files:**
- Create: `src/js/number.zig`

- [ ] **Step 1: Write Number wrapper**

```zig
// src/js/number.zig
const std = @import("std");
const napi = @import("../napi.zig");
const context = @import("context.zig");

pub const Number = struct {
    val: napi.Value,

    // --- Narrowing (returns error on overflow/type mismatch) ---

    pub fn toI32(self: Number) !i32 {
        return self.val.getValueInt32();
    }

    pub fn toU32(self: Number) !u32 {
        return self.val.getValueUint32();
    }

    pub fn toF64(self: Number) !f64 {
        return self.val.getValueDouble();
    }

    pub fn toI64(self: Number) !i64 {
        return self.val.getValueInt64();
    }

    // --- Assertion (panics on failure) ---

    pub fn assertI32(self: Number) i32 {
        return self.toI32() catch @panic("Number.assertI32 failed");
    }

    pub fn assertU32(self: Number) u32 {
        return self.toU32() catch @panic("Number.assertU32 failed");
    }

    pub fn assertF64(self: Number) f64 {
        return self.toF64() catch @panic("Number.assertF64 failed");
    }

    pub fn assertI64(self: Number) i64 {
        return self.toI64() catch @panic("Number.assertI64 failed");
    }

    // --- Construction ---
    // Accepts integer types (i8..i64, u8..u64), float types (f32, f64),
    // and comptime_int/comptime_float. Does not accept u128/i128/f128.

    pub fn from(value: anytype) Number {
        const e = context.env();
        const T = @TypeOf(value);
        const val = switch (@typeInfo(T)) {
            .int, .comptime_int => blk: {
                // Try i32 first (most common JS number path), fall back to i64, then f64
                if (@typeInfo(T) == .comptime_int) {
                    if (value >= std.math.minInt(i32) and value <= std.math.maxInt(i32)) {
                        break :blk e.createInt32(@intCast(value)) catch @panic("Number.from: createInt32 failed");
                    } else if (value >= std.math.minInt(i64) and value <= std.math.maxInt(i64)) {
                        break :blk e.createInt64(@intCast(value)) catch @panic("Number.from: createInt64 failed");
                    } else {
                        @compileError("Number.from: value out of range for JS number. Use BigInt for i128/u128.");
                    }
                } else {
                    const info = @typeInfo(T).int;
                    if (info.bits <= 32 and info.signedness == .signed) {
                        break :blk e.createInt32(@intCast(value)) catch @panic("Number.from: createInt32 failed");
                    } else if (info.bits <= 32 and info.signedness == .unsigned) {
                        break :blk e.createUint32(@intCast(value)) catch @panic("Number.from: createUint32 failed");
                    } else if (info.bits <= 64) {
                        break :blk e.createInt64(@intCast(value)) catch @panic("Number.from: createInt64 failed");
                    } else {
                        @compileError("Number.from: integer too large for JS number. Use BigInt for i128/u128.");
                    }
                }
            },
            .float, .comptime_float => blk: {
                break :blk e.createDouble(@floatCast(value)) catch @panic("Number.from: createDouble failed");
            },
            else => @compileError("Number.from: unsupported type " ++ @typeName(T) ++ ". Use integer or float types."),
        };
        return .{ .val = val };
    }

    /// Get the underlying napi.Value.
    pub fn toValue(self: Number) napi.Value {
        return self.val;
    }
};
```

- [ ] **Step 2: Run zig build to verify it compiles**

Run: `zig build test`
Expected: Compiles (Number type is valid Zig). Real behavior tested in integration test.

- [ ] **Step 3: Commit**

```bash
git add src/js/number.zig
git commit -m "feat(js): add Number zero-cost wrapper type"
```

---

### Task 4: Create Boolean type

**Files:**
- Create: `src/js/boolean.zig`

- [ ] **Step 1: Write Boolean wrapper**

```zig
// src/js/boolean.zig
const napi = @import("../napi.zig");
const context = @import("context.zig");

pub const Boolean = struct {
    val: napi.Value,

    pub fn toBool(self: Boolean) !bool {
        return self.val.getValueBool();
    }

    pub fn assertBool(self: Boolean) bool {
        return self.toBool() catch @panic("Boolean.assertBool failed");
    }

    pub fn from(value: bool) Boolean {
        const e = context.env();
        const val = e.getBoolean(value) catch @panic("Boolean.from failed");
        return .{ .val = val };
    }

    pub fn toValue(self: Boolean) napi.Value {
        return self.val;
    }
};
```

- [ ] **Step 2: Commit**

```bash
git add src/js/boolean.zig
git commit -m "feat(js): add Boolean zero-cost wrapper type"
```

---

### Task 5: Create String type

**Files:**
- Create: `src/js/string.zig`

- [ ] **Step 1: Write String wrapper**

```zig
// src/js/string.zig
const std = @import("std");
const napi = @import("../napi.zig");
const context = @import("context.zig");

pub const String = struct {
    val: napi.Value,

    /// Copies string into caller-provided buffer.
    /// Returns error if buf is smaller than the string (BufferTooSmall mapped from napi error).
    /// Use len() to check size first.
    pub fn toSlice(self: String, buf: []u8) ![]const u8 {
        return self.val.getValueStringUtf8(buf);
    }

    /// Allocates a new slice with the string contents.
    pub fn toOwnedSlice(self: String, alloc: std.mem.Allocator) ![]const u8 {
        // First get the length
        const str_len = try self.len();
        // Allocate buffer (+1 for null terminator that N-API writes)
        const buf = try alloc.alloc(u8, str_len + 1);
        errdefer alloc.free(buf);
        const result = try self.val.getValueStringUtf8(buf);
        // Shrink to exact size (N-API returns without null terminator in the slice)
        if (result.len < buf.len) {
            // Return a slice of the allocated buffer
            return buf[0..result.len];
        }
        return result;
    }

    /// Returns the UTF-8 byte length of the string.
    pub fn len(self: String) !usize {
        // N-API: pass a zero-length buffer to get just the length
        // getValueStringUtf8 with empty buf returns the string length via napi
        // We need to call the raw C API for length-only query
        var str_len: usize = 0;
        const status_code = napi.c.napi_get_value_string_utf8(
            self.val.env,
            self.val.value,
            null,
            0,
            &str_len,
        );
        try napi.status.check(status_code);
        return str_len;
    }

    pub fn from(value: []const u8) String {
        const e = context.env();
        const val = e.createStringUtf8(value) catch @panic("String.from failed");
        return .{ .val = val };
    }

    pub fn toValue(self: String) napi.Value {
        return self.val;
    }
};
```

- [ ] **Step 2: Commit**

```bash
git add src/js/string.zig
git commit -m "feat(js): add String zero-cost wrapper type"
```

---

### Task 6: Create BigInt and Date types

**Files:**
- Create: `src/js/bigint.zig`
- Create: `src/js/date.zig`

- [ ] **Step 1: Write BigInt wrapper**

```zig
// src/js/bigint.zig
const std = @import("std");
const napi = @import("../napi.zig");
const context = @import("context.zig");

pub const BigInt = struct {
    val: napi.Value,

    pub fn toI64(self: BigInt) !i64 {
        return self.val.getValueBigintInt64(null);
    }

    pub fn toU64(self: BigInt) !u64 {
        return self.val.getValueBigintUint64(null);
    }

    pub fn toI128(self: BigInt) !i128 {
        var sign_bit: u1 = 0;
        var words: [2]u64 = .{ 0, 0 };
        const result = try self.val.getValueBigintWords(&sign_bit, &words);
        const low: i128 = @intCast(result[0]);
        const high: i128 = if (result.len > 1) @intCast(result[1]) else 0;
        const magnitude = low | (high << 64);
        return if (sign_bit == 1) -magnitude else magnitude;
    }

    /// Accepts i64, u64, i128, u128, comptime_int.
    pub fn from(value: anytype) BigInt {
        const e = context.env();
        const T = @TypeOf(value);
        const val = switch (@typeInfo(T)) {
            .int, .comptime_int => blk: {
                const info = if (@typeInfo(T) == .comptime_int) null else @typeInfo(T).int;
                if (info == null or (info.?.bits <= 64 and info.?.signedness == .signed)) {
                    break :blk e.createBigintInt64(@intCast(value)) catch @panic("BigInt.from: createBigintInt64 failed");
                } else if (info.?.bits <= 64 and info.?.signedness == .unsigned) {
                    break :blk e.createBigintUint64(@intCast(value)) catch @panic("BigInt.from: createBigintUint64 failed");
                } else {
                    // i128/u128: use words API
                    const magnitude: u128 = if (value < 0) @intCast(-value) else @intCast(value);
                    const low: u64 = @truncate(magnitude);
                    const high: u64 = @truncate(magnitude >> 64);
                    const sign: u1 = if (value < 0) 1 else 0;
                    const words = if (high != 0) &[_]u64{ low, high } else &[_]u64{low};
                    break :blk e.createBigintWords(sign, words) catch @panic("BigInt.from: createBigintWords failed");
                }
            },
            else => @compileError("BigInt.from: unsupported type " ++ @typeName(T)),
        };
        return .{ .val = val };
    }

    pub fn toValue(self: BigInt) napi.Value {
        return self.val;
    }
};
```

- [ ] **Step 2: Write Date wrapper**

```zig
// src/js/date.zig
const napi = @import("../napi.zig");
const context = @import("context.zig");

pub const Date = struct {
    val: napi.Value,

    /// Returns milliseconds since epoch.
    pub fn toTimestamp(self: Date) !f64 {
        return self.val.getDateValue();
    }

    pub fn assertTimestamp(self: Date) f64 {
        return self.toTimestamp() catch @panic("Date.assertTimestamp failed");
    }

    /// Create a Date from milliseconds since epoch.
    pub fn from(timestamp: f64) Date {
        const e = context.env();
        const val = e.createDate(timestamp) catch @panic("Date.from failed");
        return .{ .val = val };
    }

    pub fn toValue(self: Date) napi.Value {
        return self.val;
    }
};
```

- [ ] **Step 3: Commit**

```bash
git add src/js/bigint.zig src/js/date.zig
git commit -m "feat(js): add BigInt and Date zero-cost wrapper types"
```

---

### Task 7: Create js.zig entry point and verify compilation

**Files:**
- Create: `src/js.zig`

- [ ] **Step 1: Write js.zig that re-exports all types**

```zig
// src/js.zig — DSL entry point
const context = @import("js/context.zig");

// Core context accessors
pub const env = context.env;
pub const allocator = context.allocator;

// Primitive types
pub const Number = @import("js/number.zig").Number;
pub const String = @import("js/string.zig").String;
pub const Boolean = @import("js/boolean.zig").Boolean;
pub const BigInt = @import("js/bigint.zig").BigInt;
pub const Date = @import("js/date.zig").Date;

// Complex types (added in Chunk 2)
// pub const Array = @import("js/array.zig").Array;
// pub const Object = @import("js/object.zig").Object;
// pub const Function = @import("js/function.zig").Function;
// pub const Value = @import("js/value.zig").Value;

// TypedArrays (added in Chunk 2)
// pub const typed_arrays = @import("js/typed_arrays.zig");

// Promise (added in Chunk 2)
// pub const Promise = @import("js/promise.zig").Promise;
// pub const createPromise = @import("js/promise.zig").createPromise;

// Module export (added in Chunk 3)
// pub const exportModule = @import("js/export_module.zig").exportModule;

test {
    @import("std").testing.refAllDecls(@This());
}
```

- [ ] **Step 2: Run zig build test to verify everything compiles together**

Run: `zig build test`
Expected: All tests pass — new js module compiles, existing tests still work.

- [ ] **Step 3: Commit**

```bash
git add src/js.zig
git commit -m "feat(js): add js.zig entry point re-exporting primitive types"
```

---

## Chunk 2: Complex Types — Array, Object(T), Function, TypedArrays, Promise, Value

### Task 8: Create Array type

**Files:**
- Create: `src/js/array.zig`

- [ ] **Step 1: Write Array wrapper**

```zig
// src/js/array.zig
const napi = @import("../napi.zig");
const context = @import("context.zig");
const Number = @import("number.zig").Number;
const String = @import("string.zig").String;
const Boolean = @import("boolean.zig").Boolean;

pub const Array = struct {
    val: napi.Value,

    /// Get element at index as untyped Value.
    pub fn get(self: Array, index: u32) !@import("value.zig").Value {
        const element = try self.val.getElement(index);
        return .{ .val = element };
    }

    /// Get element at index as Number.
    pub fn getNumber(self: Array, index: u32) !Number {
        const element = try self.val.getElement(index);
        return .{ .val = element };
    }

    /// Get element at index as String.
    pub fn getString(self: Array, index: u32) !String {
        const element = try self.val.getElement(index);
        return .{ .val = element };
    }

    /// Get element at index as Boolean.
    pub fn getBoolean(self: Array, index: u32) !Boolean {
        const element = try self.val.getElement(index);
        return .{ .val = element };
    }

    /// Returns the array length.
    pub fn length(self: Array) !u32 {
        return self.val.getArrayLength();
    }

    /// Set element at index.
    pub fn set(self: Array, index: u32, value: anytype) !void {
        const T = @TypeOf(value);
        // If it has a .val field (it's a DSL wrapper), extract the napi.Value
        if (@hasField(T, "val")) {
            try self.val.setElement(index, value.val);
        } else if (T == napi.Value) {
            try self.val.setElement(index, value);
        } else {
            @compileError("Array.set: unsupported value type " ++ @typeName(T));
        }
    }

    pub fn toValue(self: Array) napi.Value {
        return self.val;
    }
};
```

- [ ] **Step 2: Commit**

```bash
git add src/js/array.zig
git commit -m "feat(js): add Array zero-cost wrapper type"
```

---

### Task 9: Create Object(T) type

**Files:**
- Create: `src/js/object.zig`

- [ ] **Step 1: Write Object(T) wrapper with comptime field accessors**

```zig
// src/js/object.zig
const std = @import("std");
const napi = @import("../napi.zig");
const context = @import("context.zig");

/// Generic typed Object wrapper. T must be a struct whose fields are DSL types
/// (Number, String, Boolean, etc.). Generates per-field get/set accessors at comptime.
pub fn Object(comptime T: type) type {
    const fields = @typeInfo(T).@"struct".fields;

    return struct {
        val: napi.Value,

        const Self = @This();

        /// Extract all fields into a Zig struct at once.
        pub fn get(self: Self) !T {
            var result: T = undefined;
            inline for (fields) |field| {
                const prop = try self.val.getNamedProperty(field.name ++ "");
                @field(result, field.name) = .{ .val = prop };
            }
            return result;
        }

        /// Set all fields from a Zig struct at once.
        pub fn set(self: Self, value: T) !void {
            inline for (fields) |field| {
                const field_val = @field(value, field.name);
                try self.val.setNamedProperty(field.name ++ "", field_val.val);
            }
        }

        /// Convert field name to PascalCase for accessor names.
        fn pascalCase(comptime name: []const u8) []const u8 {
            if (name.len == 0) return name;
            var result: [name.len]u8 = undefined;
            result[0] = std.ascii.toUpper(name[0]);
            for (name[1..], 1..) |ch, i| {
                result[i] = ch;
            }
            return &result;
        }

        // Generate per-field typed getter/setter accessors at comptime.
        // For a field "host: String", generates:
        //   pub fn getHost(self) !String
        //   pub fn setHost(self, value: String) !void

        pub usingnamespace blk: {
            var decls = struct {};
            inline for (fields) |field| {
                const pascal = pascalCase(field.name);

                // Getter: get<FieldName>
                const getter_name = "get" ++ pascal;
                const FieldType = field.type;
                decls = @Type(.{ .@"struct" = .{
                    .layout = .auto,
                    .fields = &.{},
                    .decls = @typeInfo(@TypeOf(decls)).@"struct".decls ++ &.{.{
                        .name = getter_name,
                        .val = struct {
                            fn func(self: Self) !FieldType {
                                const prop = try self.val.getNamedProperty(field.name ++ "");
                                return .{ .val = prop };
                            }
                        }.func,
                    }},
                    .is_tuple = false,
                } });
            }
            break :blk decls;
        };

        pub fn toValue(self: Self) napi.Value {
            return self.val;
        }
    };
}
```

Note: The `usingnamespace` approach for per-field accessors is complex. A simpler alternative is to rely on `get()` returning the full struct and let users access fields directly (e.g., `const c = try obj.get(); c.host`). The per-field accessors can be added as a follow-up if needed. For the initial implementation, implement `get()` and `set()` only, and add a comment noting per-field accessors as future work.

**Simplified version (recommended for initial implementation):**

```zig
// src/js/object.zig
const std = @import("std");
const napi = @import("../napi.zig");
const context = @import("context.zig");

pub fn Object(comptime T: type) type {
    const fields = @typeInfo(T).@"struct".fields;

    return struct {
        val: napi.Value,

        const Self = @This();

        /// Extract all fields into a Zig struct at once.
        pub fn get(self: Self) !T {
            var result: T = undefined;
            inline for (fields) |field| {
                const name: [:0]const u8 = field.name ++ "";
                const prop = try self.val.getNamedProperty(name);
                @field(result, field.name) = .{ .val = prop };
            }
            return result;
        }

        /// Set all fields from a Zig struct at once.
        pub fn set(self: Self, value: T) !void {
            inline for (fields) |field| {
                const name: [:0]const u8 = field.name ++ "";
                const field_val = @field(value, field.name);
                try self.val.setNamedProperty(name, field_val.val);
            }
        }

        pub fn toValue(self: Self) napi.Value {
            return self.val;
        }
    };
}
```

- [ ] **Step 2: Commit**

```bash
git add src/js/object.zig
git commit -m "feat(js): add Object(T) comptime-generated typed object wrapper"
```

---

### Task 10: Create Function type

**Files:**
- Create: `src/js/function.zig`

- [ ] **Step 1: Write Function wrapper**

```zig
// src/js/function.zig
const std = @import("std");
const napi = @import("../napi.zig");
const context = @import("context.zig");

pub const Function = struct {
    val: napi.Value,

    /// Call the function with the given arguments.
    /// Arguments must be DSL wrapper types (Number, String, etc.) or napi.Value.
    pub fn call(self: Function, args: anytype) !@import("value.zig").Value {
        const e = context.env();
        const ArgsType = @TypeOf(args);
        const fields = @typeInfo(ArgsType).@"struct".fields;

        var raw_args: [fields.len]napi.c.napi_value = undefined;
        inline for (fields, 0..) |field, i| {
            const arg = @field(args, field.name);
            const ArgT = @TypeOf(arg);
            if (@hasField(ArgT, "val")) {
                raw_args[i] = arg.val.value;
            } else if (ArgT == napi.Value) {
                raw_args[i] = arg.value;
            } else {
                @compileError("Function.call: unsupported argument type " ++ @typeName(ArgT));
            }
        }

        const undefined = try e.getUndefined();
        const result = try e.callFunctionRaw(self.val, undefined, &raw_args);
        return .{ .val = result };
    }

    pub fn toValue(self: Function) napi.Value {
        return self.val;
    }
};
```

- [ ] **Step 2: Commit**

```bash
git add src/js/function.zig
git commit -m "feat(js): add Function zero-cost wrapper type"
```

---

### Task 11: Create TypedArray types

**Files:**
- Create: `src/js/typed_arrays.zig`

- [ ] **Step 1: Write TypedArray wrappers using comptime generation**

```zig
// src/js/typed_arrays.zig
const std = @import("std");
const napi = @import("../napi.zig");
const context = @import("context.zig");

fn TypedArray(comptime Element: type, comptime array_type: napi.value_types.TypedarrayType) type {
    return struct {
        val: napi.Value,

        const Self = @This();

        /// Get a slice view into the typed array's data.
        pub fn toSlice(self: Self) ![]Element {
            const info = try self.val.getTypedarrayInfo();
            const byte_ptr: [*]u8 = @ptrCast(info.data.ptr);
            const elem_ptr: [*]Element = @ptrCast(@alignCast(byte_ptr));
            return elem_ptr[0..info.length];
        }

        /// Create a typed array from a slice. Copies the data.
        pub fn from(data: []const Element) Self {
            const e = context.env();
            const byte_len = data.len * @sizeOf(Element);

            // Create an ArrayBuffer to hold the data
            var buf_ptr: [*]u8 = undefined;
            const arraybuffer = e.createArrayBuffer(byte_len, &buf_ptr) catch
                @panic("TypedArray.from: createArrayBuffer failed");

            // Copy data into the array buffer
            const dest = buf_ptr[0..byte_len];
            const src: []const u8 = std.mem.sliceAsBytes(data);
            @memcpy(dest, src);

            // Create the typed array view
            const val = e.createTypedarray(array_type, data.len, arraybuffer, 0) catch
                @panic("TypedArray.from: createTypedarray failed");

            return .{ .val = val };
        }

        pub fn toValue(self: Self) napi.Value {
            return self.val;
        }
    };
}

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
```

- [ ] **Step 2: Commit**

```bash
git add src/js/typed_arrays.zig
git commit -m "feat(js): add TypedArray zero-cost wrapper types for all variants"
```

---

### Task 12: Create Promise(T) type

**Files:**
- Create: `src/js/promise.zig`

- [ ] **Step 1: Write Promise wrapper**

```zig
// src/js/promise.zig
const napi = @import("../napi.zig");
const context = @import("context.zig");
const String = @import("string.zig").String;

pub fn Promise(comptime T: type) type {
    return struct {
        val: napi.Value,
        deferred: napi.Deferred,

        const Self = @This();

        /// Resolve the promise with a value.
        pub fn resolve(self: Self, value: T) !void {
            try self.deferred.resolve(value.val);
        }

        /// Reject the promise with an error message.
        pub fn reject(self: Self, err: String) !void {
            const e = context.env();
            const error_obj = try e.createError(
                try e.createStringUtf8("Error"),
                err.val,
            );
            try self.deferred.reject(error_obj);
        }

        pub fn toValue(self: Self) napi.Value {
            return self.val;
        }
    };
}

/// Create a new Promise. Returns a typed Promise wrapper.
pub fn createPromise(comptime T: type) !Promise(T) {
    const e = context.env();
    const deferred = try e.createPromise();
    return .{
        .val = deferred.getPromise(),
        .deferred = deferred,
    };
}
```

- [ ] **Step 2: Commit**

```bash
git add src/js/promise.zig
git commit -m "feat(js): add Promise(T) zero-cost wrapper type"
```

---

### Task 13: Create Value (untyped escape hatch)

**Files:**
- Create: `src/js/value.zig`

- [ ] **Step 1: Write Value wrapper**

```zig
// src/js/value.zig
const napi = @import("../napi.zig");
const Number = @import("number.zig").Number;
const String = @import("string.zig").String;
const Boolean = @import("boolean.zig").Boolean;
const BigInt = @import("bigint.zig").BigInt;
const Array = @import("array.zig").Array;
const Function = @import("function.zig").Function;
const Date = @import("date.zig").Date;
const typed_arrays = @import("typed_arrays.zig");

pub const Value = struct {
    val: napi.Value,

    // --- Type checking ---

    pub fn isNumber(self: Value) bool {
        return (self.val.typeof() catch return false) == .number;
    }

    pub fn isString(self: Value) bool {
        return (self.val.typeof() catch return false) == .string;
    }

    pub fn isBigInt(self: Value) bool {
        return (self.val.typeof() catch return false) == .bigint;
    }

    pub fn isBoolean(self: Value) bool {
        return (self.val.typeof() catch return false) == .boolean;
    }

    pub fn isArray(self: Value) bool {
        return self.val.isArray() catch false;
    }

    pub fn isObject(self: Value) bool {
        return (self.val.typeof() catch return false) == .object;
    }

    pub fn isFunction(self: Value) bool {
        return (self.val.typeof() catch return false) == .function;
    }

    pub fn isDate(self: Value) bool {
        return self.val.isDate() catch false;
    }

    pub fn isTypedArray(self: Value) bool {
        return self.val.isTypedarray() catch false;
    }

    pub fn isNull(self: Value) bool {
        return (self.val.typeof() catch return false) == .null;
    }

    pub fn isUndefined(self: Value) bool {
        return (self.val.typeof() catch return false) == .undefined;
    }

    // --- Type narrowing ---

    pub fn asNumber(self: Value) !Number {
        return .{ .val = self.val };
    }

    pub fn asString(self: Value) !String {
        return .{ .val = self.val };
    }

    pub fn asBigInt(self: Value) !BigInt {
        return .{ .val = self.val };
    }

    pub fn asBoolean(self: Value) !Boolean {
        return .{ .val = self.val };
    }

    pub fn asArray(self: Value) !Array {
        return .{ .val = self.val };
    }

    pub fn asObject(self: Value, comptime T: type) !@import("object.zig").Object(T) {
        return .{ .val = self.val };
    }

    pub fn asFunction(self: Value) !Function {
        return .{ .val = self.val };
    }

    pub fn asDate(self: Value) !Date {
        return .{ .val = self.val };
    }

    pub fn asUint8Array(self: Value) !typed_arrays.Uint8Array {
        return .{ .val = self.val };
    }

    pub fn asFloat64Array(self: Value) !typed_arrays.Float64Array {
        return .{ .val = self.val };
    }

    pub fn asInt32Array(self: Value) !typed_arrays.Int32Array {
        return .{ .val = self.val };
    }

    pub fn asUint32Array(self: Value) !typed_arrays.Uint32Array {
        return .{ .val = self.val };
    }

    pub fn asFloat32Array(self: Value) !typed_arrays.Float32Array {
        return .{ .val = self.val };
    }

    pub fn toValue(self: Value) napi.Value {
        return self.val;
    }
};
```

- [ ] **Step 2: Commit**

```bash
git add src/js/value.zig
git commit -m "feat(js): add Value untyped escape hatch type"
```

---

### Task 14: Update js.zig to re-export all types

**Files:**
- Modify: `src/js.zig`

- [ ] **Step 1: Uncomment and add all type re-exports in js.zig**

Replace `src/js.zig` with:

```zig
// src/js.zig — DSL entry point
const context = @import("js/context.zig");

// Core context accessors
pub const env = context.env;
pub const allocator = context.allocator;

// Primitive types
pub const Number = @import("js/number.zig").Number;
pub const String = @import("js/string.zig").String;
pub const Boolean = @import("js/boolean.zig").Boolean;
pub const BigInt = @import("js/bigint.zig").BigInt;
pub const Date = @import("js/date.zig").Date;

// Complex types
pub const Array = @import("js/array.zig").Array;
pub const Object = @import("js/object.zig").Object;
pub const Function = @import("js/function.zig").Function;
pub const Value = @import("js/value.zig").Value;

// TypedArrays
pub const Int8Array = @import("js/typed_arrays.zig").Int8Array;
pub const Uint8Array = @import("js/typed_arrays.zig").Uint8Array;
pub const Uint8ClampedArray = @import("js/typed_arrays.zig").Uint8ClampedArray;
pub const Int16Array = @import("js/typed_arrays.zig").Int16Array;
pub const Uint16Array = @import("js/typed_arrays.zig").Uint16Array;
pub const Int32Array = @import("js/typed_arrays.zig").Int32Array;
pub const Uint32Array = @import("js/typed_arrays.zig").Uint32Array;
pub const Float32Array = @import("js/typed_arrays.zig").Float32Array;
pub const Float64Array = @import("js/typed_arrays.zig").Float64Array;
pub const BigInt64Array = @import("js/typed_arrays.zig").BigInt64Array;
pub const BigUint64Array = @import("js/typed_arrays.zig").BigUint64Array;

// Promise
pub const Promise = @import("js/promise.zig").Promise;
pub const createPromise = @import("js/promise.zig").createPromise;

// Module export (added in Chunk 3)
// pub const exportModule = @import("js/export_module.zig").exportModule;

// Error helpers
pub fn throwError(message: []const u8) void {
    const e = context.env();
    e.throwError("", message) catch {};
}

test {
    @import("std").testing.refAllDecls(@This());
}
```

- [ ] **Step 2: Run zig build test**

Run: `zig build test`
Expected: All tests pass — full type system compiles.

- [ ] **Step 3: Commit**

```bash
git add src/js.zig
git commit -m "feat(js): re-export all DSL types from js.zig entry point"
```

---

## Chunk 3: Comptime Machinery — wrapFunction, wrapClass, exportModule

### Task 15: Create wrapFunction — comptime callback wrapper

**Files:**
- Create: `src/js/wrap_function.zig`

This is the core machinery that converts a DSL-typed Zig function into an N-API callback.

- [ ] **Step 1: Write wrapFunction**

```zig
// src/js/wrap_function.zig
const std = @import("std");
const napi = @import("../napi.zig");
const context = @import("context.zig");

// Import all JS types for type detection
const Number = @import("number.zig").Number;
const String = @import("string.zig").String;
const Boolean = @import("boolean.zig").Boolean;
const BigInt = @import("bigint.zig").BigInt;
const Date = @import("date.zig").Date;
const Array = @import("array.zig").Array;
const Function = @import("function.zig").Function;
const JsValue = @import("value.zig").Value;

/// Check if a type is a JS DSL wrapper type (has .val: napi.Value field).
fn isDslType(comptime T: type) bool {
    if (@typeInfo(T) != .@"struct") return false;
    for (@typeInfo(T).@"struct".fields) |field| {
        if (std.mem.eql(u8, field.name, "val") and field.type == napi.Value) return true;
    }
    return false;
}

/// Check if T is Object(SomeStruct) — a comptime-generated generic.
fn isObjectType(comptime T: type) bool {
    return isDslType(T) and @hasDecl(T, "get") and @hasDecl(T, "set");
}

/// Check if T is Promise(SomeType).
fn isPromiseType(comptime T: type) bool {
    if (@typeInfo(T) != .@"struct") return false;
    var has_val = false;
    var has_deferred = false;
    for (@typeInfo(T).@"struct".fields) |field| {
        if (std.mem.eql(u8, field.name, "val") and field.type == napi.Value) has_val = true;
        if (std.mem.eql(u8, field.name, "deferred")) has_deferred = true;
    }
    return has_val and has_deferred;
}

/// Convert a napi.Value argument to the expected DSL type at the given parameter position.
pub fn convertArg(comptime T: type, raw_val: napi.Value) T {
    // All DSL types are just wrappers around napi.Value
    if (isDslType(T)) {
        return .{ .val = raw_val };
    }
    @compileError("wrapFunction: unsupported parameter type " ++ @typeName(T) ++
        ". Function parameters must be JS DSL types (Number, String, Boolean, etc.).");
}

/// Convert a DSL return value to napi.Value, handling error unions and optionals.
pub fn convertReturn(comptime T: type, value: T, e: napi.Env) napi.c.napi_value {
    if (isDslType(T)) {
        return value.val.value;
    } else if (T == void) {
        return (e.getUndefined() catch unreachable).value;
    }
    @compileError("wrapFunction: unsupported return type " ++ @typeName(T));
}

/// Generate a raw N-API C callback from a DSL-typed Zig function.
/// Returns napi.c.napi_callback for use with raw C APIs (napi_create_function, napi_define_class).
/// We bypass Env.createFunction (which expects Callback(argc)) and call C APIs directly.
pub fn wrapFunction(comptime func: anytype) napi.c.napi_callback {
    const FnType = @TypeOf(func);
    const fn_info = @typeInfo(FnType).@"fn";
    const params = fn_info.params;
    const ReturnType = fn_info.return_type.?;

    return struct {
        fn callback(raw_env: napi.c.napi_env, raw_info: napi.c.napi_callback_info) callconv(.c) napi.c.napi_value {
            // Set up thread-local env
            const napi_env = napi.Env{ .env = raw_env };
            const prev = context.setEnv(napi_env);
            defer context.restoreEnv(prev);

            // Extract arguments from callback info
            var argc: usize = params.len;
            var argv: [if (params.len > 0) params.len else 1]napi.c.napi_value = undefined;
            var this_arg: napi.c.napi_value = undefined;

            if (params.len > 0) {
                napi.status.check(napi.c.napi_get_cb_info(
                    raw_env,
                    raw_info,
                    &argc,
                    &argv,
                    &this_arg,
                    null,
                )) catch {
                    napi_env.throwError("", "Failed to get callback info") catch {};
                    return null;
                };
            }

            // Build argument tuple
            var args: std.meta.ArgsTuple(FnType) = undefined;
            inline for (params, 0..) |param, i| {
                const ParamType = param.type.?;
                const raw_val = napi.Value{ .env = raw_env, .value = argv[i] };
                args[i] = convertArg(ParamType, raw_val);
            }

            // Call user function and handle return type
            return callAndConvert(func, args, napi_env, ReturnType);
        }
    }.callback;
}

pub fn callAndConvert(
    comptime func: anytype,
    args: std.meta.ArgsTuple(@TypeOf(func)),
    e: napi.Env,
    comptime ReturnType: type,
) napi.c.napi_value {
    // Determine the unwrapped return type (strip error union, then optional)
    const is_error_union = @typeInfo(ReturnType) == .error_union;
    const AfterError = if (is_error_union) @typeInfo(ReturnType).error_union.payload else ReturnType;
    const is_optional = @typeInfo(AfterError) == .optional;
    const InnerType = if (is_optional) @typeInfo(AfterError).optional.child else AfterError;

    if (is_error_union) {
        const result = @call(.auto, func, args) catch |err| {
            // Convert Zig error to JS exception
            const err_name = @errorName(err);
            e.throwError("", err_name) catch {};
            return null;
        };

        if (is_optional) {
            // !?T — error already handled above, now handle null → undefined
            if (result) |val| {
                return convertReturn(InnerType, val, e);
            } else {
                return (e.getUndefined() catch unreachable).value;
            }
        } else {
            return convertReturn(AfterError, result, e);
        }
    } else if (is_optional) {
        // ?T — no error union, just optional
        const result = @call(.auto, func, args);
        if (result) |val| {
            return convertReturn(InnerType, val, e);
        } else {
            return (e.getUndefined() catch unreachable).value;
        }
    } else {
        // Plain T — no error, no optional
        const result = @call(.auto, func, args);
        return convertReturn(ReturnType, result, e);
    }
}
```

- [ ] **Step 2: Run zig build test**

Run: `zig build test`
Expected: Compiles. Full behavior tested in integration test.

- [ ] **Step 3: Commit**

```bash
git add src/js/wrap_function.zig
git commit -m "feat(js): add comptime wrapFunction for DSL fn → napi callback conversion"
```

---

### Task 16: Create wrapClass — comptime class generation

**Files:**
- Create: `src/js/wrap_class.zig`

- [ ] **Step 1: Write wrapClass**

```zig
// src/js/wrap_class.zig
const std = @import("std");
const napi = @import("../napi.zig");
const context = @import("context.zig");
const wrap_function = @import("wrap_function.zig");

/// Generate N-API class definition from a Zig struct with js_class = true.
/// Produces a constructor callback and property descriptors for methods.
pub fn wrapClass(comptime T: type) type {
    // Validate: must have js_class = true
    if (!@hasDecl(T, "js_class") or !T.js_class) {
        @compileError("wrapClass: type " ++ @typeName(T) ++ " must have `pub const js_class = true;`");
    }

    // Validate: must have init
    if (!@hasDecl(T, "init")) {
        @compileError("wrapClass: type " ++ @typeName(T) ++ " must have a `pub fn init(...)` constructor.");
    }

    return struct {
        /// The N-API constructor callback.
        pub const constructor = struct {
            fn callback(raw_env: napi.c.napi_env, raw_info: napi.c.napi_callback_info) callconv(.c) napi.c.napi_value {
                const napi_env = napi.Env{ .env = raw_env };
                const prev = context.setEnv(napi_env);
                defer context.restoreEnv(prev);

                // Get this_arg and arguments
                const init_fn = T.init;
                const FnType = @TypeOf(init_fn);
                const fn_info = @typeInfo(FnType).@"fn";
                const params = fn_info.params;

                var argc: usize = params.len;
                var argv: [if (params.len > 0) params.len else 1]napi.c.napi_value = undefined;
                var this_arg: napi.c.napi_value = undefined;

                napi.status.check(napi.c.napi_get_cb_info(
                    raw_env,
                    raw_info,
                    &argc,
                    &argv,
                    &this_arg,
                    null,
                )) catch {
                    napi_env.throwError("", "Failed to get constructor callback info") catch {};
                    return null;
                };

                // Build init args
                var args: std.meta.ArgsTuple(FnType) = undefined;
                inline for (params, 0..) |param, i| {
                    const raw_val = napi.Value{ .env = raw_env, .value = argv[i] };
                    args[i] = wrap_function.convertArg(param.type.?, raw_val);
                }

                // Call init — may return T or !T
                const ReturnType = fn_info.return_type.?;
                const instance = if (@typeInfo(ReturnType) == .error_union)
                    @call(.auto, init_fn, args) catch |err| {
                        napi_env.throwError("", @errorName(err)) catch {};
                        return null;
                    }
                else
                    @call(.auto, init_fn, args);

                // Allocate and store native data
                const alloc = std.heap.c_allocator;
                const native = alloc.create(T) catch {
                    napi_env.throwError("", "Failed to allocate native instance") catch {};
                    return null;
                };
                native.* = instance;

                // Wrap native data onto JS object
                const this_val = napi.Value{ .env = raw_env, .value = this_arg };
                const finalize_cb = if (@hasDecl(T, "deinit")) &wrapDeinit else &defaultFinalize;
                _ = napi_env.wrap(this_val, T, native, finalize_cb, null) catch {
                    alloc.destroy(native);
                    napi_env.throwError("", "Failed to wrap native object") catch {};
                    return null;
                };

                return this_arg;
            }
        }.callback;

        fn defaultFinalize(_: napi.Env, native: *T, _: ?*anyopaque) void {
            std.heap.c_allocator.destroy(native);
        }

        fn wrapDeinit(_: napi.Env, native: *T, _: ?*anyopaque) void {
            if (@hasDecl(T, "deinit")) {
                native.deinit();
            }
            std.heap.c_allocator.destroy(native);
        }

        /// Generate property descriptors for all instance and static methods.
        pub fn getPropertyDescriptors() []const napi.c.napi_property_descriptor {
            comptime {
                const decls = @typeInfo(T).@"struct".decls;
                var props: []const napi.c.napi_property_descriptor = &.{};

                for (decls) |decl| {
                    // Skip non-method decls
                    if (std.mem.eql(u8, decl.name, "js_class")) continue;
                    if (std.mem.eql(u8, decl.name, "init")) continue;
                    if (std.mem.eql(u8, decl.name, "deinit")) continue;

                    const field = @field(T, decl.name);
                    const FieldType = @TypeOf(field);
                    if (@typeInfo(FieldType) != .@"fn") continue;

                    const fn_params = @typeInfo(FieldType).@"fn".params;
                    const is_instance = fn_params.len > 0 and
                        (fn_params[0].type.? == *T or fn_params[0].type.? == T);

                    if (is_instance) {
                        props = props ++ &[_]napi.c.napi_property_descriptor{.{
                            .utf8name = decl.name ++ "",
                            .method = wrapMethod(T, field, fn_params[0].type.? == *T),
                        }};
                    } else {
                        // Static method
                        props = props ++ &[_]napi.c.napi_property_descriptor{.{
                            .utf8name = decl.name ++ "",
                            .method = wrap_function.wrapFunction(field),
                            .attributes = @intFromEnum(napi.value_types.PropertyAttributes.static),
                        }};
                    }
                }

                return props;
            }
        }

        fn wrapMethod(comptime Class: type, comptime method: anytype, comptime is_mutable: bool) napi.c.napi_callback {
            const FnType = @TypeOf(method);
            const fn_info = @typeInfo(FnType).@"fn";
            const params = fn_info.params;
            const ReturnType = fn_info.return_type.?;

            return struct {
                fn callback(raw_env: napi.c.napi_env, raw_info: napi.c.napi_callback_info) callconv(.c) napi.c.napi_value {
                    const napi_env = napi.Env{ .env = raw_env };
                    const prev_env = context.setEnv(napi_env);
                    defer context.restoreEnv(prev_env);

                    // Extract args and this
                    const method_argc = params.len - 1; // exclude self
                    var argc: usize = method_argc;
                    var argv: [if (method_argc > 0) method_argc else 1]napi.c.napi_value = undefined;
                    var this_arg: napi.c.napi_value = undefined;

                    napi.status.check(napi.c.napi_get_cb_info(
                        raw_env,
                        raw_info,
                        &argc,
                        &argv,
                        &this_arg,
                        null,
                    )) catch {
                        napi_env.throwError("", "Failed to get method callback info") catch {};
                        return null;
                    };

                    // Unwrap self
                    const this_val = napi.Value{ .env = raw_env, .value = this_arg };
                    const self_ptr = napi_env.unwrap(Class, this_val) catch {
                        napi_env.throwTypeError("", "Failed to unwrap native object") catch {};
                        return null;
                    };

                    // Build args tuple (self + remaining params)
                    var args: std.meta.ArgsTuple(FnType) = undefined;
                    if (is_mutable) {
                        args[0] = self_ptr;
                    } else {
                        args[0] = self_ptr.*;
                    }

                    inline for (params[1..], 0..) |param, i| {
                        const raw_val = napi.Value{ .env = raw_env, .value = argv[i] };
                        args[i + 1] = wrap_function.convertArg(param.type.?, raw_val);
                    }

                    return wrap_function.callAndConvert(method, args, napi_env, ReturnType);
                }
            }.callback;
        }
    };
}
```

Note: `convertArg` and `callAndConvert` are declared `pub` in `wrap_function.zig` so `wrap_class.zig` can use them.

- [ ] **Step 2: Run zig build test**

Run: `zig build test`
Expected: Compiles.

- [ ] **Step 3: Commit**

```bash
git add src/js/wrap_class.zig
git commit -m "feat(js): add comptime wrapClass for js_class struct → JS class generation"
```

---

### Task 17: Create exportModule — comptime decl scanner

**Files:**
- Create: `src/js/export_module.zig`

- [ ] **Step 1: Write exportModule**

```zig
// src/js/export_module.zig
const std = @import("std");
const napi = @import("../napi.zig");
const context = @import("context.zig");
const wrap_function = @import("wrap_function.zig");
const wrap_class = @import("wrap_class.zig");

/// Scan all pub declarations in a module and generate N-API registration.
/// Usage: `comptime { js.exportModule(@This()); }`
pub fn exportModule(comptime Module: type) void {
    // Generate the module init function
    const init = struct {
        fn initModule(env: napi.Env, exports: napi.Value) anyerror!void {
            const prev = context.setEnv(env);
            defer context.restoreEnv(prev);

            const decls = @typeInfo(Module).@"struct".decls;

            inline for (decls) |decl| {
                const field = @field(Module, decl.name);
                const FieldType = @TypeOf(field);

                if (@typeInfo(FieldType) == .@"fn") {
                    // It's a function — wrap and register using raw C API
                    // (Env.createFunction expects Callback(N), but we produce napi_callback)
                    const wrapped = wrap_function.wrapFunction(field);
                    const name: [:0]const u8 = decl.name ++ "";
                    var func_val: napi.c.napi_value = undefined;
                    try napi.status.check(napi.c.napi_create_function(
                        env.env,
                        name.ptr,
                        name.len,
                        wrapped,
                        null,
                        &func_val,
                    ));
                    try exports.setNamedProperty(name, napi.Value{ .env = env.env, .value = func_val });
                } else if (@typeInfo(FieldType) == .type) {
                    // It's a type — check if it's a js_class
                    const InnerType = field;
                    if (@hasDecl(InnerType, "js_class") and InnerType.js_class) {
                        const class_wrapper = wrap_class.wrapClass(InnerType);
                        const name: [:0]const u8 = decl.name ++ "";
                        const props = class_wrapper.getPropertyDescriptors();
                        var class_val: napi.c.napi_value = undefined;
                        try napi.status.check(napi.c.napi_define_class(
                            env.env,
                            name.ptr,
                            name.len,
                            class_wrapper.constructor,
                            null,
                            props.len,
                            props.ptr,
                            &class_val,
                        ));
                        try exports.setNamedProperty(name, napi.Value{ .env = env.env, .value = class_val });
                    }
                }
                // Skip other pub consts (e.g., type aliases, config structs)
            }
        }
    }.initModule;

    // Register the module with N-API
    napi.module.register(init);
}
```

- [ ] **Step 2: Update js.zig to export exportModule**

Add to `src/js.zig`:

```zig
// Module export
pub const exportModule = @import("js/export_module.zig").exportModule;
```

Remove the commented-out line.

- [ ] **Step 3: Run zig build test**

Run: `zig build test`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add src/js/export_module.zig src/js.zig
git commit -m "feat(js): add comptime exportModule for automatic pub decl registration"
```

---

## Chunk 4: Integration — Example Module and End-to-End Tests

### Task 18: Create DSL example module

**Files:**
- Create: `examples/js_dsl/mod.zig`

- [ ] **Step 1: Write the example module using the DSL**

```zig
// examples/js_dsl/mod.zig
const js = @import("zapi").js;
const Number = js.Number;
const String = js.String;
const Boolean = js.Boolean;
const Array = js.Array;

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

/// Return undefined for not found.
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

/// Function that always throws.
pub fn willThrow() !Number {
    return error.IntentionalError;
}

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

comptime {
    js.exportModule(@This());
}
```

- [ ] **Step 2: Commit**

```bash
git add examples/js_dsl/mod.zig
git commit -m "feat: add DSL example module demonstrating functions, classes, error handling"
```

---

### Task 19: Add js_dsl example to build.zig

**Files:**
- Modify: `build.zig`

- [ ] **Step 1: Add js_dsl module and library to build.zig**

Add after the `example_type_tag` section (before the `tls_run_test` step), following the same pattern as existing examples:

```zig
    const module_example_js_dsl = b.createModule(.{
        .root_source_file = b.path("examples/js_dsl/mod.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    b.modules.put(b.dupe("example_js_dsl"), module_example_js_dsl) catch @panic("OOM");

    const lib_example_js_dsl = b.addLibrary(.{
        .name = "example_js_dsl",
        .root_module = module_example_js_dsl,
        .linkage = .dynamic,
    });

    lib_example_js_dsl.linker_allow_shlib_undefined = true;
    const install_lib_example_js_dsl = b.addInstallArtifact(lib_example_js_dsl, .{
        .dest_sub_path = "example_js_dsl.node",
    });

    const tls_install_lib_example_js_dsl = b.step("build-lib:example_js_dsl", "Install the example_js_dsl library");
    tls_install_lib_example_js_dsl.dependOn(&install_lib_example_js_dsl.step);
    b.getInstallStep().dependOn(&install_lib_example_js_dsl.step);
```

Also add the import at the bottom with the other imports:

```zig
    module_example_js_dsl.addImport("zapi", module_napi);
```

Note: The import name must be `"zapi"` (not `"napi"`) since the DSL example uses `@import("zapi")`. The `module_napi` module's root source file is `src/root.zig` which now exports both `napi` and `js` namespaces.

- [ ] **Step 2: Build the example to verify compilation**

Run: `zig build build-lib:example_js_dsl`
Expected: Builds successfully, produces `zig-out/lib/example_js_dsl.node`

- [ ] **Step 3: Commit**

```bash
git add build.zig
git commit -m "build: add js_dsl example module to build system"
```

---

### Task 20: Write integration tests

**Files:**
- Create: `examples/js_dsl/mod.test.ts`

- [ ] **Step 1: Write JS integration tests**

```typescript
// examples/js_dsl/mod.test.ts
import { describe, it, expect } from "vitest";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const mod = require("../../zig-out/lib/example_js_dsl.node");

describe("js dsl - functions", () => {
    it("add two numbers", () => {
        expect(mod.add(1, 2)).toEqual(3);
    });

    it("add negative numbers", () => {
        expect(mod.add(-5, 3)).toEqual(-2);
    });

    it("greet returns formatted string", () => {
        expect(mod.greet("World")).toEqual("Hello, World!");
    });

    it("findValue returns index when found", () => {
        expect(mod.findValue([10, 20, 30], 20)).toEqual(1);
    });

    it("findValue returns undefined when not found", () => {
        expect(mod.findValue([10, 20, 30], 99)).toBeUndefined();
    });

    it("willThrow throws an error", () => {
        expect(() => mod.willThrow()).toThrow("IntentionalError");
    });
});

describe("js dsl - Counter class", () => {
    it("creates counter with initial value", () => {
        const c = new mod.Counter(5);
        expect(c.getCount()).toEqual(5);
    });

    it("increments counter", () => {
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
```

- [ ] **Step 2: Build the native module first**

Run: `zig build build-lib:example_js_dsl`
Expected: Builds successfully.

- [ ] **Step 3: Run the integration tests**

Run: `pnpm test examples/js_dsl/mod.test.ts`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add examples/js_dsl/mod.test.ts
git commit -m "test: add integration tests for JS DSL example module"
```

---

### Task 21: Verify all existing tests still pass

- [ ] **Step 1: Run the full test suite**

Run: `zig build test && pnpm test`
Expected: All existing tests pass alongside new ones. No regressions.

- [ ] **Step 2: Final commit if any fixes were needed**

Only if changes were required to fix test failures.

---

## Dependency Notes

- Tasks 1-7 must be sequential (each builds on the previous).
- Tasks 8-13 (complex types) can be worked on in parallel after Task 7.
- Task 14 depends on Tasks 8-13 (re-exports all types).
- Task 15 (wrapFunction) depends on Task 14.
- Task 16 (wrapClass) depends on Task 15.
- Task 17 (exportModule) depends on Tasks 15-16.
- Tasks 18-21 (integration) depend on Task 17.

## Implementation Risks

1. **Zig comptime limitations** — `@typeInfo` on generic types and `usingnamespace` for generated accessors may have edge cases. Keep Object(T) simple initially (get/set only, no per-field accessors).
2. **N-API module name** — The `build.zig` import name must match what the example uses in `@import`. Currently examples import `"napi"`, the DSL example needs `"zapi"`. May need a module alias or rename.
3. **Error name extraction** — `@errorName(err)` returns a `[:0]const u8` which must be compatible with `throwError`'s parameter type. Verify at implementation time.
4. **Property descriptor initialization** — `napi.c.napi_property_descriptor` has many fields. Ensure all unset fields are zero-initialized (Zig default for extern structs may vary).
