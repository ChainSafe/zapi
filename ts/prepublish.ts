import {promises as fs} from "node:fs";
import {availableParallelism} from "node:os";
import {join} from "node:path";
import {type ParseArgsOptionsConfig, parseArgs} from "node:util";
import {type Config, type PkgJson, getTargetParts, loadConfig} from "./config.js";
import {parsePositiveIntOption, runWithConcurrency} from "./lib.js";
import {logDetail, logInfo, logSuccess, logWarn} from "./log.js";

const defaultConcurrency = String(Math.max(1, Math.min(availableParallelism(), 4)));

export type CreateNpmDirsOpts = {
  "npm-dir": string;
  concurrency: number;
};

export async function createNpmDirs(config: Config, opts: CreateNpmDirsOpts): Promise<void> {
  await runWithConcurrency(config.targets, opts.concurrency, async (target) => {
    await fs.mkdir(join(opts["npm-dir"], target), {recursive: true});
  });
}

export async function moveArtifacts(_pkgJson: PkgJson, config: Config, opts: PrepublishOpts): Promise<void> {
  logInfo("Moving artifacts to npm packages...");
  await runWithConcurrency(config.targets, opts.concurrency, async (target) => {
    const artifactPath = join(opts["artifacts-dir"], target, `${config.binaryName}.node`);
    const destPath = join(opts["npm-dir"], target, `${config.binaryName}.node`);

    await fs.rename(artifactPath, destPath).catch((err) => {
      if (err.code === "ENOENT") {
        logWarn(`Artifact not found: ${artifactPath}`);
        return;
      }
      throw err;
    });
    logDetail(`${target} → ${destPath}`);
  });
}

export async function updateTargetPkgJsons(pkgJson: PkgJson, config: Config, opts: PrepublishOpts): Promise<void> {
  logInfo("Generating target package.json files...");
  await runWithConcurrency(config.targets, opts.concurrency, async (target) => {
    const {platform, arch, abi} = getTargetParts(target);

    const libc = platform !== "linux" ? undefined : abi === "gnu" ? "glibc" : abi === "musl" ? "musl" : undefined;

    const targetDir = join(opts["npm-dir"], target);
    const targetPkgJson = {
      cpu: [arch],
      files: [`${config.binaryName}.node`],
      license: pkgJson.license,
      main: `${config.binaryName}.node`,
      name: `${pkgJson.name}-${target}`,
      os: [platform],
      repository: pkgJson.repository,
      version: pkgJson.version,
      ...(libc ? {libc: [libc]} : {}),
    };
    await fs.writeFile(join(targetDir, "package.json"), JSON.stringify(targetPkgJson, null, 2));
    await fs.writeFile(
      join(targetDir, "README.md"),
      `# \`${targetPkgJson.name}\`\n
This is the ${target} target package for ${pkgJson.name}.

`
    );
    logDetail(`Created ${join(targetDir, "package.json")}`);
  });
}

export function updateOptionalDependencies(pkgJson: PkgJson, config: Config): PkgJson {
  const optionalDependencies: Record<string, string> = {};
  for (const target of config.targets) {
    optionalDependencies[`${pkgJson.name}-${target}`] = pkgJson.version;
  }
  pkgJson.optionalDependencies = optionalDependencies;
  return pkgJson;
}

type PrepublishOpts = {
  "artifacts-dir": string;
  "npm-dir": string;
  concurrency: number;
};

const prepublishOptions = {
  "artifacts-dir": {
    default: "artifacts",
    type: "string",
  },
  "concurrency": {
    default: defaultConcurrency,
    type: "string",
  },
  "npm-dir": {
    default: "npm",
    type: "string",
  },
} satisfies ParseArgsOptionsConfig;

export async function prepublishCli(): Promise<void> {
  const {values} = parseArgs({
    allowPositionals: true,
    options: prepublishOptions,
  });

  const {pkgJson, config} = await loadConfig();
  const concurrency = parsePositiveIntOption("concurrency", values.concurrency as string | undefined, Number(defaultConcurrency));

  logInfo(`Preparing ${pkgJson.name}@${pkgJson.version} for publishing with concurrency ${concurrency}...`);

  const opts: PrepublishOpts = {
    "artifacts-dir": values["artifacts-dir"],
    "npm-dir": values["npm-dir"],
    concurrency,
  };

  await createNpmDirs(config, opts);
  await moveArtifacts(pkgJson, config, opts);
  await updateTargetPkgJsons(pkgJson, config, opts);

  logInfo("Updating package.json with optionalDependencies...");
  const updatedPkgJson = await updateOptionalDependencies(pkgJson, config);
  await fs.writeFile("package.json", JSON.stringify(updatedPkgJson, null, 2));

  logSuccess(`Prepared ${config.targets.length} target package(s) in ${values["npm-dir"]}/`);
}
