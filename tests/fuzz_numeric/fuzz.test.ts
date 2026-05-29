import { describe, it } from "vitest";
import { createRequire } from "node:module";
import * as fs from "node:fs";
import * as path from "node:path";
import * as url from "node:url";
import fc from "fast-check";
import { edgeNumbers, edgeBigInts, edgeUint8Arrays } from "./edges.ts";
import {
	equalUint8Array,
	fitsBigIntI128,
	fitsBigIntI64,
	fitsBigIntU64,
	oracleBigIntI128,
	oracleBigIntI128LowBits,
	oracleLosslessI64,
	oracleLosslessU64,
	oracleNumberF64,
	oracleNumberI32,
	oracleNumberI64,
	oracleNumberU32,
	oracleUint8Array,
} from "./oracles.ts";

const require = createRequire(import.meta.url);
const mod = require("../../zig-out/lib/test_fuzz_numeric.node") as {
	rtNumberF64(n: number): number;
	rtNumberI32(n: number): number;
	rtNumberU32(n: number): number;
	rtNumberI64(n: number): bigint;
	rtBigIntI64(b: bigint): bigint;
	rtBigIntU64(b: bigint): bigint;
	losslessI64(b: bigint): { value: bigint; lossless: boolean };
	losslessU64(b: bigint): { value: bigint; lossless: boolean };
	rtBigIntI128(b: bigint): bigint;
	rtBigIntI128LowBits(b: bigint): bigint;
	rtBigIntWords(b: bigint): bigint;
	rtUint8Array(value: Uint8Array): Uint8Array;
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

function reviveUint8Array(raw: unknown): Uint8Array {
	if (Array.isArray(raw) && raw.every((v) => Number.isInteger(v))) {
		return new Uint8Array(raw);
	}
	throw new Error(`Cannot revive as Uint8Array: ${JSON.stringify(raw)}`);
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
