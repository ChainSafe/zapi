import { describe, it } from "vitest";
import fc from "fast-check";
import { edgeUint8Arrays } from "../utils/edge.ts";
import { equalUint8Array, oracleUint8Array } from "../utils/oracles.ts";
import {
	FUZZ_RUNS,
	loadSeeds,
	mod,
	reviveUint8Array,
} from "../utils/support.ts";

const uint8ArrayArb = fc.oneof(
	{ arbitrary: fc.uint8Array({ maxLength: 4096 }), weight: 4 },
	{ arbitrary: fc.constantFrom(...edgeUint8Arrays), weight: 1 },
);

describe("rtUint8Array", () => {
	it("round-trips bytes unchanged", () => {
		fc.assert(
			fc.property(uint8ArrayArb, (value) =>
				equalUint8Array(mod.rtUint8Array(value), oracleUint8Array(value)),
			),
			{
				numRuns: FUZZ_RUNS,
				examples: loadSeeds<Uint8Array>("rtUint8Array", reviveUint8Array),
			},
		);
	});
});
