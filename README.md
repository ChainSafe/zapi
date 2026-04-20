# zapi

A Zig N-API wrapper library and CLI for building and publishing cross-platform Node.js native addons.

zapi provides two main components:

1. **Zig Library** (`src/`) - Write Node.js native addons in Zig with a high-level DSL that mirrors JavaScript's type system
2. **CLI Tool** (`ts/`) - Build tooling for cross-compiling and publishing multi-platform npm packages

## Installation

```bash
npm install -D @chainsafe/zapi
```

Add the Zig dependency to your `build.zig.zon`:

```zig
.dependencies = .{
    .zapi = .{
        .url = "https://github.com/chainsafe/zapi/archive/<commit>.tar.gz",
        .hash = "...",
    },
},
```

---

## Zig Library — Quick Start

The DSL is the default approach for writing native addons. Import `js` from zapi and write normal Zig functions — zapi handles all the N-API marshalling automatically.

```zig
const js = @import("zapi").js;

pub fn add(a: js.Number, b: js.Number) !js.Number {
    return js.Number.from(try a.toI32() + try b.toI32());
}

pub const Counter = struct {
    pub const js_meta = js.class(.{
        .properties = .{
            .count = js.prop(.{ .get = true, .set = false }),
        },
    });

    _count: i32,

    pub fn init(start: js.Number) !Counter {
        return .{ ._count = try start.toI32() };
    }

    pub fn increment(self: *Counter) void {
        self._count += 1;
    }

    // Getter: obj.count (not obj.count())
    pub fn count(self: Counter) js.Number {
        return js.Number.from(self._count);
    }
};

comptime { js.exportModule(@This(), .{}); }
```

**JavaScript usage:**

```js
const mod = require('./my_module.node');
mod.add(1, 2); // 3
const c = new mod.Counter(0);
c.increment();
c.count; // 1 (getter, not a method call)
```

`pub` functions are auto-exported, and structs with `js_meta = js.class(...)` become JS classes. One line — `comptime { js.exportModule(@This(), .{}); }` — registers everything.

---

## JS Types Reference

| Type | JS Equivalent | Key Methods |
|------|--------------|-------------|
| `Number` | `number` | `toI32()`, `toF64()`, `assertI32()`, `from(anytype)` |
| `String` | `string` | `toSlice(buf)`, `toOwnedSlice(alloc)`, `len()`, `from([]const u8)` |
| `Boolean` | `boolean` | `toBool()`, `assertBool()`, `from(bool)` |
| `BigInt` | `bigint` | `toI64()`, `toU64()`, `toI128()`, `from(anytype)` |
| `Date` | `Date` | `toTimestamp()`, `from(f64)` |
| `Array` | `Array` | `get(i)`, `getNumber(i)`, `length()`, `set(i, val)` |
| `Object(T)` | `object` | `get()`, `set(value)` — `T` fields must be DSL types |
| `Function` | `Function` | `call(args)` |
| `Value` | `any` | `isNumber()`, `asNumber()`, type checking/narrowing |
| `Uint8Array` etc. | `TypedArray` | `toSlice()`, `from(slice)` |
| `Promise(T)` | `Promise` | `resolve(value)`, `reject(err)` |

---

## Functions

Three patterns for exporting functions:

### Basic — direct mapping

```zig
pub fn add(a: Number, b: Number) !Number {
    return Number.from(try a.toI32() + try b.toI32());
}
```

### Error handling — `!T` becomes a thrown JS exception

```zig
pub fn safeDivide(a: Number, b: Number) !Number {
    const divisor = try b.toI32();
    if (divisor == 0) return error.DivisionByZero;
    return Number.from(@divTrunc(try a.toI32(), divisor));
}
```

JS: `try { safeDivide(10, 0) } catch (e) { /* "DivisionByZero" */ }`

### Nullable returns — `?T` becomes `undefined`

```zig
pub fn findValue(arr: Array, target: Number) ?Number {
    const len = arr.length() catch return null;
    // ... search, return null if not found
}
```

---

## Classes

Structs with `js_meta = js.class(...)` are exported as JavaScript classes:

```zig
pub const Timer = struct {
    pub const js_meta = js.class(.{});
    start: i64,

    pub fn init() Timer {
        return .{ .start = std.time.milliTimestamp() };
    }

    pub fn elapsed(self: Timer) js.Number {
        return js.Number.from(std.time.milliTimestamp() - self.start);
    }

    pub fn reset(self: *Timer) void {
        self.start = std.time.milliTimestamp();
    }

    pub fn deinit(self: *Timer) void {
        _ = self;
    }
};
```

**Method classification:**

| Signature | JS Behavior |
|-----------|-------------|
| `pub fn init(...)` | Constructor (`new Class(...)`) — must return `T` or `!T` |
| `pub fn method(self: T, ...)` | Immutable instance method |
| `pub fn method(self: *T, ...)` | Mutable instance method |
| `pub fn method(self: T, ...) !T` | Instance method returning a new JS instance |
| `pub fn method(...) !T` | Static method returning a new JS instance |
| `pub fn method(...)` | Static method (no self, returns non-T) |
| `pub fn deinit(self: *T)` | Optional GC destructor |

Methods or functions that return the class type automatically materialize a fresh JS instance. There is no separate author-facing "factory" marker:

```zig
pub const PublicKey = struct {
    pub const js_meta = js.class(.{});
    pk: bls.PublicKey,

    pub fn init() PublicKey {
        return .{ .pk = undefined };
    }

    // Static factory: PublicKey.fromBytes(bytes)
    pub fn fromBytes(bytes: js.Uint8Array) !PublicKey {
        const slice = try bytes.toSlice();
        return .{ .pk = try bls.PublicKey.deserialize(slice) };
    }
};
```

JS: `const pk = PublicKey.fromBytes(bytes);`

Same-class instance methods also work:

```zig
pub fn clone(self: MyState) !MyState {
    const cloned = try self.data.clone();
    return .{ .data = cloned };
}
```

JS: `const newState = state.clone();` — returns a new instance, original unchanged.

### Optional Parameters

Parameters with optional DSL types (`?js.Number`, `?js.Boolean`, etc.) become optional JS arguments:

```zig
pub fn fromBytes(bytes: js.Uint8Array, validate: ?js.Boolean) !PublicKey {
    const do_validate = if (validate) |v| try v.toBool() else false;
    // ...
}
```

JS: `PublicKey.fromBytes(bytes)` or `PublicKey.fromBytes(bytes, true)`

### Getters and Setters

Declare properties inside `js_meta` with `js.prop` to register property accessors:

```zig
pub const Config = struct {
    pub const js_meta = js.class(.{
        .properties = .{
            .volume = js.prop(.{ .get = true, .set = true }),
            .muted = js.prop(.{ .get = true, .set = true }),
            .label = js.prop(.{ .get = true, .set = false }),
        },
    });

    _volume: i32,
    _muted: bool,
    _label: []const u8,

    pub fn init() Config {
        return .{ ._volume = 50, ._muted = false, ._label = "default" };
    }

    // Read-write: obj.volume / obj.volume = 80
    pub fn volume(self: Config) js.Number {
        return js.Number.from(self._volume);
    }
    pub fn setVolume(self: *Config, value: js.Number) !void {
        const v = try value.toI32();
        if (v < 0 or v > 100) return error.VolumeOutOfRange;
        self._volume = v;
    }

    // Read-only: obj.label
    pub fn label(self: Config) js.String {
        return js.String.from(self._label);
    }
};
```

JS: `cfg.volume = 80; cfg.label; // "default"`

**Rules:**
- `pub const js_meta = js.class(.{})` marks a struct as a JS class
- `.properties = .{ .name = js.prop(.{ .get = true, .set = false }) }` registers a readonly getter backed by `pub fn name(...)`
- `.properties = .{ .name = js.prop(.{ .get = true, .set = true }) }` registers getter/setter methods using `name` and `setName`
- `.properties = .{ .name = js.prop(.{ .get = "customGetter", .set = false }) }` registers a getter backed by a specifically named method
- Accessor backing methods are not exported as callable JS methods

---

## Working with Types

### Typed Objects

```zig
const Config = struct { host: String, port: Number, verbose: Boolean };

pub fn connect(config: Object(Config)) !String {
    const c = try config.get();
    // access c.host, c.port, c.verbose
}
```

### TypedArrays

```zig
pub fn sum(data: Uint8Array) !Number {
    const slice = try data.toSlice();
    var total: i32 = 0;
    for (slice) |byte| total += @intCast(byte);
    return Number.from(total);
}
```

### Promises

```zig
pub fn asyncOp(val: Number) !Promise(Number) {
    var promise = try js.createPromise(Number);
    try promise.resolve(val);  // must resolve or reject before returning
    return promise;
}
```

`Promise(T)` in this DSL path is synchronous-only: resolve or reject it before the exported function returns. For truly asynchronous completion, keep the `Deferred` handle in lower-level N-API code and bridge back with `napi.AsyncWork` or `napi.ThreadSafeFunction`.

### Callbacks

```zig
pub fn applyCallback(val: Number, cb: Function) !Value {
    return try cb.call(.{val});
}
```

---

## Namespaces

Import Zig modules as `pub const` to create JS namespaces. The DSL recursively registers all DSL-compatible declarations:

```zig
// root.zig
pub const math = @import("math.zig");     // → exports.math.multiply(...)
pub const crypto = @import("crypto.zig"); // → exports.crypto.PublicKey, etc.

comptime { js.exportModule(@This(), .{}); }
```

Namespaces nest arbitrarily — a sub-module with more `pub const` imports creates deeper nesting.

---

## Module Lifecycle

`exportModule` accepts optional lifecycle hooks with atomic env refcounting:

```zig
comptime {
    js.exportModule(@This(), .{
        .init = fn (refcount: u32) !void,    // called before registration (0 = first env)
        .cleanup = fn (refcount: u32) void,  // called on env exit (0 = last env)
    });
}
```

This enables safe shared-state initialization for worker thread scenarios.

---

## Mixing DSL and N-API

```zig
pub fn advanced() !Value {
    const e = js.env();      // access low-level napi.Env
    const obj = try e.createObject();
    // use any napi.Env method...
    return .{ .val = obj };
}
```

**Context accessors:**

| Function | Description |
|----------|-------------|
| `js.env()` | Current N-API environment (thread-local, set by DSL callbacks) |
| `js.allocator()` | C allocator for native allocations |
| `js.thisArg()` | JS `this` value (available inside instance methods/getters/setters) |

---

## Advanced: Low-Level N-API

The DSL layer handles most use cases. Drop down to the N-API layer when you need full control over handle scopes, async work, thread-safe functions, or other advanced features.

### Core Types

| Type | Description |
|------|-------------|
| `Env` | The N-API environment, provides methods to create values, throw errors, manage scopes |
| `Value` | A JavaScript value handle with methods for type checking, property access, conversions |
| `CallbackInfo` | Provides access to function arguments and `this` binding |
| `HandleScope` | Prevents garbage collection of values within a scope |
| `EscapableHandleScope` | Like HandleScope but allows one value to escape |
| `Ref` | A persistent reference to a value that survives garbage collection |
| `Deferred` | Resolver/rejecter for promises |
| `AsyncWork` | Run work on a thread pool with completion callback on main thread |
| `ThreadSafeFunction` | Call JavaScript from any thread safely |
| `AsyncContext` | Context for async resource tracking |

### Creating Functions

#### Manual Style

Full control using raw `Env` and `Value`:

```zig
fn add_manual(env: napi.Env, info: napi.CallbackInfo(2)) !napi.Value {
    const a = try info.arg(0).getValueInt32();
    const b = try info.arg(1).getValueInt32();
    return try env.createInt32(a + b);
}
```

#### Automatic Conversion with `createCallback`

Let zapi handle argument/return conversion:

```zig
const napi = @import("zapi").napi;

// Arguments and return value are automatically converted
fn add(a: i32, b: i32) i32 {
    return a + b;
}

// Register with automatic wrapping
try env.createFunction("add", 2, napi.createCallback(2, add, .{}), null);
```

#### Argument Hints

Control how arguments are converted:

```zig
napi.createCallback(2, myFunc, .{
    .args = .{ .env, .auto, .value, .data, .string, .buffer },
    .returns = .value,  // or .string, .buffer, .auto
});
```

| Hint | Description |
|------|-------------|
| `.auto` | Automatic type conversion |
| `.env` | Inject `napi.Env` |
| `.value` | Pass raw `napi.Value` |
| `.data` | User data pointer passed to createFunction |
| `.string` | Convert to/from `[]const u8` |
| `.buffer` | Convert to/from byte slice |

### Creating Classes

```zig
const napi = @import("zapi").napi;

const Timer = struct {
    start: i64,

    pub fn read(self: *Timer) i64 {
        return std.time.milliTimestamp() - self.start;
    }
};

try env.defineClass(
    "Timer",
    0,
    timerConstructor,
    null,
    &[_]napi.c.napi_property_descriptor{
        .{ .utf8name = "read", .method = napi.wrapCallback(0, Timer.read) },
    },
);
```

### Async Work (Thread Pool)

Run CPU-intensive work off the main thread:

```zig
const napi = @import("zapi").napi;

const Work = struct {
    a: i32,
    b: i32,
    result: i32,
    deferred: napi.Deferred,
};

fn execute(env: napi.Env, data: *Work) void {
    // Runs on thread pool - don't call JS here!
    data.result = data.a + data.b;
}

fn complete(env: napi.Env, status: napi.status.Status, data: *Work) void {
    // Back on main thread - resolve the promise
    const result = env.createInt32(data.result) catch return;
    data.deferred.resolve(result) catch return;
}

// Create async work
const work = try napi.AsyncWork(Work).create(env, null, name, execute, complete, &data);
try work.queue();
```

### Thread-Safe Functions

Call JavaScript from any thread:

```zig
const napi = @import("zapi").napi;

const tsfn = try env.createThreadsafeFunction(
    jsCallback,        // JS function to call
    context,           // User context
    "name",
    0,                 // Max queue size (0 = unlimited)
    1,                 // Initial thread count
    null,              // Finalize data
    null,              // Finalize callback
    myCallJsCallback,  // Called on main thread
);

// From any thread:
try tsfn.call(&data, .blocking);
```

### Error Handling

All N-API calls return `NapiError` on failure:

```zig
const napi = @import("zapi").napi;

fn myFunction(env: napi.Env) !void {
    // Errors propagate naturally
    const value = try env.createStringUtf8("hello");

    // Throw JavaScript errors
    try env.throwError("ERR_CODE", "Something went wrong");
    try env.throwTypeError("ERR_TYPE", "Expected a number");
}
```

---

## CLI Tool

### Configuration

Add a `zapi` field to your `package.json`:

```json
{
  "name": "my-addon",
  "zapi": {
    "binaryName": "my-addon",
    "step": "my-lib",
    "targets": [
      "x86_64-unknown-linux-gnu",
      "x86_64-unknown-linux-musl",
      "aarch64-unknown-linux-gnu",
      "x86_64-apple-darwin",
      "aarch64-apple-darwin",
      "x86_64-pc-windows-msvc"
    ]
  }
}
```

### Supported Targets

| Target | Platform | Arch | ABI |
|--------|----------|------|-----|
| `aarch64-apple-darwin` | macOS | arm64 | - |
| `x86_64-apple-darwin` | macOS | x64 | - |
| `aarch64-unknown-linux-gnu` | Linux | arm64 | glibc |
| `x86_64-unknown-linux-gnu` | Linux | x64 | glibc |
| `x86_64-unknown-linux-musl` | Linux | x64 | musl |
| `x86_64-pc-windows-msvc` | Windows | x64 | msvc |

### Global Options

| Option | Description |
|--------|-------------|
| `--help`, `-h` | Show help message |
| `--version`, `-v` | Show version number |

### Commands

#### `zapi build`

Build for a single target platform.

```bash
zapi build [options]
```

| Option | Description | Default |
|--------|-------------|---------|
| `--step` | Zig build step | `zapi.step` from package.json |
| `--target` | Target triple | Current platform |
| `--optimize` | `Debug`, `ReleaseSafe`, `ReleaseFast`, `ReleaseSmall` | - |
| `--zig-cwd` | Working directory for zig build | `.` |

#### `zapi build-artifacts`

Build for all configured targets and collect artifacts.

```bash
zapi build-artifacts [options]
```

| Option | Description | Default |
|--------|-------------|---------|
| `--step` | Zig build step | `zapi.step` from package.json |
| `--optimize` | Optimization level | - |
| `--zig-cwd` | Working directory for zig build | `.` |
| `--artifacts-dir` | Output directory for artifacts | `artifacts` |

**Example output:**
```
▶ Building my-addon for 6 target(s)...
[1/6] Building for x86_64-unknown-linux-gnu...
  → Moving artifact to artifacts/x86_64-unknown-linux-gnu
[2/6] Building for aarch64-apple-darwin...
  → Moving artifact to artifacts/aarch64-apple-darwin
...
✓ Built 6 artifact(s) to artifacts/
```

#### `zapi prepublish`

Prepare npm packages for publishing:
- Creates `npm/<target>/` directories for each target
- Moves compiled `.node` binaries from artifacts into target packages
- Generates `package.json` for each target package (with correct `os`, `cpu`, `libc`)
- Updates the main `package.json` with `optionalDependencies`

```bash
zapi prepublish [options]
```

| Option | Description | Default |
|--------|-------------|---------|
| `--artifacts-dir` | Directory containing built artifacts | `artifacts` |
| `--npm-dir` | Directory for npm packages | `npm` |

**Example output:**
```
▶ Preparing my-addon@1.0.0 for publishing...
▶ Moving artifacts to npm packages...
  → x86_64-unknown-linux-gnu → npm/x86_64-unknown-linux-gnu/my-addon.node
▶ Generating target package.json files...
  → Created npm/x86_64-unknown-linux-gnu/package.json
▶ Updating package.json with optionalDependencies...
✓ Prepared 6 target package(s) in npm/
```

#### `zapi publish`

Publish all target-specific packages and the main package to npm.

```bash
zapi publish [options] [-- <npm-args>]
```

| Option | Description | Default |
|--------|-------------|---------|
| `--npm-dir` | Directory containing npm packages | `npm` |
| `--dry-run` | Preview what would be published without publishing | `false` |

Any arguments after `--` are passed directly to `npm publish` (e.g., `--access public`, `--tag beta`).

**Example dry-run:**
```bash
zapi publish --dry-run
```
```
▶ [DRY RUN] Would publish 6 target package(s) + main package
  → Extra npm args: (none)
[1/7] Would publish x86_64-unknown-linux-gnu
  → Directory: /path/to/npm/x86_64-unknown-linux-gnu
...
✓ [DRY RUN] 7 package(s) would be published
```

### Release Workflow

```bash
# 1. Build for all targets
zapi build-artifacts --optimize ReleaseFast

# 2. Prepare npm packages
zapi prepublish

# 3. Preview what will be published
zapi publish --dry-run

# 4. Publish to npm
zapi publish -- --access public
```

### Error Handling

Set `DEBUG=1` for full stack traces on errors.

---

## Runtime Loading

### `requireNapiLibrary(packageDir)`

Load the native addon, automatically selecting the correct binary for the current platform:

```typescript
import { requireNapiLibrary } from "@chainsafe/zapi";
import { fileURLToPath } from "node:url";
import { dirname } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const addon = requireNapiLibrary(__dirname);
```

Resolution order:
1. Local build: `zig-out/lib/<binaryName>.node`
2. Published package: `<pkg-name>-<target>`

---

## Examples

See the [examples/](examples/) directory for comprehensive examples including:
- All DSL types (Number, String, Boolean, BigInt, Date, Array, Object, TypedArrays, Promise)
- Error handling and nullable returns
- Classes with static factories, instance factories, and optional parameters
- Computed getters and setters
- Nested namespaces
- Module lifecycle hooks (init/cleanup with worker thread refcounting)
- Callbacks and mixed DSL/N-API usage
- Low-level N-API with manual registration

## License

MIT
