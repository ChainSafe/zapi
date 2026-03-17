import {promises as fs} from "node:fs";
import {availableParallelism} from "node:os";
import {join} from "node:path";
import {type ParseArgsOptionsConfig, parseArgs} from "node:util";
import {build} from "./build.js";
import {loadConfig} from "./config.js";
import {type Target, parsePositiveIntOption, runWithConcurrency, validateOptimize} from "./lib.js";
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
  buildPrefix?: string;
};

export async function moveArtifact(opts: MoveArtifactOpts): Promise<void> {
  const destDir = join(opts.artifactsDir, opts.target);
  await fs.mkdir(destDir, {recursive: true});

  const outputLibDir = opts.buildPrefix ? join(opts.buildPrefix, "lib") : join(opts.zigCwd, "zig-out", "lib");

  await fs.rename(join(outputLibDir, `${opts.binaryName}.node`), join(destDir, `${opts.binaryName}.node`));
}

export async function buildArtifactsCli(): Promise<void> {
  const {values} = parseArgs({
    allowPositionals: true,
    options: buildArtifactsCliOptions,
  });

  const optimize = validateOptimize(values.optimize as string | undefined);

  const {config} = await loadConfig();
  const step = values.step ?? config.step;
  if (!step) {
    throw new Error("--step is required (or set zapi.step in package.json)");
  }

  const concurrency = parsePositiveIntOption(
    "concurrency",
    values.concurrency as string | undefined,
    Number(defaultConcurrency)
  );
  const total = config.targets.length;
  const artifactsDir = values["artifacts-dir"];
  const buildRoot = join(artifactsDir, ".zapi-build");

  logInfo(`Building ${config.binaryName} for ${total} target(s) with concurrency ${concurrency}...`);

  await runWithConcurrency(config.targets, concurrency, async (target, index) => {
    const targetBuildDir = join(buildRoot, target);
    const prefix = join(targetBuildDir, "prefix");
    const cacheDir = join(targetBuildDir, "cache");
    const globalCacheDir = join(targetBuildDir, "global-cache");

    logStep(index + 1, total, `Building for ${target}...`);

    await build({
      cacheDir,
      globalCacheDir,
      optimize,
      prefix,
      quiet: true,
      step,
      target,
      zigCwd: values["zig-cwd"],
    });

    logDetail(`Moving artifact to ${join(artifactsDir, target)}`);
    await moveArtifact({
      artifactsDir,
      binaryName: config.binaryName,
      buildPrefix: prefix,
      target,
      zigCwd: values["zig-cwd"],
    });
  });

  logSuccess(`Built ${total} artifact(s) to ${artifactsDir}/`);
}
