import {spawnSync} from "node:child_process";
import {existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from "node:fs";
import {tmpdir} from "node:os";
import {delimiter, join} from "node:path";
import {fileURLToPath} from "node:url";
import {afterEach, beforeEach, describe, expect, it} from "vitest";

const cli = fileURLToPath(new URL("../../lib/cli.js", import.meta.url));
const targets = ["aarch64-apple-darwin", "x86_64-unknown-linux-gnu"];
const name = "@zapi-test/addon";
const version = "1.2.3";

describe("package preparation", () => {
  let directory: string;
  const manifest = {name, version, zapi: {binaryName: "bindings", targets}};

  beforeEach(() => {
    directory = mkdtempSync(join(tmpdir(), "zapi-preparing-"));
    writeFileSync(join(directory, "package.json"), JSON.stringify(manifest));
    for (const target of targets) {
      mkdirSync(join(directory, "artifacts", target), {recursive: true});
      writeFileSync(join(directory, "artifacts", target, "bindings.node"), target);
    }
  });

  afterEach(() => rmSync(directory, {recursive: true, force: true}));

  function run(...args: string[]) {
    return spawnSync(process.execPath, [cli, "prepublish", ...args], {cwd: directory, encoding: "utf8"});
  }

  it("prepares platforms without modifying the tracked manifest", () => {
    const result = run("--platforms-only");
    expect(result.status, result.stderr).toBe(0);
    expect(readFileSync(join(directory, "package.json"), "utf8")).toBe(JSON.stringify(manifest));
    for (const target of targets) {
      const pkg = JSON.parse(readFileSync(join(directory, "npm", target, "package.json"), "utf8"));
      expect(pkg.name, target).toBe(`${name}-${target}`);
      expect(pkg.version, target).toBe(version);
      expect(readFileSync(join(directory, "npm", target, "bindings.node"), "utf8"), target).toBe(target);
    }
  });

  it("prepares only the main manifest without requiring or touching artifacts", () => {
    rmSync(join(directory, "artifacts"), {recursive: true});
    const result = run("--main-only");
    expect(result.status, result.stderr).toBe(0);
    const pkg = JSON.parse(readFileSync(join(directory, "package.json"), "utf8"));
    expect(pkg.optionalDependencies).toEqual(
      Object.fromEntries(targets.map((target) => [`${name}-${target}`, version]))
    );
    expect(existsSync(join(directory, "npm"))).toBe(false);
    expect(result.stdout).not.toContain("Artifact not found");
  });

  it("still prepares platforms and the main manifest by default", () => {
    const result = run();
    expect(result.status, result.stderr).toBe(0);
    const pkg = JSON.parse(readFileSync(join(directory, "package.json"), "utf8"));
    expect(pkg.optionalDependencies).toEqual(
      Object.fromEntries(targets.map((target) => [`${name}-${target}`, version]))
    );
    for (const target of targets) {
      expect(existsSync(join(directory, "npm", target, "bindings.node")), target).toBe(true);
    }
  });

  it("rejects conflicting preparation options before changing files", () => {
    const result = run("--main-only", "--platforms-only");
    expect(result.status).not.toBe(0);
    expect(result.stderr).toContain("mutually exclusive");
    expect(readFileSync(join(directory, "package.json"), "utf8")).toBe(JSON.stringify(manifest));
    expect(existsSync(join(directory, "npm"))).toBe(false);
  });
});

describe("publishing", () => {
  let directory: string;
  let env: NodeJS.ProcessEnv;

  beforeEach(() => {
    directory = mkdtempSync(join(tmpdir(), "zapi-publishing-"));
    mkdirSync(join(directory, "bin"));
    writeFileSync(
      join(directory, "package.json"),
      JSON.stringify({name, version, zapi: {binaryName: "bindings", targets}})
    );
    for (const target of targets) {
      const path = join(directory, "npm", target);
      mkdirSync(path, {recursive: true});
      writeFileSync(join(path, "package.json"), JSON.stringify({name: `${name}-${target}`, version}));
    }
    writeFileSync(join(directory, "published.json"), "[]");
    writeFileSync(join(directory, "calls.jsonl"), "");
    writeFileSync(
      join(directory, "bin", "npm"),
      `#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");
const root = process.env.TEST_ROOT;
const args = process.argv.slice(2);
const pkg = JSON.parse(fs.readFileSync("package.json"));
const spec = pkg.name + "@" + pkg.version;
const state = path.join(root, "published.json");
const published = JSON.parse(fs.readFileSync(state));
fs.appendFileSync(path.join(root, "calls.jsonl"), JSON.stringify({args, spec}) + "\\n");
if (args[0] === "view") {
  if (process.env.VIEW_ERROR) {
    console.log(JSON.stringify({error: {code: process.env.VIEW_ERROR}}));
    process.exit(1);
  }
  if (published.includes(spec)) { console.log(JSON.stringify(pkg.version)); process.exit(0); }
  console.log(JSON.stringify({error: {code: "E404"}}));
  process.exit(1);
}
if (args[0] !== "publish") process.exit(99);
if (pkg.name === process.env.FAIL_PACKAGE || published.includes(spec)) process.exit(1);
published.push(spec);
fs.writeFileSync(state, JSON.stringify(published));
`,
      {mode: 0o755}
    );
    env = {...process.env, TEST_ROOT: directory, PATH: `${join(directory, "bin")}${delimiter}${process.env.PATH}`};
  });

  afterEach(() => rmSync(directory, {recursive: true, force: true}));

  function run(args: string[]) {
    return spawnSync(process.execPath, [cli, "publish", ...args], {cwd: directory, env, encoding: "utf8"});
  }

  function published(): string[] {
    return JSON.parse(readFileSync(join(directory, "published.json"), "utf8"));
  }

  it("preserves the default platform-first, main-last publish order", () => {
    const result = run([]);
    expect(result.status, result.stderr).toBe(0);
    expect(published()).toEqual([...targets.map((target) => `${name}-${target}@${version}`), `${name}@${version}`]);
  });

  it("resumes a partial platform publish without touching the main package", () => {
    env.FAIL_PACKAGE = `${name}-${targets[1]}`;
    expect(run(["--platforms-only", "--skip-existing"]).status).not.toBe(0);
    expect(published()).toEqual([`${name}-${targets[0]}@${version}`]);
    delete env.FAIL_PACKAGE;
    const result = run([
      "--platforms-only",
      "--skip-existing",
      "--",
      "--registry=https://registry.example",
      "--tag",
      "next",
    ]);
    expect(result.status, result.stderr).toBe(0);
    expect(published()).toEqual(targets.map((target) => `${name}-${target}@${version}`));
    const calls: {args: string[]; spec: string}[] = readFileSync(join(directory, "calls.jsonl"), "utf8")
      .trim()
      .split("\n")
      .map((line) => JSON.parse(line));
    expect(
      calls.filter((call) => call.args[0] === "publish" && call.spec === `${name}-${targets[0]}@${version}`)
    ).toHaveLength(1);
    expect(
      calls
        .filter((call) => call.args[0] === "view")
        .slice(-2)
        .every((call) => call.args.includes("https://registry.example"))
    ).toBe(true);
    expect(calls.at(-1)?.args).toEqual(["publish", "--registry=https://registry.example", "--tag", "next"]);
  });

  it.each(["E401", "E500", "ENOTFOUND"])("aborts on %s instead of treating it as a missing version", (code) => {
    env.VIEW_ERROR = code;
    const result = run(["--platforms-only", "--skip-existing"]);
    expect(result.status).not.toBe(0);
    expect(published()).toEqual([]);
  });

  it("skips an already published main package when requested", () => {
    expect(run([]).status).toBe(0);
    const result = run(["--skip-existing"]);
    expect(result.status, result.stderr).toBe(0);
    expect(published()).toHaveLength(3);
  });

  it.each([false, true])("never publishes in a dry run (skip existing: %s)", (skip) => {
    const result = run(["--platforms-only", "--dry-run", ...(skip ? ["--skip-existing"] : [])]);
    expect(result.status, result.stderr).toBe(0);
    expect(published()).toEqual([]);
    expect(result.stdout).not.toContain("main package");
  });
});
