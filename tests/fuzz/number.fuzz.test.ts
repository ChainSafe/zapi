import { describe, it } from "vitest";
import fc from "fast-check";
import { edgeNumbers } from "../utils/edge.ts";
import {
	oracleNumberF64,
	oracleNumberI32,
	oracleNumberI64,
	oracleNumberU32,
} from "../utils/oracles.ts";
import { FUZZ_RUNS, loadSeeds, mod } from "../utils/support.ts";

const numberArb = fc.oneof(
	{ arbitrary: fc.double(), weight: 4 },
	{ arbitrary: fc.constantFrom(...edgeNumbers), weight: 1 },
);

describe("rtNumberF64", () => {
	it("round-trip is identity for all JS numbers", () => {
		fc.assert(
			fc.property(numberArb, (n) => {
				const result = mod.rtNumberF64(n);
				const expected = oracleNumberF64(n);
				if (Number.isNaN(expected)) return Number.isNaN(result);
				return Object.is(result, expected);
			}),
			{
				numRuns: FUZZ_RUNS,
				examples: loadSeeds<number>("rtNumberF64", (raw) => raw as number),
			},
		);
	});
});

const numberIntArb = fc.oneof(
	{ arbitrary: fc.integer({ min: -(2 ** 33), max: 2 ** 33 }), weight: 3 },
	{ arbitrary: fc.double(), weight: 2 },
	{ arbitrary: fc.constantFrom(...edgeNumbers), weight: 1 },
);

describe("rtNumberI32", () => {
	it("matches ECMAScript ToInt32 (`| 0`)", () => {
		fc.assert(
			fc.property(numberIntArb, (n) => mod.rtNumberI32(n) === oracleNumberI32(n)),
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
			fc.property(numberIntArb, (n) => mod.rtNumberU32(n) === oracleNumberU32(n)),
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
			fc.property(
				numberIntArb,
				(n) => mod.rtNumberI64(n) === oracleNumberI64(n),
			),
			{
				numRuns: FUZZ_RUNS,
				examples: loadSeeds<number>("rtNumberI64", (r) => r as number),
			},
		);
	});
});
