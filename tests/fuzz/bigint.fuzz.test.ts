import { describe, it } from "vitest";
import fc from "fast-check";
import { edgeBigInts } from "../utils/edge.ts";
import {
	fitsBigIntI128,
	fitsBigIntI64,
	fitsBigIntU64,
	oracleBigIntI128,
	oracleBigIntI128LowBits,
	oracleLosslessI64,
	oracleLosslessU64,
} from "../utils/oracles.ts";
import { FUZZ_RUNS, loadSeeds, mod, reviveBigInt } from "../utils/support.ts";

const bigIntArbI64 = fc.oneof(
	{ arbitrary: fc.bigInt({ min: -(2n ** 65n), max: 2n ** 65n }), weight: 4 },
	{ arbitrary: fc.constantFrom(...edgeBigInts), weight: 1 },
);

describe("rtBigIntI64", () => {
	it("is exact in [-2^63, 2^63) and throws outside that range", () => {
		fc.assert(
			fc.property(bigIntArbI64, (b) => {
				if (fitsBigIntI64(b)) return mod.rtBigIntI64(b) === b;

				try {
					mod.rtBigIntI64(b);
					return false;
				} catch {
					return true;
				}
			}),
			{
				numRuns: FUZZ_RUNS,
				examples: loadSeeds<bigint>("rtBigIntI64", reviveBigInt),
			},
		);
	});
});

describe("rtBigIntU64", () => {
	it("is exact in [0, 2^64) and throws outside that range", () => {
		fc.assert(
			fc.property(bigIntArbI64, (b) => {
				if (fitsBigIntU64(b)) return mod.rtBigIntU64(b) === b;

				try {
					mod.rtBigIntU64(b);
					return false;
				} catch {
					return true;
				}
			}),
			{
				numRuns: FUZZ_RUNS,
				examples: loadSeeds<bigint>("rtBigIntU64", reviveBigInt),
			},
		);
	});
});

describe("losslessI64", () => {
	it("lossless ⇔ b ∈ [-2^63, 2^63) and value matches asIntN", () => {
		fc.assert(
			fc.property(bigIntArbI64, (b) => {
				const { value, lossless } = mod.losslessI64(b);
				const expected = oracleLosslessI64(b);
				return value === expected.value && lossless === expected.lossless;
			}),
			{
				numRuns: FUZZ_RUNS,
				examples: loadSeeds<bigint>("losslessI64", reviveBigInt),
			},
		);
	});
});

describe("losslessU64", () => {
	it("lossless ⇔ b ∈ [0, 2^64) and value matches asUintN", () => {
		fc.assert(
			fc.property(bigIntArbI64, (b) => {
				const { value, lossless } = mod.losslessU64(b);
				const expected = oracleLosslessU64(b);
				return value === expected.value && lossless === expected.lossless;
			}),
			{
				numRuns: FUZZ_RUNS,
				examples: loadSeeds<bigint>("losslessU64", reviveBigInt),
			},
		);
	});
});

const bigIntArbI128 = fc.oneof(
	{ arbitrary: fc.bigInt({ min: -(2n ** 129n), max: 2n ** 129n }), weight: 4 },
	{ arbitrary: fc.constantFrom(...edgeBigInts), weight: 1 },
);

describe("rtBigIntI128", () => {
	it("is exact in [-2^127, 2^127) and throws outside that range", () => {
		fc.assert(
			fc.property(bigIntArbI128, (b) => {
				if (fitsBigIntI128(b)) return mod.rtBigIntI128(b) === oracleBigIntI128(b);

				try {
					mod.rtBigIntI128(b);
					return false;
				} catch {
					return true;
				}
			}),
			{
				numRuns: FUZZ_RUNS,
				examples: loadSeeds<bigint>("rtBigIntI128", reviveBigInt),
			},
		);
	});
});

describe("rtBigIntI128LowBits", () => {
	it("matches BigInt.asIntN(128, ·)", () => {
		fc.assert(
			fc.property(
				bigIntArbI128,
				(b) => mod.rtBigIntI128LowBits(b) === oracleBigIntI128LowBits(b),
			),
			{
				numRuns: FUZZ_RUNS,
				examples: loadSeeds<bigint>("rtBigIntI128LowBits", reviveBigInt),
			},
		);
	});
});

const bigIntArbWords = fc.oneof(
	// Keep within the addon's 64-word cap (4096 bits).
	{
		arbitrary: fc.bigInt({ min: -(2n ** 4000n), max: 2n ** 4000n }),
		weight: 4,
	},
	{ arbitrary: fc.constantFrom(...edgeBigInts), weight: 1 },
);

describe("rtBigIntWords", () => {
	it("is identity for any BigInt under the word-buffer cap", () => {
		fc.assert(
			fc.property(bigIntArbWords, (b) => mod.rtBigIntWords(b) === b),
			{
				numRuns: FUZZ_RUNS,
				examples: loadSeeds<bigint>("rtBigIntWords", reviveBigInt),
			},
		);
	});
});
