import {chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {afterEach, beforeEach, describe, expect, it, vi} from "vitest";
import {build, buildLocal} from "../../ts/build.js";
import {buildArtifacts} from "../../ts/buildArtifacts.js";
import {type PkgJson, parsePkgJson, resolvePreset, targetPackages} from "../../ts/config.js";
import {getTarget, requireNapiLibrary} from "../../ts/lib.js";
import {createNpmDirs, moveArtifacts, updateOptionalDependencies, updateTargetPkgJsons} from "../../ts/prepublish.js";
import {publish} from "../../ts/publish.js";

const target = "aarch64-apple-darwin";
const otherTarget = "x86_64-unknown-linux-gnu";

const pkgJson: PkgJson = {
	name: "@scope/addon",
	version: "1.2.3",
	zapi: {
		binaryName: "addon",
		step: "lib",
		targets: [target, otherTarget],
		presets: [
			{name: "mainnet", args: ["-Dpreset=mainnet"]},
			{name: "minimal", args: ["-Dpreset=minimal"]},
		],
	},
};

const standalonePkgJson: PkgJson = {
	...pkgJson,
	zapi: {
		...pkgJson.zapi!,
		presets: [
			{name: "mainnet", args: ["-Dpreset=mainnet"]},
			{name: "minimal", args: ["-Dpreset=minimal"], standalone: true},
		],
	},
};

// Concurrent builds append to one log, so each call must land as a single write.
const FAKE_ZIG = `#!/bin/sh
prefix=""
prev=""
line=""
for arg in "$@"; do
	if [ "$prev" = "--prefix" ]; then prefix="$arg"; fi
	line="$line$arg "
	prev="$arg"
done
printf '%s\\n' "$line" >> "$ZAPI_FAKE_ZIG_LOG"
libdir="\${prefix:-zig-out}/lib"
mkdir -p "$libdir"
: > "$libdir/addon.node"
`;

let tmp: string;
let zigLog: string;
const savedEnv = {...process.env};

function zigCalls(): string[] {
	return readFileSync(zigLog, "utf-8").trim().split("\n").map((line) => line.trim());
}

function withPresets(presets: unknown): PkgJson {
	return {...pkgJson, zapi: {...pkgJson.zapi!, presets: presets as NonNullable<PkgJson["zapi"]>["presets"]}};
}

beforeEach(() => {
	tmp = mkdtempSync(join(tmpdir(), "zapi-presets-"));
	zigLog = join(tmp, "zig-calls.log");
	const bin = join(tmp, "bin");
	mkdirSync(bin);
	writeFileSync(join(bin, "zig"), FAKE_ZIG);
	chmodSync(join(bin, "zig"), 0o755);
	process.env.PATH = `${bin}:${savedEnv.PATH}`;
	process.env.ZAPI_FAKE_ZIG_LOG = zigLog;
});

afterEach(() => {
	process.env.PATH = savedEnv.PATH;
	delete process.env.ZAPI_FAKE_ZIG_LOG;
	vi.restoreAllMocks();
});

describe("presets config", () => {
	it("defaults to a single unsuffixed preset", () => {
		const config = parsePkgJson({name: "addon", version: "0.0.0", zapi: {binaryName: "addon", targets: [target]}});
		expect(config.presets).toEqual([{name: "default", args: [], file: "addon.node", standalone: false}]);
	});

	it("suffixes every preset after the first", () => {
		const config = parsePkgJson(pkgJson);
		expect(config.presets).toEqual([
			{name: "mainnet", args: ["-Dpreset=mainnet"], file: "addon.node", standalone: false},
			{name: "minimal", args: ["-Dpreset=minimal"], file: "addon-minimal.node", standalone: false},
		]);
	});

	it("parses the standalone flag", () => {
		const config = parsePkgJson(standalonePkgJson);
		expect(config.presets.map((preset) => preset.standalone)).toEqual([false, true]);
	});

	it("rejects duplicate preset names", () => {
		expect(() => parsePkgJson(withPresets([{name: "a"}, {name: "a"}]))).toThrow("zapi.presets");
	});

	it("rejects preset names that are not file-name safe", () => {
		expect(() => parsePkgJson(withPresets([{name: "min/imal"}]))).toThrow("zapi.presets");
	});

	it("rejects a standalone default preset", () => {
		expect(() => parsePkgJson(withPresets([{name: "a", standalone: true}]))).toThrow("zapi.presets[0]");
	});

	it("rejects a non-boolean standalone flag", () => {
		expect(() => parsePkgJson(withPresets([{name: "a"}, {name: "b", standalone: "yes"}]))).toThrow(
			"zapi.presets[].standalone"
		);
	});

	it("resolves the first preset when none is requested", () => {
		const config = parsePkgJson(pkgJson);
		expect(resolvePreset(config).name).toBe("mainnet");
		expect(resolvePreset(config, "minimal").file).toBe("addon-minimal.node");
	});

	it("rejects unknown preset names", () => {
		const config = parsePkgJson(pkgJson);
		expect(() => resolvePreset(config, "gnosis")).toThrow(/gnosis/);
	});

	it("lists a standalone preset as its own package", () => {
		const packages = targetPackages(standalonePkgJson, parsePkgJson(standalonePkgJson));
		expect(packages.map((pkg) => pkg.name)).toEqual([
			`@scope/addon-${target}`,
			`@scope/addon-minimal-${target}`,
			`@scope/addon-${otherTarget}`,
			`@scope/addon-minimal-${otherTarget}`,
		]);
		expect(packages[0]).toMatchObject({dir: target, files: ["addon.node"], optional: true});
		expect(packages[1]).toMatchObject({dir: `minimal-${target}`, files: ["addon-minimal.node"], optional: false});
	});
});

describe("build", () => {
	it("passes preset args to zig build", async () => {
		await build({extraArgs: ["-Dpreset=minimal"], quiet: true, step: "lib", target, zigCwd: tmp});
		expect(zigCalls()).toEqual(["build lib -Dtarget=aarch64-macos-none -Dpreset=minimal"]);
	});

	it("renames a local non-default preset build to its preset file", async () => {
		const config = parsePkgJson(pkgJson);
		await buildLocal({config, preset: resolvePreset(config, "minimal"), target, zigCwd: tmp});
		expect(existsSync(join(tmp, "zig-out/lib/addon-minimal.node"))).toBe(true);
		expect(existsSync(join(tmp, "zig-out/lib/addon.node"))).toBe(false);
	});

	it("keeps the default preset file name for a local build", async () => {
		const config = parsePkgJson(pkgJson);
		await buildLocal({config, preset: resolvePreset(config), target, zigCwd: tmp});
		expect(existsSync(join(tmp, "zig-out/lib/addon.node"))).toBe(true);
	});
});

describe("build-artifacts", () => {
	it("builds every preset for every target", async () => {
		const config = parsePkgJson(pkgJson);
		const artifactsDir = join(tmp, "artifacts");
		await buildArtifacts({artifactsDir, concurrency: 2, config, step: "lib", zigCwd: tmp});

		for (const t of [target, otherTarget]) {
			expect(existsSync(join(artifactsDir, t, "addon.node")), `${t} default`).toBe(true);
			expect(existsSync(join(artifactsDir, t, "addon-minimal.node")), `${t} minimal`).toBe(true);
		}
		const calls = zigCalls();
		expect(calls).toHaveLength(4);
		expect(calls.filter((c) => c.includes("-Dpreset=minimal"))).toHaveLength(2);
	});
});

describe("prepublish", () => {
	const opts = () => ({"artifacts-dir": join(tmp, "artifacts"), concurrency: 1, "npm-dir": join(tmp, "npm")});

	function writeArtifacts(): void {
		for (const t of [target, otherTarget]) {
			mkdirSync(join(tmp, "artifacts", t), {recursive: true});
			writeFileSync(join(tmp, "artifacts", t, "addon.node"), "");
			writeFileSync(join(tmp, "artifacts", t, "addon-minimal.node"), "");
		}
	}

	it("moves every bundled preset file into the target package", async () => {
		const config = parsePkgJson(pkgJson);
		writeArtifacts();
		await createNpmDirs(pkgJson, config, opts());
		await moveArtifacts(pkgJson, config, opts());
		expect(existsSync(join(tmp, "npm", target, "addon.node"))).toBe(true);
		expect(existsSync(join(tmp, "npm", target, "addon-minimal.node"))).toBe(true);
	});

	it("lists every bundled preset file in the target package.json", async () => {
		const config = parsePkgJson(pkgJson);
		await createNpmDirs(pkgJson, config, opts());
		await updateTargetPkgJsons(pkgJson, config, opts());
		const written = JSON.parse(readFileSync(join(tmp, "npm", target, "package.json"), "utf-8"));
		expect(written.files).toEqual(["addon.node", "addon-minimal.node"]);
		expect(written.main).toBe("addon.node");
	});

	it("puts a standalone preset in its own package", async () => {
		const config = parsePkgJson(standalonePkgJson);
		writeArtifacts();
		await createNpmDirs(standalonePkgJson, config, opts());
		await moveArtifacts(standalonePkgJson, config, opts());
		await updateTargetPkgJsons(standalonePkgJson, config, opts());

		expect(existsSync(join(tmp, "npm", `minimal-${target}`, "addon-minimal.node"))).toBe(true);
		expect(existsSync(join(tmp, "npm", target, "addon-minimal.node"))).toBe(false);

		const regular = JSON.parse(readFileSync(join(tmp, "npm", target, "package.json"), "utf-8"));
		expect(regular.files).toEqual(["addon.node"]);

		const standalone = JSON.parse(readFileSync(join(tmp, "npm", `minimal-${target}`, "package.json"), "utf-8"));
		expect(standalone).toMatchObject({
			cpu: ["arm64"],
			files: ["addon-minimal.node"],
			main: "addon-minimal.node",
			name: `@scope/addon-minimal-${target}`,
			os: ["darwin"],
			version: "1.2.3",
		});
	});

	it("leaves standalone packages out of optionalDependencies", () => {
		const config = parsePkgJson(standalonePkgJson);
		const updated = updateOptionalDependencies(structuredClone(standalonePkgJson), config);
		expect(Object.keys(updated.optionalDependencies as object)).toEqual([
			`@scope/addon-${target}`,
			`@scope/addon-${otherTarget}`,
		]);
	});
});

describe("publish", () => {
	it("publishes standalone packages", async () => {
		const dir = join(tmp, "pkg");
		mkdirSync(dir);
		writeFileSync(join(dir, "package.json"), JSON.stringify(standalonePkgJson));
		const log = vi.spyOn(console, "log").mockImplementation(() => {});

		await publish({concurrency: 1, cwd: dir, "dry-run": true, "npm-dir": "npm", npmArgs: []});

		const lines = log.mock.calls.map((call) => call.join(" "));
		expect(lines.some((line) => line.includes(`Would publish @scope/addon-minimal-${target}`))).toBe(true);
		expect(lines.some((line) => line.includes(join(dir, "npm", `minimal-${target}`)))).toBe(true);
		expect(lines.some((line) => line.includes("Would publish 4 package(s)"))).toBe(true);
	});
});

describe("requireNapiLibrary", () => {
	function writePackage(json: PkgJson): string {
		const dir = join(tmp, "pkg");
		mkdirSync(dir);
		writeFileSync(join(dir, "package.json"), JSON.stringify(json));
		return dir;
	}

	it("rejects unknown presets before loading", () => {
		const dir = writePackage(pkgJson);
		expect(() => requireNapiLibrary(dir, "gnosis")).toThrow(/gnosis/);
	});

	it("loads a bundled preset from the target package file", () => {
		const dir = writePackage(pkgJson);
		const current = getTarget(process.platform, process.arch);
		expect(() => requireNapiLibrary(dir, "minimal")).toThrow(`@scope/addon-${current}/addon-minimal.node`);
	});

	it("loads a standalone preset from its own package", () => {
		const dir = writePackage(standalonePkgJson);
		const current = getTarget(process.platform, process.arch);
		expect(() => requireNapiLibrary(dir, "minimal")).toThrow(`@scope/addon-minimal-${current}/addon-minimal.node`);
	});

	it("prefers a local preset build", () => {
		const dir = writePackage(pkgJson);
		mkdirSync(join(dir, "zig-out/lib"), {recursive: true});
		writeFileSync(join(dir, "zig-out/lib/addon-minimal.node"), "");
		expect(() => requireNapiLibrary(dir, "minimal")).toThrow(join(dir, "zig-out/lib/addon-minimal.node"));
	});
});
