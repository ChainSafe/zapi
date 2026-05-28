import { describe, it } from "vitest";
import { createRequire } from "node:module";
import * as fs from "node:fs";
import * as path from "node:path";
import * as url from "node:url";
import fc from "fast-check";
import { edgeNumbers, edgeBigInts } from "./edges.ts";

const require = createRequire(import.meta.url);
const mod = require("../../zig-out/lib/test_fuzz_numeric.node") as {
	rtNumberF64(n: number): number;
	rtNumberI32(n: number): number;
	rtNumberU32(n: number): number;
	rtNumberI64(n: number): bigint;
	rtBigIntI64(b: bigint): bigint;
	rtBigIntU64(b: bigint): bigint;
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

function reviveBigInt(raw: unknown): bigint {
	if (typeof raw === "object" && raw !== null && "__bigint" in raw) {
		return BigInt((raw as { __bigint: string }).__bigint);
	}
	throw new Error(`Cannot revive as bigint: ${JSON.stringify(raw)}`);
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

const I64_MAX = (1n << 63n) - 1n;
const I64_MIN = -(1n << 63n);

const numberIntArb = fc.oneof(
	{ arbitrary: fc.integer({ min: -(2 ** 33), max: 2 ** 33 }), weight: 3 },
	{ arbitrary: fc.double(), weight: 2 },
	{ arbitrary: fc.constantFrom(...edgeNumbers), weight: 1 },
);

describe("rtNumberI32", () => {
	it("matches ECMAScript ToInt32 (`| 0`)", () => {
		fc.assert(
			fc.property(numberIntArb, (n) => mod.rtNumberI32(n) === (n | 0)),
			{
				numRuns: FUZZ_RUNS,
				examples: loadSeeds<number>("rtNumberI32", (r) => r as number),
			},
		);
	});
});

describe("rtNumberU32", () => {
	it("matches ECMAScript ToUint32 (`>>> 0`)", () => {
		fc.assert(
			fc.property(numberIntArb, (n) => mod.rtNumberU32(n) === (n >>> 0)),
			{
				numRuns: FUZZ_RUNS,
				examples: loadSeeds<number>("rtNumberU32", (r) => r as number),
			},
		);
	});
});

describe("rtNumberI64", () => {
	it("matches NAPI int64 semantics (clamped)", () => {
		fc.assert(
			fc.property(numberIntArb, (n) => {
				let expected: bigint;
				if (Number.isNaN(n) || !Number.isFinite(n)) expected = 0n;
				else if (n >= 2 ** 63) expected = I64_MAX;
				else if (n < -(2 ** 63)) expected = I64_MIN;
				else expected = BigInt(Math.trunc(n));
				return mod.rtNumberI64(n) === expected;
			}),
			{
				numRuns: FUZZ_RUNS,
				examples: loadSeeds<number>("rtNumberI64", (r) => r as number),
			},
		);
	});
});

const bigIntArbI64 = fc.oneof(
	{ arbitrary: fc.bigInt({ min: -(2n ** 65n), max: 2n ** 65n }), weight: 4 },
	{ arbitrary: fc.constantFrom(...edgeBigInts), weight: 1 },
);

describe("rtBigIntI64", () => {
	it("matches BigInt.asIntN(64, ·)", () => {
		fc.assert(
			fc.property(bigIntArbI64, (b) =>
				mod.rtBigIntI64(b) === BigInt.asIntN(64, b),
			),
			{
				numRuns: FUZZ_RUNS,
				examples: loadSeeds<bigint>("rtBigIntI64", reviveBigInt),
			},
		);
	});
});

describe("rtBigIntU64", () => {
	it("matches BigInt.asUintN(64, ·)", () => {
		fc.assert(
			fc.property(bigIntArbI64, (b) =>
				mod.rtBigIntU64(b) === BigInt.asUintN(64, b),
			),
			{
				numRuns: FUZZ_RUNS,
				examples: loadSeeds<bigint>("rtBigIntU64", reviveBigInt),
			},
		);
	});
});
