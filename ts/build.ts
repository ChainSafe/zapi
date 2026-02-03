import {parseArgs, type ParseArgsOptionsConfig} from "node:util";
import {getZigTriple, Optimize, type Target, validateOptimize, validateTarget, requireOption} from "./lib.js";
import { spawn } from "node:child_process";
import { logInfo, logSuccess } from "./log.js";
import { loadConfig } from "./config.js";

export type BuildOptions = {
  target: Target;
  optimize?: Optimize;
  zigCwd: string;
  step: string;
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
  "zig-cwd": {
    type: "string",
    default: ".",
  },
  "step": {
    type: "string",
  },
  "optimize": {
    type: "string",
  },
  "target": {
    type: "string",
  },
} satisfies ParseArgsOptionsConfig;


export async function buildCli(): Promise<void> {
  const {values} = parseArgs({
    options: buildCliOptions,
    allowPositionals: true,
  });

  const { config } = await loadConfig();
  const step = values.step ?? config.step;
  if (!step) {
    throw new Error("--step is required (or set zapi.step in package.json)");
  }
  const target = validateTarget(values.target as string | undefined);
  const optimize = validateOptimize(values.optimize as string | undefined);

  const buildOptions: BuildOptions = {
    target,
    optimize,
    zigCwd: values["zig-cwd"],
    step,
  };

  await build(buildOptions);
}
