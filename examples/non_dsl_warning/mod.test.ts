import { describe, expect, it } from "vitest";
import { spawnSync } from "node:child_process";
const non_dsl_mod = require("../../zig-out/lib/example_non_dsl_warning.node");

const cwd = new URL("../..", import.meta.url);

function runNode(source: string) {
	return spawnSync(process.execPath, ["-e", source], {
		cwd,
		encoding: "utf8",
	});
}

describe("non-DSL fn should warn user", () => {
	it("exports DSL functions and skips non-DSL functions", () => {
		const result = runNode(`
			const mod = require("./zig-out/lib/example_non_dsl_warning.node");
			process.stdout.write(JSON.stringify({
				exported: mod.exported(41),
				skipped: typeof mod.skipped,
			}));
		`);

		expect(result.status).toEqual(0);
		expect(JSON.parse(result.stdout)).toEqual({
			exported: 42,
			skipped: "undefined",
		});

		expect(result.stderr).toContain("zapi: skipping non-DSL function mod.skipped, this will not be exported");
	});
});
