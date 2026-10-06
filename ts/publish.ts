import {spawn} from "node:child_process";
import {join} from "node:path";
import {type ParseArgsOptionsConfig, parseArgs} from "node:util";
import {loadConfig, targetPackages} from "./config.js";
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
  /** Package root holding package.json and the npm dir (default: process.cwd()) */
  cwd?: string;
  /** Extra args appended to every `npm publish` (default: everything after `--` on the CLI) */
  npmArgs?: string[];
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
  const cwd = opts.cwd ?? process.cwd();
  const extraArgs = opts.npmArgs ?? extraPublishArgs();
  const publishArgv = ["publish", ...extraArgs];

  const {pkgJson, config} = await loadConfig(cwd);
  const packages = targetPackages(pkgJson, config);
  const total = packages.length + 1; // +1 for main package

  if (opts["dry-run"]) {
    logInfo(
      `[DRY RUN] Would publish ${packages.length} package(s) + main package with concurrency ${opts.concurrency}`
    );
    logDetail(`Extra npm args: ${extraArgs.length > 0 ? extraArgs.join(" ") : "(none)"}`);

    for (let i = 0; i < packages.length; i++) {
      const pkg = packages[i];
      logStep(i + 1, total, `Would publish ${pkg.name}`);
      logDetail(`Directory: ${join(cwd, opts["npm-dir"], pkg.dir)}`);
    }

    logStep(total, total, "Would publish main package");
    logDetail(`Directory: ${cwd}`);

    logSuccess(`[DRY RUN] ${total} package(s) would be published`);
    return;
  }

  logInfo(`Publishing ${packages.length} package(s) + main package with concurrency ${opts.concurrency}...`);

  let started = 0;
  await runWithConcurrency(packages, opts.concurrency, async (pkg) => {
    started += 1;
    logStep(started, total, `Publishing ${pkg.name}...`);
    await runNpm(publishArgv, join(cwd, opts["npm-dir"], pkg.dir));
  });

  logStep(total, total, "Publishing main package...");
  await runNpm(publishArgv, cwd);

  logSuccess(`Published ${total} package(s) successfully!`);
}

export async function publishCli(): Promise<void> {
  const {values} = parseArgs({
    allowPositionals: true,
    options: publishOptions,
    strict: false,
  });

  await publish({
    concurrency: parsePositiveIntOption("concurrency", values.concurrency as string | undefined, 1),
    "dry-run": values["dry-run"] as boolean,
    "npm-dir": values["npm-dir"] as string,
  });
}
