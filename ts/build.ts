import {spawn} from "node:child_process";
import {type ParseArgsOptionsConfig, parseArgs} from "node:util";
import {loadConfig} from "./config.js";
import {type Optimize, type Target, getZigTriple, validateOptimize, validateTarget} from "./lib.js";
import {logInfo, logSuccess} from "./log.js";

export type BuildOptions = {
  target: Target;
  optimize?: Optimize;
  zigCwd: string;
  step: string;
  prefix?: string;
  cacheDir?: string;
  globalCacheDir?: string;
  /** Skip logging (useful when called from buildArtifacts which has its own logging) */
  quiet?: boolean;
};

export async function build(opts: BuildOptions): Promise<void> {
  const args = ["build", opts.step];

  const triple = getZigTriple(opts.target);
  args.push(`-Dtarget=${triple}`);

  if (opts.optimize) {
    args.push(`-Doptimize=${opts.optimize}`);
  }

  if (opts.prefix) {
    args.push("--prefix", opts.prefix);
  }

  if (opts.cacheDir) {
    args.push("--cache-dir", opts.cacheDir);
  }

  if (opts.globalCacheDir) {
    args.push("--global-cache-dir", opts.globalCacheDir);
  }

  if (!opts.quiet) {
    logInfo(`Building for ${opts.target}...`);
  }

  const exitCode = await new Promise<number | null>((resolve, reject) => {
    const child = spawn("zig", args, {
      cwd: opts.zigCwd,
      stdio: "inherit",
    });

    child.on("error", (err) => {
      reject(new Error(`Failed to spawn zig: ${err.message}`));
    });

    child.on("close", (code) => {
      resolve(code);
    });
  });

  if (exitCode !== 0) {
    throw new Error(`zig build failed with exit code ${exitCode}`);
  }

  if (!opts.quiet) {
    logSuccess(`Build complete for ${opts.target}`);
  }
}

const buildCliOptions = {
  optimize: {
    type: "string",
  },
  step: {
    type: "string",
  },
  target: {
    type: "string",
  },
  "zig-cwd": {
    default: ".",
    type: "string",
  },
} satisfies ParseArgsOptionsConfig;

export async function buildCli(): Promise<void> {
  const {values} = parseArgs({
    allowPositionals: true,
    options: buildCliOptions,
  });

  const {config} = await loadConfig();
  const step = values.step ?? config.step;
  if (!step) {
    throw new Error("--step is required (or set zapi.step in package.json)");
  }
  const target = validateTarget(values.target as string | undefined);
  const optimize = validateOptimize(values.optimize as string | undefined);

  const buildOptions: BuildOptions = {
    optimize,
    step,
    target,
    zigCwd: values["zig-cwd"],
  };

  await build(buildOptions);
}
