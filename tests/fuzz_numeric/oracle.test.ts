import { describe, it, expect } from "vitest";
import { createRequire } from "node:module";
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
		it(`is exact-or-throw on ${b}n`, () => {
			if (fitsBigIntI64(b)) {
				expect(mod.rtBigIntI64(b)).toBe(b);
			} else {
				expect(() => mod.rtBigIntI64(b)).toThrow();
			}
		});
	}
});

describe("oracle sanity: rtBigIntU64", () => {
	for (const b of edgeBigInts) {
		it(`is exact-or-throw on ${b}n`, () => {
			if (fitsBigIntU64(b)) {
				expect(mod.rtBigIntU64(b)).toBe(b);
			} else {
				expect(() => mod.rtBigIntU64(b)).toThrow();
			}
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
	rtBigIntI128LowBits(b: bigint): bigint;
};

describe("oracle sanity: rtBigIntI128", () => {
	for (const b of edgeBigInts) {
		it(`is exact-or-throw on ${b}n`, () => {
			if (fitsBigIntI128(b)) {
				expect(modI128.rtBigIntI128(b)).toBe(oracleBigIntI128(b));
			} else {
				expect(() => modI128.rtBigIntI128(b)).toThrow();
			}
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

	it("1n << 127n (just out-of-range positive) throws", () => {
		const b = 1n << 127n;
		expect(() => modI128.rtBigIntI128(b)).toThrow();
	});

	it("-(1n << 127n) - 1n (just out-of-range negative) throws", () => {
		const b = -(1n << 127n) - 1n;
		expect(() => modI128.rtBigIntI128(b)).toThrow();
	});

	it("1n << 128n (oversized positive) throws", () => {
		expect(() => modI128.rtBigIntI128(1n << 128n)).toThrow();
	});

	it("-(1n << 128n) (oversized negative) throws", () => {
		expect(() => modI128.rtBigIntI128(-(1n << 128n))).toThrow();
	});
});

describe("oracle sanity: rtBigIntI128LowBits", () => {
	for (const b of edgeBigInts) {
		it(`agrees with low-bits oracle on ${b}n`, () => {
			expect(modI128.rtBigIntI128LowBits(b)).toBe(oracleBigIntI128LowBits(b));
		});
	}
});

const modW = require("../../zig-out/lib/test_fuzz_numeric.node") as {
	rtBigIntWords(b: bigint): bigint;
	rtUint8Array(value: Uint8Array): Uint8Array;
};

describe("oracle sanity: rtBigIntWords", () => {
	for (const b of edgeBigInts) {
		it(`round-trips ${b}n`, () => {
			expect(modW.rtBigIntWords(b)).toBe(b);
		});
	}
});

describe("oracle sanity: rtUint8Array", () => {
	for (const value of edgeUint8Arrays) {
		it(`round-trips ${value.length} byte(s)`, () => {
			expect(equalUint8Array(modW.rtUint8Array(value), oracleUint8Array(value))).toBe(
				true,
			);
		});
	}
});
