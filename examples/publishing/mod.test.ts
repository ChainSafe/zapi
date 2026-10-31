import {execFile, spawnSync} from "node:child_process";
import {existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from "node:fs";
import {createServer} from "node:http";
import {tmpdir} from "node:os";
import {delimiter, join} from "node:path";
import {fileURLToPath} from "node:url";
import {promisify} from "node:util";
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

  it("preserves unrelated optional dependencies and removes retired native targets", () => {
    writeFileSync(
      join(directory, "package.json"),
      JSON.stringify({
        ...manifest,
        optionalDependencies: {other: "^2.0.0", [`${name}-x86_64-apple-darwin`]: "1.0.0"},
      })
    );
    const result = run("--main-only");
    expect(result.status, result.stderr).toBe(0);
    const pkg = JSON.parse(readFileSync(join(directory, "package.json"), "utf8"));
    expect(pkg.optionalDependencies).toEqual({
      other: "^2.0.0",
      ...Object.fromEntries(targets.map((target) => [`${name}-${target}`, version])),
    });
  });

  it("can prepare platforms repeatedly from the same build artifacts", () => {
    expect(run("--platforms-only").status).toBe(0);
    rmSync(join(directory, "npm"), {recursive: true});
    const result = run("--platforms-only");
    expect(result.status, result.stderr).toBe(0);
    for (const target of targets) {
      expect(readFileSync(join(directory, "npm", target, "bindings.node"), "utf8"), target).toBe(target);
    }
  });

  it("fails on missing artifacts instead of repackaging an old binary", () => {
    expect(run("--platforms-only").status).toBe(0);
    rmSync(join(directory, "artifacts"), {recursive: true, force: true});
    writeFileSync(join(directory, "package.json"), JSON.stringify({...manifest, version: "2.0.0"}));
    const result = run("--platforms-only");
    expect(result.status).not.toBe(0);
    for (const target of targets) {
      const pkg = JSON.parse(readFileSync(join(directory, "npm", target, "package.json"), "utf8"));
      expect(pkg.version, target).toBe(version);
    }
  });

  it("passes the wrapper's publish configuration to generated platforms", () => {
    const publishConfig = {registry: "https://registry.example", access: "public"};
    writeFileSync(join(directory, "package.json"), JSON.stringify({...manifest, publishConfig}));
    const result = run("--platforms-only");
    expect(result.status, result.stderr).toBe(0);
    for (const target of targets) {
      const pkg = JSON.parse(readFileSync(join(directory, "npm", target, "package.json"), "utf8"));
      expect(pkg.publishConfig, target).toEqual(publishConfig);
    }
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
      writeFileSync(join(path, "bindings.node"), target);
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

  function calls(): {args: string[]; spec: string}[] {
    return readFileSync(join(directory, "calls.jsonl"), "utf8")
      .trim()
      .split("\n")
      .filter(Boolean)
      .map((line) => JSON.parse(line));
  }

  it("preserves the default platform-first, main-last publish order", () => {
    const result = run([]);
    expect(result.status, result.stderr).toBe(0);
    expect(published()).toEqual([...targets.map((target) => `${name}-${target}@${version}`), `${name}@${version}`]);
  });

  it("accepts an absolute path to the prepared platform packages", () => {
    const result = run(["--platforms-only", "--npm-dir", join(directory, "npm")]);
    expect(result.status, result.stderr).toBe(0);
    expect(published()).toEqual(targets.map((target) => `${name}-${target}@${version}`));
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
        .every((call) => call.args.includes("--registry=https://registry.example"))
    ).toBe(true);
    expect(calls.at(-1)?.args).toEqual(["publish", "--registry=https://registry.example", "--tag", "next"]);
  });

  it.each([{extraArgs: []}, {extraArgs: ["--registry=https://override.example", "--userconfig=/tmp/custom.npmrc"]}])(
    "queries the publish registry while preserving explicit npm overrides: $extraArgs",
    ({extraArgs}) => {
      for (const target of targets) {
        writeFileSync(
          join(directory, "npm", target, "package.json"),
          JSON.stringify({
            name: `${name}-${target}`,
            version,
            publishConfig: {registry: "https://registry.example"},
          })
        );
      }
      const result = run(["--platforms-only", "--skip-existing", "--", ...extraArgs]);
      expect(result.status, result.stderr).toBe(0);
      for (const call of calls().filter((call) => call.args[0] === "view")) {
        expect(call.args, call.spec).toEqual([
          "view",
          call.spec,
          "version",
          "--registry=https://registry.example",
          ...extraArgs,
          "--json",
          "--prefer-online",
        ]);
      }
    }
  );

  it.each(["name", "version"])("refuses stale platform %s before publishing any package", (field) => {
    const target = targets[1];
    writeFileSync(
      join(directory, "npm", target, "package.json"),
      JSON.stringify({
        name: `${name}-${target}`,
        version,
        [field]: "stale",
      })
    );
    const result = run(["--platforms-only", "--skip-existing"]);
    expect(result.status).not.toBe(0);
    expect(calls()).toEqual([]);
  });

  it.each(["manifest", "cli", "scoped"])(
    "uses the correct registry with real npm (%s)",
    async (mode) => {
      const requests: number[] = [];
      const servers = [0, 1].map((index) =>
        createServer((request, response) => {
          requests.push(index);
          const packageName = decodeURIComponent(request.url?.slice(1) ?? "");
          response.setHeader("content-type", "application/json");
          response.end(JSON.stringify({name: packageName, versions: {[version]: {name: packageName, version}}}));
        })
      );
      try {
        const registries = await Promise.all(
          servers.map(async (server) => {
            await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
            const address = server.address();
            if (!address || typeof address === "string") throw new Error("Expected a TCP address");
            return `http://127.0.0.1:${address.port}`;
          })
        );
        const registryKey = mode === "scoped" ? "@zapi-test:registry" : "registry";
        for (const target of targets) {
          writeFileSync(
            join(directory, "npm", target, "package.json"),
            JSON.stringify({
              name: `${name}-${target}`,
              version,
              publishConfig: {[registryKey]: registries[1]},
            })
          );
        }
        writeFileSync(join(directory, "user.npmrc"), "");
        writeFileSync(join(directory, "global.npmrc"), "");
        await promisify(execFile)(
          process.execPath,
          [
            cli,
            "publish",
            "--platforms-only",
            "--skip-existing",
            "--dry-run",
            "--",
            "--access",
            "public",
            "--ignore-scripts",
            "--provenance",
            "--tag",
            "next",
            ...(mode === "cli" ? ["--registry", registries[0]] : []),
          ],
          {
            cwd: directory,
            timeout: 10000,
            env: {
              ...process.env,
              npm_config_registry: registries[0],
              npm_config_userconfig: join(directory, "user.npmrc"),
              npm_config_globalconfig: join(directory, "global.npmrc"),
              npm_config_cache: join(directory, "cache"),
              npm_config_update_notifier: "false",
            },
          }
        );
        expect(requests).toEqual(targets.map(() => (mode === "cli" ? 0 : 1)));
      } finally {
        for (const server of servers) server.close();
      }
    },
    15000
  );

  it("refuses a missing platform binary before publishing any package", () => {
    rmSync(join(directory, "npm", targets[1], "bindings.node"));
    expect(run(["--platforms-only"]).status).not.toBe(0);
    expect(calls()).toEqual([]);
  });

  it("rejects unsupported zapi options instead of silently publishing every package", () => {
    expect(run(["--main-only"]).status).not.toBe(0);
    expect(calls()).toEqual([]);
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
