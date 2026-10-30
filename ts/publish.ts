import {execFile, spawn} from "node:child_process";
import {readFile} from "node:fs/promises";
import {join} from "node:path";
import {type ParseArgsOptionsConfig, parseArgs, promisify} from "node:util";
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
  "platforms-only": {
    default: false,
    type: "boolean",
  },
  "skip-existing": {
    default: false,
    type: "boolean",
  },
} satisfies ParseArgsOptionsConfig;

export type PublishOpts = {
  "npm-dir": string;
  "dry-run": boolean;
  concurrency: number;
  "platforms-only"?: boolean;
  "skip-existing"?: boolean;
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

async function isPublished(cwd: string, extraArgs: string[]): Promise<boolean> {
  const manifest = JSON.parse(await readFile(join(cwd, "package.json"), "utf8")) as {name: string; version: string};
  const spec = `${manifest.name}@${manifest.version}`;
  const {values} = parseArgs({
    allowPositionals: true,
    args: extraArgs,
    options: {registry: {type: "string"}},
    strict: false,
  });
  const registryArgs = typeof values.registry === "string" ? ["--registry", values.registry] : [];
  let stdout: string;
  try {
    ({stdout} = await promisify(execFile)(
      "npm",
      ["view", spec, "version", "--json", "--prefer-online", ...registryArgs],
      {cwd}
    ));
  } catch (error) {
    if (error instanceof Error && "stdout" in error && typeof error.stdout === "string") {
      let response: {error?: {code?: string}} | undefined;
      try {
        response = JSON.parse(error.stdout) as typeof response;
      } catch {
        // Non-JSON failures must not be mistaken for an unpublished package.
      }
      if (response?.error?.code === "E404") return false;
    }
    throw new Error(`Unable to check whether ${spec} is published`, {cause: error});
  }
  if (JSON.parse(stdout) !== manifest.version) throw new Error(`Unexpected npm version response for ${spec}`);
  return true;
}

export async function publish(opts: PublishOpts): Promise<void> {
  const extraArgs = extraPublishArgs();
  const publishArgv = ["publish", ...extraArgs];
  const {config} = await loadConfig();
  const total = config.targets.length + (opts["platforms-only"] ? 0 : 1);
  const description = `${config.targets.length} target package(s)${opts["platforms-only"] ? "" : " + main package"}`;

  logInfo(`${opts["dry-run"] ? "[DRY RUN] " : ""}Publishing ${description} with concurrency ${opts.concurrency}...`);
  logDetail(`Extra npm args: ${extraArgs.length > 0 ? extraArgs.join(" ") : "(none)"}`);

  let started = 0;
  let skipped = 0;
  const publishPackage = async (label: string, cwd: string): Promise<void> => {
    const step = ++started;
    if (opts["skip-existing"] && (await isPublished(cwd, extraArgs))) {
      skipped += 1;
      logStep(step, total, `Skipping ${label}: version already published`);
      return;
    }
    logStep(step, total, `${opts["dry-run"] ? "Would publish" : "Publishing"} ${label}`);
    if (opts["dry-run"]) {
      logDetail(`Directory: ${cwd}`);
    } else {
      await runNpm(publishArgv, cwd);
    }
  };

  await runWithConcurrency(config.targets, opts.concurrency, async (target) => {
    await publishPackage(target, join(process.cwd(), opts["npm-dir"], target));
  });
  if (!opts["platforms-only"]) await publishPackage("main package", process.cwd());

  logSuccess(
    `${opts["dry-run"] ? "[DRY RUN] Would publish" : "Published"} ${total - skipped} package(s); skipped ${skipped}`
  );
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
    "platforms-only": values["platforms-only"] as boolean,
    "skip-existing": values["skip-existing"] as boolean,
  });
}
