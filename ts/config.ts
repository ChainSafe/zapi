import { promises as fs } from "node:fs";
import { join } from "node:path";
import { Target, TARGETS } from "./lib.js";

export type Config = {
  binaryName: string;
  targets: Target[];
  step?: string;
};

export type PkgJson = {
  name: string;
  version: string;
  license?: string;
  repository?: string | { type?: string; url?: string };
  zapi?: {
    binaryName: string;
    targets: string[];
    step?: string;
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
export async function loadConfig(cwd: string = "."): Promise<LoadedConfig> {
  const pkgJsonPath = join(cwd, "package.json");
  const pkgJson = JSON.parse(await fs.readFile(pkgJsonPath, "utf-8")) as PkgJson;
  const config = parsePkgJson(pkgJson);
  return { pkgJson, config };
}

export function parsePkgJson(pkgJson: any): Config {
  const napi = pkgJson.zapi;
  if (typeof napi !== "object" || napi === null) {
    throw new Error("zapi field is missing in package.json");
  }
  const binaryName = napi.binaryName;
  if (typeof binaryName !== "string") {
    throw new Error("zapi.binaryName must be a string");
  }
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
    targets: targets as Target[]
  };
}

export function getTargetParts(target: Target): {platform: NodeJS.Platform, arch: NodeJS.Architecture, abi?: string} {
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
  return {platform, arch, abi};
}
