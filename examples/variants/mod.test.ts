import {spawnSync} from "node:child_process";
import {existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync} from "node:fs";
import {tmpdir} from "node:os";
import {delimiter, join} from "node:path";
import {fileURLToPath} from "node:url";
import {afterEach, beforeEach, describe, expect, it} from "vitest";
import {getTarget, requireNapiLibrary} from "../../ts/lib.js";

const cli = fileURLToPath(new URL("../../lib/cli.js", import.meta.url));
const targets = ["aarch64-apple-darwin", "x86_64-unknown-linux-gnu"];
const variants = {mainnet: ["-Dpreset=mainnet"], minimal: ["-Dpreset=minimal", "-Dfoo=bar"]};
const name = "@zapi-test/addon";
const version = "1.2.3";
const manifest = {name, version, zapi: {binaryName: "bindings", step: "lib", targets, variants}};

describe("variants", () => {
  let directory: string;
  let env: NodeJS.ProcessEnv;

  beforeEach(() => {
    directory = mkdtempSync(join(tmpdir(), "zapi-variants-"));
    mkdirSync(join(directory, "bin"));
    writeFileSync(join(directory, "package.json"), JSON.stringify(manifest));
    // Stands in for `zig build`: installs a binary whose content is the arguments it was built with
    writeFileSync(
      join(directory, "bin", "zig"),
      `#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");
const args = process.argv.slice(2);
const prefixIx = args.indexOf("--prefix");
const lib = path.join(prefixIx === -1 ? "zig-out" : args[prefixIx + 1], "lib");
fs.mkdirSync(lib, {recursive: true});
fs.writeFileSync(path.join(lib, "bindings.node"), args.filter((arg) => arg.startsWith("-D")).join(" "));
`,
      {mode: 0o755}
    );
    env = {...process.env, PATH: `${join(directory, "bin")}${delimiter}${process.env.PATH}`};
  });

  afterEach(() => rmSync(directory, {recursive: true, force: true}));

  function run(...args: string[]) {
    return spawnSync(process.execPath, [cli, ...args], {cwd: directory, env, encoding: "utf8"});
  }

  function writeArtifacts(): void {
    for (const target of targets) {
      mkdirSync(join(directory, "artifacts", target), {recursive: true});
      for (const variant of Object.keys(variants)) {
        writeFileSync(join(directory, "artifacts", target, `bindings-${variant}.node`), `${target} ${variant}`);
      }
    }
  }

  it("builds every variant of every target with its zig arguments", () => {
    const result = run("build-artifacts");
    expect(result.status, result.stderr).toBe(0);
    for (const target of targets) {
      const triple = target === "aarch64-apple-darwin" ? "aarch64-macos-none" : "x86_64-linux-gnu";
      expect(readdirSync(join(directory, "artifacts", target)).sort(), target).toEqual([
        "bindings-mainnet.node",
        "bindings-minimal.node",
      ]);
      for (const [variant, zigArgs] of Object.entries(variants)) {
        expect(
          readFileSync(join(directory, "artifacts", target, `bindings-${variant}.node`), "utf8"),
          `${target} ${variant}`
        ).toBe([`-Dtarget=${triple}`, ...zigArgs].join(" "));
      }
    }
  });

  it("builds a single variant into the local build path", () => {
    const result = run("build", "--variant", "minimal", "--prefix", "out");
    expect(result.status, result.stderr).toBe(0);
    expect(readdirSync(join(directory, "out", "lib"))).toEqual(["bindings-minimal.node"]);
    expect(readFileSync(join(directory, "out", "lib", "bindings-minimal.node"), "utf8")).toContain(
      variants.minimal.join(" ")
    );
  });

  it("rejects a build without a variant, or with an unknown one", () => {
    const missing = run("build");
    expect(missing.status).not.toBe(0);
    expect(missing.stderr).toContain("A variant is required");
    const unknown = run("build", "--variant", "gnosis");
    expect(unknown.status).not.toBe(0);
    expect(unknown.stderr).toContain('Unknown variant "gnosis"');
    expect(existsSync(join(directory, "zig-out"))).toBe(false);
  });

  it("packages every variant in each target package", () => {
    writeArtifacts();
    const result = run("prepublish", "--platforms-only");
    expect(result.status, result.stderr).toBe(0);
    for (const target of targets) {
      const pkg = JSON.parse(readFileSync(join(directory, "npm", target, "package.json"), "utf8"));
      expect(pkg.files, target).toEqual(["bindings-mainnet.node", "bindings-minimal.node"]);
      expect(pkg.main, target).toBeUndefined();
      for (const variant of Object.keys(variants)) {
        expect(
          readFileSync(join(directory, "npm", target, `bindings-${variant}.node`), "utf8"),
          `${target} ${variant}`
        ).toBe(`${target} ${variant}`);
      }
    }
  });

  it("fails preparation and publishing when a variant binary is missing", () => {
    writeArtifacts();
    expect(run("prepublish", "--platforms-only").status).toBe(0);
    rmSync(join(directory, "npm", targets[1], "bindings-minimal.node"));
    expect(run("publish", "--dry-run").status).not.toBe(0);

    rmSync(join(directory, "npm"), {recursive: true});
    rmSync(join(directory, "artifacts", targets[1], "bindings-minimal.node"));
    expect(run("prepublish", "--platforms-only").status).not.toBe(0);
  });

  it.each([
    [{mainnet: "-Dpreset=mainnet"}, "must be an array of strings"],
    [{"../mainnet": []}, "zapi.variants names must match"],
    [{}, "must not be empty"],
  ])("rejects invalid variants %j", (invalid, message) => {
    writeFileSync(join(directory, "package.json"), JSON.stringify({...manifest, zapi: {...manifest.zapi, variants: invalid}}));
    const result = run("prepublish", "--main-only");
    expect(result.status).not.toBe(0);
    expect(result.stderr).toContain(message);
  });

  describe("requireNapiLibrary", () => {
    const target = getTarget(process.platform, process.arch);

    it("requires a configured variant", () => {
      expect(() => requireNapiLibrary(directory)).toThrow("A variant is required");
      expect(() => requireNapiLibrary(directory, {variant: "gnosis"})).toThrow('Unknown variant "gnosis"');
    });

    it("rejects a variant for a package without variants", () => {
      writeFileSync(join(directory, "package.json"), JSON.stringify({name, version, zapi: {binaryName: "bindings", targets}}));
      expect(() => requireNapiLibrary(directory, {variant: "minimal"})).toThrow("zapi.variants is not set");
    });

    it("resolves the variant file in the platform package, and prefers a local build", () => {
      const targetDir = join(directory, "node_modules", `${name}-${target}`);
      mkdirSync(targetDir, {recursive: true});
      writeFileSync(join(targetDir, "package.json"), JSON.stringify({name: `${name}-${target}`, version}));
      // Not real addons: loading one fails with an error naming the path the loader picked
      for (const variant of Object.keys(variants)) {
        writeFileSync(join(targetDir, `bindings-${variant}.node`), "");
      }
      const load = (variant: string): string => {
        try {
          requireNapiLibrary(directory, {variant});
        } catch (e) {
          return (e as Error).message;
        }
        throw new Error("expected the stand-in addon to fail to load");
      };

      for (const variant of Object.keys(variants)) {
        expect(load(variant), variant).toContain(join(targetDir, `bindings-${variant}.node`));
      }

      mkdirSync(join(directory, "zig-out", "lib"), {recursive: true});
      writeFileSync(join(directory, "zig-out", "lib", "bindings-minimal.node"), "");
      expect(load("minimal")).toContain(join(directory, "zig-out", "lib", "bindings-minimal.node"));
      expect(load("mainnet")).toContain(join(targetDir, "bindings-mainnet.node"));
    });
  });
});
