import { describe, it } from "vitest";
import { createRequire } from "node:module";
import * as fs from "node:fs";
import * as path from "node:path";
import * as url from "node:url";
import fc from "fast-check";
import { edgeNumbers } from "./edges.ts";

const require = createRequire(import.meta.url);
const mod = require("../../zig-out/lib/test_fuzz_numeric.node") as {
	rtNumberF64(n: number): number;
};

const FUZZ_RUNS = Number(process.env.FUZZ_RUNS ?? 10_000);
const __dirname = path.dirname(url.fileURLToPath(import.meta.url));

/**
 * Load persisted regression cases for a target.
 *
 * Each file under seeds/ is a JSON array of values (in whatever JSON-encodable
 * form makes sense for the target; bigints use `{"__bigint":"123"}`).
 * Missing file → empty examples list; not an error.
 */
function loadSeeds<T>(target: string, revive: (raw: unknown) => T): T[] {
	const file = path.join(__dirname, "seeds", `${target}.json`);
	if (!fs.existsSync(file)) return [];
	const raw = JSON.parse(fs.readFileSync(file, "utf8")) as unknown[];
	return raw.map(revive);
}

const numberArb = fc.oneof(
	{ arbitrary: fc.double(), weight: 4 },
	{ arbitrary: fc.constantFrom(...edgeNumbers), weight: 1 },
);

describe("rtNumberF64", () => {
	it("round-trip is identity for all JS numbers", () => {
		fc.assert(
			fc.property(numberArb, (n) => {
				const result = mod.rtNumberF64(n);
				if (Number.isNaN(n)) return Number.isNaN(result);
				return Object.is(result, n);
			}),
			{
				numRuns: FUZZ_RUNS,
				examples: loadSeeds<number>("rtNumberF64", (raw) => raw as number),
			},
		);
	});
});
