import {promises as fs} from "node:fs";
import {availableParallelism} from "node:os";
import {join} from "node:path";
import {type ParseArgsOptionsConfig, parseArgs} from "node:util";
import {type Config, type PkgJson, getTargetParts, loadConfig, targetPackages} from "./config.js";
import {parsePositiveIntOption, runWithConcurrency} from "./lib.js";
import {logDetail, logInfo, logSuccess, logWarn} from "./log.js";

const defaultConcurrency = String(Math.max(1, Math.min(availableParallelism(), 4)));

export type CreateNpmDirsOpts = {
  "npm-dir": string;
  concurrency: number;
};

export async function createNpmDirs(pkgJson: PkgJson, config: Config, opts: CreateNpmDirsOpts): Promise<void> {
  await runWithConcurrency(targetPackages(pkgJson, config), opts.concurrency, async (pkg) => {
    await fs.mkdir(join(opts["npm-dir"], pkg.dir), {recursive: true});
  });
}

export async function moveArtifacts(pkgJson: PkgJson, config: Config, opts: PrepublishOpts): Promise<void> {
  logInfo("Moving artifacts to npm packages...");
  await runWithConcurrency(targetPackages(pkgJson, config), opts.concurrency, async (pkg) => {
    for (const file of pkg.files) {
      const artifactPath = join(opts["artifacts-dir"], pkg.target, file);
      const destPath = join(opts["npm-dir"], pkg.dir, file);

      await fs.rename(artifactPath, destPath).catch((err) => {
        if (err.code === "ENOENT") {
          logWarn(`Artifact not found: ${artifactPath}`);
          return;
        }
        throw err;
      });
      logDetail(`${pkg.target} → ${destPath}`);
    }
  });
}

export async function updateTargetPkgJsons(pkgJson: PkgJson, config: Config, opts: PrepublishOpts): Promise<void> {
  logInfo("Generating target package.json files...");
  await runWithConcurrency(targetPackages(pkgJson, config), opts.concurrency, async (pkg) => {
    const {platform, arch, abi} = getTargetParts(pkg.target);

    const libc = platform !== "linux" ? undefined : abi === "gnu" ? "glibc" : abi === "musl" ? "musl" : undefined;

    const pkgDir = join(opts["npm-dir"], pkg.dir);
    const targetPkgJson = {
      cpu: [arch],
      files: pkg.files,
      license: pkgJson.license,
      main: pkg.files[0],
      name: pkg.name,
      os: [platform],
      repository: pkgJson.repository,
      version: pkgJson.version,
      ...(libc ? {libc: [libc]} : {}),
    };
    await fs.writeFile(join(pkgDir, "package.json"), JSON.stringify(targetPkgJson, null, 2));
    await fs.writeFile(
      join(pkgDir, "README.md"),
      `# \`${targetPkgJson.name}\`\n
This is the ${pkg.target} target package for ${pkgJson.name}.

`
    );
    logDetail(`Created ${join(pkgDir, "package.json")}`);
  });
}

export function updateOptionalDependencies(pkgJson: PkgJson, config: Config): PkgJson {
  const optionalDependencies: Record<string, string> = {};
  for (const pkg of targetPackages(pkgJson, config)) {
    if (pkg.optional) {
      optionalDependencies[pkg.name] = pkgJson.version;
    }
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
  concurrency: {
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
  const concurrency = parsePositiveIntOption(
    "concurrency",
    values.concurrency as string | undefined,
    Number(defaultConcurrency)
  );

  logInfo(`Preparing ${pkgJson.name}@${pkgJson.version} for publishing with concurrency ${concurrency}...`);

  const opts: PrepublishOpts = {
    "artifacts-dir": values["artifacts-dir"],
    concurrency,
    "npm-dir": values["npm-dir"],
  };

  await createNpmDirs(pkgJson, config, opts);
  await moveArtifacts(pkgJson, config, opts);
  await updateTargetPkgJsons(pkgJson, config, opts);

  logInfo("Updating package.json with optionalDependencies...");
  const updatedPkgJson = await updateOptionalDependencies(pkgJson, config);
  await fs.writeFile("package.json", JSON.stringify(updatedPkgJson, null, 2));

  logSuccess(`Prepared ${targetPackages(pkgJson, config).length} package(s) in ${values["npm-dir"]}/`);
}
