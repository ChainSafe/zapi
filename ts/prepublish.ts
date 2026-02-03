import { promises as fs } from "node:fs";
import { join } from "node:path";
import { parseArgs, ParseArgsOptionsConfig } from "node:util";
import { Config, getTargetParts, loadConfig, type PkgJson } from "./config.js";
import { logInfo, logDetail, logSuccess, logWarn } from "./log.js";

export type CreateNpmDirsOpts = {
  "npm-dir": string;
};

export async function createNpmDirs(config: Config, opts: CreateNpmDirsOpts): Promise<void> {
  for (const target of config.targets) {
    await fs.mkdir(join(opts["npm-dir"], target), { recursive: true });
  }
}

export async function moveArtifacts(pkgJson: PkgJson, config: Config, opts: PrepublishOpts): Promise<void> {
  logInfo("Moving artifacts to npm packages...");
  for (const target of config.targets) {
    const artifactPath = join(opts["artifacts-dir"], target, `${config.binaryName}.node`);
    const destPath = join(opts["npm-dir"], target, `${config.binaryName}.node`);

    await fs.rename(artifactPath, destPath).catch((err) => {
      if (err.code === 'ENOENT') {
        logWarn(`Artifact not found: ${artifactPath}`);
        return;
      }
      throw err;
    });
    logDetail(`${target} → ${destPath}`);
  }
}

export async function updateTargetPkgJsons(
  pkgJson: PkgJson,
  config: Config,
  opts: PrepublishOpts
): Promise<void> {
  logInfo("Generating target package.json files...");
  for (const target of config.targets) {
    const {platform, arch, abi} = getTargetParts(target);

    const libc = platform !== 'linux' ?
      undefined :
      abi === 'gnu' ? 'glibc' :
      abi === 'musl' ? 'musl' :
      undefined;

    const targetDir = join(opts["npm-dir"], target);
    const targetPkgJson = {
      name: `${pkgJson.name}-${target}`,
      version: pkgJson.version,
      license: pkgJson.license,
      repository: pkgJson.repository,
      main: `${config.binaryName}.node`,
      files: [`${config.binaryName}.node`],
      os: [platform],
      cpu: [arch],
      ...(libc ? { libc: [libc] } : {}),
    };
    await fs.writeFile(join(targetDir, "package.json"), JSON.stringify(targetPkgJson, null, 2));
    await fs.writeFile(join(targetDir, "README.md"), `# \`${targetPkgJson.name}\`\n
This is the ${target} target package for ${pkgJson.name}.

`);
    logDetail(`Created ${join(targetDir, "package.json")}`);
  }
}

export function updateOptionalDependencies(
  pkgJson: PkgJson,
  config: Config,
): PkgJson {
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
};

const prepublishOptions = {
    "artifacts-dir": {
      type: "string",
      default: "artifacts",
    },
    "npm-dir": {
      type: "string",
      default: "npm",
    }
} satisfies ParseArgsOptionsConfig;

export async function prepublishCli(): Promise<void> {
  const {values} = parseArgs({
    options: prepublishOptions,
    allowPositionals: true,
  });

  const { pkgJson, config } = await loadConfig();

  logInfo(`Preparing ${pkgJson.name}@${pkgJson.version} for publishing...`);

  await createNpmDirs(config, values);
  await moveArtifacts(pkgJson, config, values);
  await updateTargetPkgJsons(pkgJson, config, values);

  logInfo("Updating package.json with optionalDependencies...");
  const updatedPkgJson = await updateOptionalDependencies(pkgJson, config);
  await fs.writeFile("package.json", JSON.stringify(updatedPkgJson, null, 2));

  logSuccess(`Prepared ${config.targets.length} target package(s) in ${values["npm-dir"]}/`);
}
