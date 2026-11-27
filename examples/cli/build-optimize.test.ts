import {EventEmitter} from "node:events";
import {beforeEach, expect, test, vi} from "vitest";
import {build} from "../../ts/build.js";
import {Optimize} from "../../ts/lib.js";

const {spawn} = vi.hoisted(() => ({spawn: vi.fn()}));
vi.mock("node:child_process", () => ({spawn}));

beforeEach(() => {
  spawn.mockReset();
  spawn.mockImplementation(() => {
    const child = new EventEmitter();
    queueMicrotask(() => child.emit("close", 0));
    return child;
  });
});

test.each([
  [Optimize.Debug, "debug"],
  [Optimize.ReleaseSafe, "safe"],
  [Optimize.ReleaseFast, "fast"],
  [Optimize.ReleaseSmall, "small"],
])("passes Zig 0.17 optimization tags for %s", async (optimize, tag) => {
  await build({target: "aarch64-apple-darwin", optimize, zigCwd: ".", step: "build-lib:addon", quiet: true});
  expect(spawn).toHaveBeenCalledWith(
    "zig",
    ["build", "build-lib:addon", "-Dtarget=aarch64-macos-none", `-Doptimize=${tag}`],
    {cwd: ".", stdio: "inherit"}
  );
});

test("passes a per-target cache via the environment instead of the removed Zig flag", async () => {
  const globalCacheDir = "/tmp/zapi-cache";
  await build({target: "aarch64-apple-darwin", globalCacheDir, zigCwd: ".", step: "build-lib:addon", quiet: true});
  const [, args, options] = spawn.mock.calls[0];
  expect(args).toEqual(["build", "build-lib:addon", "-Dtarget=aarch64-macos-none"]);
  expect(options.env).toEqual({...process.env, ZIG_GLOBAL_CACHE_DIR: globalCacheDir});
});
