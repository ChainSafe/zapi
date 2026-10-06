import {spawn} from "node:child_process";
import {promises as fs} from "node:fs";
import {join} from "node:path";
import {type ParseArgsOptionsConfig, parseArgs} from "node:util";
import {type Config, type Preset, loadConfig, resolvePreset} from "./config.js";
import {type Optimize, type Target, getZigTriple, validateOptimize, validateTarget} from "./lib.js";
import {logDetail, logInfo, logSuccess} from "./log.js";

export type BuildOptions = {
  target: Target;
  optimize?: Optimize;
  zigCwd: string;
  step: string;
  /** Extra `zig build` args, e.g. a preset's `-D` options */
  extraArgs?: string[];
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

  args.push(...(opts.extraArgs ?? []));

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

export function resolveStep(config: Config, step?: string): string {
  const resolved = step ?? config.step;
  if (!resolved) {
    throw new Error("--step is required (or set zapi.step in package.json)");
  }
  return resolved;
}

export type BuildLocalOptions = {
  config: Config;
  preset: Preset;
  target: Target;
  optimize?: Optimize;
  zigCwd: string;
  step?: string;
};

/**
 * Build one preset into `zig-out/lib` and give it the preset's file name, which is where
 * `requireNapiLibrary` looks for a local build of that preset.
 */
export async function buildLocal(opts: BuildLocalOptions): Promise<void> {
  await build({
    extraArgs: opts.preset.args,
    optimize: opts.optimize,
    step: resolveStep(opts.config, opts.step),
    target: opts.target,
    zigCwd: opts.zigCwd,
  });

  const libDir = join(opts.zigCwd, "zig-out", "lib");
  const built = join(libDir, `${opts.config.binaryName}.node`);
  const wanted = join(libDir, opts.preset.file);
  if (built !== wanted) {
    await fs.rename(built, wanted);
    logDetail(`Renamed to ${wanted}`);
  }
}

const buildCliOptions = {
  optimize: {
    type: "string",
  },
  preset: {
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
  const target = validateTarget(values.target as string | undefined);
  const optimize = validateOptimize(values.optimize as string | undefined);
  const preset = resolvePreset(config, values.preset as string | undefined);

  await buildLocal({
    config,
    optimize,
    preset,
    step: values.step as string | undefined,
    target,
    zigCwd: values["zig-cwd"],
  });
}
