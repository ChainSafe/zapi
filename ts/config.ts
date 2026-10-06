import {promises as fs} from "node:fs";
import {basename, join} from "node:path";
import {TARGETS, type Target} from "./lib.js";

const FILE_NAME_RE = /^[A-Za-z0-9._-]+$/;

export type Preset = {
  name: string;
  args: string[];
  file: string;
  standalone: boolean;
};

export type Config = {
  binaryName: string;
  targets: Target[];
  step?: string;
  presets: Preset[];
};

export type PkgJson = {
  name: string;
  version: string;
  license?: string;
  repository?: string | {type?: string; url?: string};
  zapi?: {
    binaryName: string;
    targets: string[];
    step?: string;
    presets?: {name: string; args?: string[]; standalone?: boolean}[];
  };
  [key: string]: unknown;
};

export type LoadedConfig = {
  pkgJson: PkgJson;
  config: Config;
};

/** One npm package produced by `prepublish`: either a target package or a standalone preset package. */
export type TargetPackage = {
  name: string;
  /** Directory under `--npm-dir` */
  dir: string;
  target: Target;
  /** Binary files it ships; the first one is `main` */
  files: string[];
  /** Listed in the main package's optionalDependencies */
  optional: boolean;
};

/**
 * Load and parse package.json and zapi config from a directory.
 * @param cwd - Directory containing package.json (default: current directory)
 */
export async function loadConfig(cwd = "."): Promise<LoadedConfig> {
  const pkgJsonPath = join(cwd, "package.json");
  const pkgJson = JSON.parse(await fs.readFile(pkgJsonPath, "utf-8")) as PkgJson;
  const config = parsePkgJson(pkgJson);
  return {config, pkgJson};
}

function validateFileNameSegment(field: string, value: string): void {
  if (!FILE_NAME_RE.test(value)) {
    throw new Error(`${field} must match /^[A-Za-z0-9._-]+$/`);
  }
  if (value !== basename(value)) {
    throw new Error(`${field} must not include path segments`);
  }
  if (value.includes("/") || value.includes("\\") || value.includes("..")) {
    throw new Error(`${field} must not contain path separators or '..'`);
  }
}

/**
 * Presets are alternative builds of the same binary, each with its own extra `zig build` args.
 * The first preset is the default and keeps the plain `<binaryName>.node` file name so a config
 * without presets publishes exactly what it did before. A standalone preset is published as its
 * own `<pkg>-<preset>-<target>` packages instead of being bundled into the target packages.
 */
function parsePresets(binaryName: string, raw: unknown): Preset[] {
  if (raw == null) {
    return [{args: [], file: `${binaryName}.node`, name: "default", standalone: false}];
  }
  if (!Array.isArray(raw) || raw.length === 0) {
    throw new Error("zapi.presets must be a non-empty array");
  }
  const names = new Set<string>();
  return raw.map((entry: unknown, index) => {
    if (typeof entry !== "object" || entry === null) {
      throw new Error("zapi.presets entries must be objects");
    }
    const {name, args = [], standalone = false} = entry as {name?: unknown; args?: unknown; standalone?: unknown};
    if (typeof name !== "string") {
      throw new Error("zapi.presets[].name must be a string");
    }
    validateFileNameSegment("zapi.presets[].name", name);
    if (names.has(name)) {
      throw new Error(`zapi.presets names must be unique: "${name}"`);
    }
    names.add(name);
    if (!Array.isArray(args) || args.some((arg) => typeof arg !== "string")) {
      throw new Error("zapi.presets[].args must be an array of strings");
    }
    if (typeof standalone !== "boolean") {
      throw new Error("zapi.presets[].standalone must be a boolean");
    }
    if (index === 0 && standalone) {
      throw new Error("zapi.presets[0] is the default preset and cannot be standalone");
    }
    return {
      args: args as string[],
      file: index === 0 ? `${binaryName}.node` : `${binaryName}-${name}.node`,
      name,
      standalone,
    };
  });
}

export function parsePkgJson(pkgJson: PkgJson): Config {
  const napi = pkgJson.zapi;
  if (typeof napi !== "object" || napi === null) {
    throw new Error("zapi field is missing in package.json");
  }
  const binaryName = napi.binaryName;
  if (typeof binaryName !== "string") {
    throw new Error("zapi.binaryName must be a string");
  }
  validateFileNameSegment("zapi.binaryName", binaryName);

  const targets = napi.targets;
  if (!Array.isArray(targets) || targets.length === 0) {
    throw new Error("zapi.targets must be a non-empty array");
  }
  for (const target of targets) {
    if (typeof target !== "string") {
      throw new Error("zapi.targets must contain only strings");
    }
    if (!TARGETS.includes(target as Target)) {
      throw new Error(`Unsupported target: ${target}`);
    }
  }
  const step = napi.step;
  if (step != null && typeof step !== "string") {
    throw new Error("zapi.step must be a string");
  }

  return {
    binaryName,
    presets: parsePresets(binaryName, napi.presets),
    step,
    targets: targets as Target[],
  };
}

/**
 * Pick a preset by name, or the default (first) preset when no name is given.
 */
export function resolvePreset(config: Config, name?: string): Preset {
  if (name == null) {
    return config.presets[0];
  }
  const preset = config.presets.find((candidate) => candidate.name === name);
  if (!preset) {
    const valid = config.presets.map((candidate) => candidate.name).join(", ");
    throw new Error(`Unknown preset "${name}". Valid values: ${valid}`);
  }
  return preset;
}

/** npm package that ships `preset` for `target`. */
export function presetPackageName(pkgJson: PkgJson, preset: Preset, target: Target): string {
  return preset.standalone ? `${pkgJson.name}-${preset.name}-${target}` : `${pkgJson.name}-${target}`;
}

export function targetPackages(pkgJson: PkgJson, config: Config): TargetPackage[] {
  const bundled = config.presets.filter((preset) => !preset.standalone);
  const packages: TargetPackage[] = [];
  for (const target of config.targets) {
    packages.push({
      dir: target,
      files: bundled.map((preset) => preset.file),
      name: `${pkgJson.name}-${target}`,
      optional: true,
      target,
    });
    for (const preset of config.presets) {
      if (!preset.standalone) continue;
      packages.push({
        dir: `${preset.name}-${target}`,
        files: [preset.file],
        name: presetPackageName(pkgJson, preset, target),
        optional: false,
        target,
      });
    }
  }
  return packages;
}

export function getTargetParts(target: Target): {platform: NodeJS.Platform; arch: NodeJS.Architecture; abi?: string} {
  let platform: NodeJS.Platform;
  let arch: NodeJS.Architecture;
  let abi: string | undefined;
  switch (target) {
    case "aarch64-apple-darwin":
      platform = "darwin";
      arch = "arm64";
      break;
    case "aarch64-unknown-linux-gnu":
      platform = "linux";
      arch = "arm64";
      abi = "gnu";
      break;
    case "aarch64-unknown-linux-musl":
      platform = "linux";
      arch = "arm64";
      abi = "musl";
      break;
    case "x86_64-apple-darwin":
      platform = "darwin";
      arch = "x64";
      break;
    case "x86_64-unknown-linux-gnu":
      platform = "linux";
      arch = "x64";
      abi = "gnu";
      break;
    case "x86_64-unknown-linux-musl":
      platform = "linux";
      arch = "x64";
      abi = "musl";
      break;
    case "x86_64-pc-windows-msvc":
      platform = "win32";
      arch = "x64";
      abi = "msvc";
      break;
  }
  return {abi, arch, platform};
}
