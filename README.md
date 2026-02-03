# zapi

A Zig N-API wrapper library and CLI for building and publishing cross-platform Node.js native addons.

## Overview

zapi provides two main components:

1. **Zig Library** (`src/`) - Idiomatic Zig bindings for the Node.js N-API, making it easy to write native addons in Zig
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

## Zig Library

### Quick Start

```zig
const napi = @import("napi");

comptime {
    napi.module.register(initModule);
}

fn initModule(env: napi.Env, module: napi.Value) !void {
    // Export a string
    try module.setNamedProperty("greeting", try env.createStringUtf8("Hello from Zig!"));
    
    // Export a function
    try module.setNamedProperty("add", try env.createFunction("add", 2, napi.createCallback(2, add, .{}), null));
}

fn add(a: i32, b: i32) i32 {
    return a + b;
}
```

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

## Example

See the [example/](example/) directory for a comprehensive example including:
- String properties
- Functions with manual and automatic argument handling
- Classes with methods
- Async work with promises
- Thread-safe functions

```bash
# Build the example
zig build

# Test it
node example/test.js
```

## License

MIT

