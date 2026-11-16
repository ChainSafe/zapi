import {promises as fs} from "node:fs";
import {basename, join} from "node:path";
import {TARGETS, type Target} from "./lib.js";

const BINARY_NAME_RE = /^[A-Za-z0-9._-]+$/;

export type Config = {
  binaryName: string;
  targets: Target[];
  step?: string;
  /** Variant name to the extra `zig build` arguments that produce it */
  variants?: Record<string, string[]>;
};

export type PkgJson = {
  name: string;
  version: string;
  license?: string;
  repository?: string | {type?: string; url?: string};
  optionalDependencies?: Record<string, string>;
  publishConfig?: Record<string, unknown>;
  zapi?: {
    binaryName: string;
    targets: string[];
    step?: string;
    variants?: Record<string, string[]>;
  };
  [key: string]: unknown;
};

export type LoadedConfig = {
  pkgJson: PkgJson;
  config: Config;
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

function validateFileNamePart(field: string, value: string): void {
  if (!BINARY_NAME_RE.test(value)) {
    throw new Error(`${field} must match /^[A-Za-z0-9._-]+$/`);
  }
  if (value !== basename(value)) {
    throw new Error(`${field} must not include path segments`);
  }
  if (value.includes("/") || value.includes("\\") || value.includes("..")) {
    throw new Error(`${field} must not contain path separators or '..'`);
  }
}

function parseVariants(variants: unknown): Record<string, string[]> | undefined {
  if (variants == null) {
    return undefined;
  }
  if (typeof variants !== "object" || Array.isArray(variants)) {
    throw new Error("zapi.variants must be an object of variant name to zig build arguments");
  }
  const entries = Object.entries(variants);
  if (entries.length === 0) {
    throw new Error("zapi.variants must not be empty");
  }
  for (const [name, zigArgs] of entries) {
    validateFileNamePart("zapi.variants names", name);
    if (!Array.isArray(zigArgs) || zigArgs.some((arg) => typeof arg !== "string")) {
      throw new Error(`zapi.variants.${name} must be an array of strings`);
    }
  }
  return variants as Record<string, string[]>;
}

/**
 * The variants to build, or a single `undefined` entry for a package without variants.
 */
export function getVariants(config: Config): (string | undefined)[] {
  return config.variants ? Object.keys(config.variants) : [undefined];
}

/**
 * File name of the addon binary: `<binaryName>.node`, or `<binaryName>-<variant>.node` for a package with variants.
 */
export function getBinaryFileName(config: Config, variant?: string): string {
  if (config.variants) {
    if (variant === undefined) {
      throw new Error(`A variant is required, one of: ${Object.keys(config.variants).join(", ")}`);
    }
    if (!Object.hasOwn(config.variants, variant)) {
      throw new Error(`Unknown variant "${variant}". Valid values: ${Object.keys(config.variants).join(", ")}`);
    }
    return `${config.binaryName}-${variant}.node`;
  }
  if (variant !== undefined) {
    throw new Error(`Variant "${variant}" requested but zapi.variants is not set in package.json`);
  }
  return `${config.binaryName}.node`;
}

export function getBinaryFileNames(config: Config): string[] {
  return getVariants(config).map((variant) => getBinaryFileName(config, variant));
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
  validateFileNamePart("zapi.binaryName", binaryName);

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
    step,
    targets: targets as Target[],
    variants: parseVariants(napi.variants),
  };
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
