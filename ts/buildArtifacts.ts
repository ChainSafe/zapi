import {promises as fs} from "node:fs";
import {join} from "node:path";
import {type ParseArgsOptionsConfig, parseArgs} from "node:util";
import {build} from "./build.js";
import {loadConfig} from "./config.js";
import {type Target, validateOptimize} from "./lib.js";
import {logDetail, logInfo, logStep, logSuccess} from "./log.js";

const buildArtifactsCliOptions = {
  "artifacts-dir": {
    default: "artifacts",
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
};

export async function moveArtifact(opts: MoveArtifactOpts): Promise<void> {
  const destDir = join(opts.artifactsDir, opts.target);
  await fs.mkdir(destDir, {recursive: true});
  await fs.rename(
    join(opts.zigCwd, "zig-out", "lib", `${opts.binaryName}.node`),
    join(destDir, `${opts.binaryName}.node`)
  );
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
  const total = config.targets.length;

  logInfo(`Building ${config.binaryName} for ${total} target(s)...`);

  for (let i = 0; i < config.targets.length; i++) {
    const target = config.targets[i];
    logStep(i + 1, total, `Building for ${target}...`);

    await build({
      optimize,
      quiet: true,
      step,
      target,
      zigCwd: values["zig-cwd"],
    });

    logDetail(`Moving artifact to ${join(values["artifacts-dir"], target)}`);
    await moveArtifact({
      artifactsDir: values["artifacts-dir"],
      binaryName: config.binaryName,
      target,
      zigCwd: values["zig-cwd"],
    });
  }

  logSuccess(`Built ${total} artifact(s) to ${values["artifacts-dir"]}/`);
}
