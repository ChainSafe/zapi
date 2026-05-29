import { describe, it, expect } from "vitest";
import { createRequire } from "node:module";
import { edgeNumbers, edgeBigInts } from "./edges.ts";
import {
	I128_MAX,
	I128_MIN,
	oracleBigIntI128,
	oracleBigIntI64,
	oracleBigIntU64,
	oracleLosslessI64,
	oracleLosslessU64,
	oracleNumberF64,
	oracleNumberI32,
	oracleNumberI64,
	oracleNumberU32,
} from "./oracles.ts";

const require = createRequire(import.meta.url);
const mod = require("../../zig-out/lib/test_fuzz_numeric.node") as {
	rtNumberF64(n: number): number;
	rtNumberI32(n: number): number;
	rtNumberU32(n: number): number;
	rtNumberI64(n: number): bigint;
	rtBigIntI64(b: bigint): bigint;
	rtBigIntU64(b: bigint): bigint;
};

function describeValue(v: number): string {
	if (Number.isNaN(v)) return "NaN";
	if (Object.is(v, -0)) return "-0";
	return String(v);
}

describe("oracle sanity: rtNumberF64", () => {
	for (const v of edgeNumbers) {
		it(`agrees with oracle on ${describeValue(v)}`, () => {
			const expected = oracleNumberF64(v);
			const actual = mod.rtNumberF64(v);
			if (Number.isNaN(expected)) {
				expect(Number.isNaN(actual)).toBe(true);
			} else {
				expect(Object.is(actual, expected)).toBe(true);
			}
		});
	}
});

describe("oracle sanity: rtNumberI32", () => {
	for (const v of edgeNumbers) {
		it(`agrees with oracle on ${describeValue(v)}`, () => {
			expect(mod.rtNumberI32(v)).toBe(oracleNumberI32(v));
		});
	}
});

describe("oracle sanity: rtNumberU32", () => {
	for (const v of edgeNumbers) {
		it(`agrees with oracle on ${describeValue(v)}`, () => {
			expect(mod.rtNumberU32(v)).toBe(oracleNumberU32(v));
		});
	}
});

describe("oracle sanity: rtNumberI64", () => {
	for (const v of edgeNumbers) {
		it(`agrees with oracle on ${describeValue(v)}`, () => {
			expect(mod.rtNumberI64(v)).toBe(oracleNumberI64(v));
		});
	}
});

describe("oracle sanity: rtBigIntI64", () => {
	for (const b of edgeBigInts) {
		it(`agrees with oracle on ${b}n`, () => {
			expect(mod.rtBigIntI64(b)).toBe(oracleBigIntI64(b));
		});
	}
});

describe("oracle sanity: rtBigIntU64", () => {
	for (const b of edgeBigInts) {
		it(`agrees with oracle on ${b}n`, () => {
			expect(mod.rtBigIntU64(b)).toBe(oracleBigIntU64(b));
		});
	}
});

const modL = require("../../zig-out/lib/test_fuzz_numeric.node") as {
	losslessI64(b: bigint): { value: bigint; lossless: boolean };
	losslessU64(b: bigint): { value: bigint; lossless: boolean };
};

describe("oracle sanity: losslessI64", () => {
	for (const b of edgeBigInts) {
		it(`agrees with oracle on ${b}n`, () => {
			expect(modL.losslessI64(b)).toEqual(oracleLosslessI64(b));
		});
	}
});

describe("oracle sanity: losslessU64", () => {
	for (const b of edgeBigInts) {
		it(`agrees with oracle on ${b}n`, () => {
			expect(modL.losslessU64(b)).toEqual(oracleLosslessU64(b));
		});
	}
});

const modI128 = require("../../zig-out/lib/test_fuzz_numeric.node") as {
	rtBigIntI128(b: bigint): bigint;
};

describe("oracle sanity: rtBigIntI128", () => {
	for (const b of edgeBigInts) {
		// Only assert identity in-range. Out-of-range edges are out of scope
		// for the oracle test — the property test handles them via the
		// implementation-defined policy (see fuzz.test.ts).
		if (b < I128_MIN || b > I128_MAX) continue;
		it(`round-trips ${b}n`, () => {
			expect(modI128.rtBigIntI128(b)).toBe(b);
		});
	}
});

describe("rtBigIntI128 boundary cases", () => {
	it("0n → 0n (zero)", () => {
		expect(modI128.rtBigIntI128(0n)).toBe(0n);
	});

	it("I128_MIN = -(1n << 127n) → -(1n << 127n) (in-range lower bound)", () => {
		const b = -(1n << 127n);
		expect(modI128.rtBigIntI128(b)).toBe(b);
	});

	it("I128_MAX = (1n << 127n) - 1n → (1n << 127n) - 1n (in-range upper bound)", () => {
		const b = (1n << 127n) - 1n;
		expect(modI128.rtBigIntI128(b)).toBe(b);
	});

	it("1n << 127n (just out-of-range positive) → BigInt.asIntN(128, 1n << 127n) === -(1n << 127n)", () => {
		const b = 1n << 127n;
		expect(modI128.rtBigIntI128(b)).toBe(oracleBigIntI128(b));
	});

	it("-(1n << 127n) - 1n (just out-of-range negative) → BigInt.asIntN(128, -(1n << 127n) - 1n)", () => {
		const b = -(1n << 127n) - 1n;
		expect(modI128.rtBigIntI128(b)).toBe(oracleBigIntI128(b));
	});

	it("1n << 128n (oversized positive, low 128 bits zero) → 0n", () => {
		expect(modI128.rtBigIntI128(1n << 128n)).toBe(0n);
	});

	it("-(1n << 128n) (oversized negative, low 128 bits zero) → 0n", () => {
		expect(modI128.rtBigIntI128(-(1n << 128n))).toBe(0n);
	});
});

const modW = require("../../zig-out/lib/test_fuzz_numeric.node") as {
	rtBigIntWords(b: bigint): bigint;
};

describe("oracle sanity: rtBigIntWords", () => {
	for (const b of edgeBigInts) {
		it(`round-trips ${b}n`, () => {
			expect(modW.rtBigIntWords(b)).toBe(b);
		});
	}
});
