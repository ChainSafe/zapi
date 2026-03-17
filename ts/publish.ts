import {spawn} from "node:child_process";
import {join} from "node:path";
import {type ParseArgsOptionsConfig, parseArgs} from "node:util";
import {loadConfig} from "./config.js";
import {parsePositiveIntOption, runWithConcurrency} from "./lib.js";
import {logDetail, logInfo, logStep, logSuccess} from "./log.js";

const publishOptions = {
  concurrency: {
    default: "1",
    type: "string",
  },
  "dry-run": {
    default: false,
    type: "boolean",
  },
  "npm-dir": {
    default: "npm",
    type: "string",
  },
} satisfies ParseArgsOptionsConfig;

export type PublishOpts = {
  "npm-dir": string;
  "dry-run": boolean;
  concurrency: number;
};

function extraPublishArgs(): string[] {
  const publishIx = process.argv.indexOf("publish");
  // Find where our options end and npm args begin (after --)
  const dashDashIx = process.argv.indexOf("--", publishIx + 1);
  if (dashDashIx !== -1) {
    return process.argv.slice(dashDashIx + 1);
  }
  return [];
}

async function runNpm(args: string[], cwd: string): Promise<void> {
  const exitCode = await new Promise<number | null>((resolve, reject) => {
    const child = spawn("npm", args, {
      cwd,
      env: process.env,
      stdio: "inherit",
    });

    child.on("error", (err) => {
      reject(new Error(`Failed to spawn npm: ${err.message}`));
    });

    child.on("close", (code) => {
      resolve(code);
    });
  });

  if (exitCode !== 0) {
    throw new Error(`npm publish failed with exit code ${exitCode}`);
  }
}

export async function publish(opts: PublishOpts): Promise<void> {
  const extraArgs = extraPublishArgs();
  const publishArgv = ["publish", ...extraArgs];

  const {config} = await loadConfig();
  const total = config.targets.length + 1; // +1 for main package

  if (opts["dry-run"]) {
    logInfo(
      `[DRY RUN] Would publish ${config.targets.length} target package(s) + main package with concurrency ${opts.concurrency}`
    );
    logDetail(`Extra npm args: ${extraArgs.length > 0 ? extraArgs.join(" ") : "(none)"}`);

    for (let i = 0; i < config.targets.length; i++) {
      const target = config.targets[i];
      const cwd = join(process.cwd(), opts["npm-dir"], target);
      logStep(i + 1, total, `Would publish ${target}`);
      logDetail(`Directory: ${cwd}`);
    }

    logStep(total, total, "Would publish main package");
    logDetail(`Directory: ${process.cwd()}`);

    logSuccess(`[DRY RUN] ${total} package(s) would be published`);
    return;
  }

  logInfo(
    `Publishing ${config.targets.length} target package(s) + main package with concurrency ${opts.concurrency}...`
  );

  let started = 0;
  await runWithConcurrency(config.targets, opts.concurrency, async (target) => {
    started += 1;
    logStep(started, total, `Publishing ${target}...`);
    await runNpm(publishArgv, join(process.cwd(), opts["npm-dir"], target));
  });

  logStep(total, total, "Publishing main package...");
  await runNpm(publishArgv, process.cwd());

  logSuccess(`Published ${total} package(s) successfully!`);
}

export async function publishCli(): Promise<void> {
  const {values} = parseArgs({
    allowPositionals: true,
    options: publishOptions,
    strict: false,
  });

  await publish({
    concurrency: parsePositiveIntOption("concurrency", values["concurrency"] as string | undefined, 1),
    "dry-run": values["dry-run"] as boolean,
    "npm-dir": values["npm-dir"] as string,
  });
}
