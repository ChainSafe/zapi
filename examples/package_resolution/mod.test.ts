import {mkdirSync, mkdtempSync, rmSync, writeFileSync} from "node:fs";
import {tmpdir} from "node:os";
import {join, relative} from "node:path";
import {afterEach, describe, expect, it} from "vitest";
import {getTarget, requireNapiLibrary} from "../../ts/lib.js";

describe("native package resolution", () => {
	const directories: string[] = [];

	afterEach(() => {
		for (const directory of directories.splice(0)) {
			rmSync(directory, {recursive: true, force: true});
		}
	});

	it.each([false, true])("loads each wrapper's own platform dependency (relative path: %s)", (relativePath) => {
		const directory = mkdtempSync(join(tmpdir(), "zapi-package-resolution-"));
		directories.push(directory);
		const target = getTarget(process.platform, process.arch);
		const name = "@zapi-test/addon";

		for (const version of ["1.0.0", "2.0.0"]) {
			const packageDir = join(directory, version);
			const targetDir = join(packageDir, "node_modules", `${name}-${target}`);
			mkdirSync(targetDir, {recursive: true});
			writeFileSync(
				join(packageDir, "package.json"),
				JSON.stringify({
					name,
					version,
					optionalDependencies: {[`${name}-${target}`]: version},
					zapi: {binaryName: "bindings", targets: [target]},
				})
			);
			writeFileSync(
				join(targetDir, "package.json"),
				JSON.stringify({name: `${name}-${target}`, version, main: "index.cjs"})
			);
			writeFileSync(join(targetDir, "index.cjs"), `module.exports = ${JSON.stringify({version})};`);

			const input = relativePath ? relative(process.cwd(), packageDir) : packageDir;
			expect(requireNapiLibrary(input), `platform dependency for wrapper ${version}`).toEqual({version});
		}
	});
});
