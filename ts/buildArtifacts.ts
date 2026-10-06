import {promises as fs} from "node:fs";
import {availableParallelism} from "node:os";
import {join} from "node:path";
import {type ParseArgsOptionsConfig, parseArgs} from "node:util";
import {build, resolveStep} from "./build.js";
import {type Config, loadConfig} from "./config.js";
import {type Optimize, type Target, parsePositiveIntOption, runWithConcurrency, validateOptimize} from "./lib.js";
import {logDetail, logInfo, logStep, logSuccess} from "./log.js";

const defaultConcurrency = String(Math.max(1, Math.min(availableParallelism(), 4)));

const buildArtifactsCliOptions = {
  "artifacts-dir": {
    default: "artifacts",
    type: "string",
  },
  concurrency: {
    default: defaultConcurrency,
    type: "string",
  },
  optimize: {
    type: "string",
  },
  step: {
    type: "string",
  },
  "zig-cwd": {
    default: ".",
    type: "string",
  },
} satisfies ParseArgsOptionsConfig;

type MoveArtifactOpts = {
  zigCwd: string;
  artifactsDir: string;
  target: Target;
  binaryName: string;
  /** Destination file name inside `artifactsDir/<target>/` */
  file: string;
  buildPrefix?: string;
};

export async function moveArtifact(opts: MoveArtifactOpts): Promise<void> {
  const destDir = join(opts.artifactsDir, opts.target);
  await fs.mkdir(destDir, {recursive: true});

  const outputLibDir = opts.buildPrefix ? join(opts.buildPrefix, "lib") : join(opts.zigCwd, "zig-out", "lib");

  await fs.rename(join(outputLibDir, `${opts.binaryName}.node`), join(destDir, opts.file));
}

export type BuildArtifactsOptions = {
  config: Config;
  step?: string;
  optimize?: Optimize;
  zigCwd: string;
  artifactsDir: string;
  concurrency: number;
};

export async function buildArtifacts(opts: BuildArtifactsOptions): Promise<void> {
  const {config, artifactsDir, zigCwd} = opts;
  const step = resolveStep(config, opts.step);
  const presetCount = config.presets.length;
  const total = config.targets.length * presetCount;
  const buildRoot = join(artifactsDir, ".zapi-build");

  const presetsNote = presetCount > 1 ? ` x ${presetCount} preset(s)` : "";
  logInfo(
    `Building ${config.binaryName} for ${config.targets.length} target(s)${presetsNote} with concurrency ${opts.concurrency}...`
  );

  await runWithConcurrency(config.targets, opts.concurrency, async (target, index) => {
    const targetBuildDir = join(buildRoot, target);
    const prefix = join(targetBuildDir, "prefix");
    const cacheDir = join(targetBuildDir, "cache");
    const globalCacheDir = join(targetBuildDir, "global-cache");

    // Presets share one prefix dir, so each build must be moved out before the next starts.
    for (const [presetIndex, preset] of config.presets.entries()) {
      const presetNote = presetCount > 1 ? ` (${preset.name})` : "";
      logStep(index * presetCount + presetIndex + 1, total, `Building for ${target}${presetNote}...`);

      await build({
        cacheDir,
        extraArgs: preset.args,
        globalCacheDir,
        optimize: opts.optimize,
        prefix,
        quiet: true,
        step,
        target,
        zigCwd,
      });

      logDetail(`Moving artifact to ${join(artifactsDir, target, preset.file)}`);
      await moveArtifact({
        artifactsDir,
        binaryName: config.binaryName,
        buildPrefix: prefix,
        file: preset.file,
        target,
        zigCwd,
      });
    }
  });

  logSuccess(`Built ${total} artifact(s) to ${artifactsDir}/`);
}

export async function buildArtifactsCli(): Promise<void> {
  const {values} = parseArgs({
    allowPositionals: true,
    options: buildArtifactsCliOptions,
  });

  const optimize = validateOptimize(values.optimize as string | undefined);
  const {config} = await loadConfig();
  const concurrency = parsePositiveIntOption(
    "concurrency",
    values.concurrency as string | undefined,
    Number(defaultConcurrency)
  );

  await buildArtifacts({
    artifactsDir: values["artifacts-dir"],
    concurrency,
    config,
    optimize,
    step: values.step as string | undefined,
    zigCwd: values["zig-cwd"],
  });
}
