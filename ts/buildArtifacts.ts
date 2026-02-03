import {parseArgs, type ParseArgsOptionsConfig} from "node:util";
import {type Target, validateOptimize, requireOption} from "./lib.js";
import { promises as fs } from "node:fs";
import { join } from "node:path";
import { build } from "./build.js";
import { loadConfig } from "./config.js";
import { logStep, logDetail, logInfo, logSuccess } from "./log.js";

const buildArtifactsCliOptions = {
  "zig-cwd": {
    type: "string",
    default: ".",
  },
  "artifacts-dir": {
    type: "string",
    default: "artifacts",
  },
  "step": {
    type: "string",
  },
  "optimize": {
    type: "string",
  },
} satisfies ParseArgsOptionsConfig;

type MoveArtifactOpts = {
  zigCwd: string;
  artifactsDir: string;
  target: Target;
  binaryName: string;
};

export async function moveArtifact(opts: MoveArtifactOpts): Promise<void> {
  const destDir = join(opts.artifactsDir, opts.target);
  await fs.mkdir(destDir, { recursive: true });
  await fs.rename(
    join(opts.zigCwd, "zig-out", "lib", `${opts.binaryName}.node`),
    join(destDir, `${opts.binaryName}.node`),
  );
}

export async function buildArtifactsCli(): Promise<void> {
  const {values} = parseArgs({
    options: buildArtifactsCliOptions,
    allowPositionals: true,
  });

  const optimize = validateOptimize(values.optimize as string | undefined);

  const { config } = await loadConfig();
  const step = values.step ?? config.step;
  if (!step) {
    throw new Error("--step is required (or set zapi.step in package.json)");
  }
  const total = config.targets.length;

  logInfo(`Building ${config.binaryName} for ${total} target(s)...`);

  for (let i = 0; i < config.targets.length; i++) {
    const target = config.targets[i];
    logStep(i + 1, total, `Building for ${target}...`);

    await build({
      optimize,
      zigCwd: values["zig-cwd"],
      target,
      step,
      quiet: true,
    });

    logDetail(`Moving artifact to ${join(values["artifacts-dir"], target)}`);
    await moveArtifact({
      zigCwd: values["zig-cwd"],
      artifactsDir: values["artifacts-dir"],
      target,
      binaryName: config.binaryName,
    });
  }

  logSuccess(`Built ${total} artifact(s) to ${values["artifacts-dir"]}/`);
}
