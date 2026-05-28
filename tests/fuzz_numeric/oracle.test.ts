import { describe, it, expect } from "vitest";
import { createRequire } from "node:module";
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

/**
 * Oracle for rtNumberF64: identity over all finite JS numbers; NaN ↔ NaN;
 * ±0 preserved (distinguished via Object.is).
 */
function oracleF64(value: number): number {
	return value;
}

function describeValue(v: number): string {
	if (Number.isNaN(v)) return "NaN";
	if (Object.is(v, -0)) return "-0";
	return String(v);
}

describe("oracle sanity: rtNumberF64", () => {
	for (const v of edgeNumbers) {
		it(`agrees with oracle on ${describeValue(v)}`, () => {
			const expected = oracleF64(v);
			const actual = mod.rtNumberF64(v);
			if (Number.isNaN(expected)) {
				expect(Number.isNaN(actual)).toBe(true);
			} else {
				expect(Object.is(actual, expected)).toBe(true);
			}
		});
	}
});

/** ECMAScript ToInt32: `value | 0`. NaN/±Inf → 0. */
function oracleI32(value: number): number {
	return value | 0;
}

/** ECMAScript ToUint32: `value >>> 0`. NaN/±Inf → 0. */
function oracleU32(value: number): number {
	return value >>> 0;
}

/**
 * NAPI napi_get_value_int64 semantics (per Node.js NAPI docs):
 *   - NaN, ±Infinity → 0
 *   - value >= 2^63 → INT64_MAX (clamped, not zero)
 *   - value < -2^63 → INT64_MIN (clamped)
 *   - exact -2^63 → INT64_MIN (representable, returned faithfully)
 *   - otherwise: BigInt(Math.trunc(value)) interpreted as i64
 *
 * Returned as a JS bigint so the JS comparison stays lossless.
 */
const I64_MAX = (1n << 63n) - 1n;
const I64_MIN = -(1n << 63n);

function oracleI64(value: number): bigint {
	if (Number.isNaN(value) || !Number.isFinite(value)) return 0n;
	if (value >= 2 ** 63) return I64_MAX;
	if (value < -(2 ** 63)) return I64_MIN;
	return BigInt(Math.trunc(value));
}

describe("oracle sanity: rtNumberI32", () => {
	for (const v of edgeNumbers) {
		it(`agrees with oracle on ${describeValue(v)}`, () => {
			expect(mod.rtNumberI32(v)).toBe(oracleI32(v));
		});
	}
});

describe("oracle sanity: rtNumberU32", () => {
	for (const v of edgeNumbers) {
		it(`agrees with oracle on ${describeValue(v)}`, () => {
			expect(mod.rtNumberU32(v)).toBe(oracleU32(v));
		});
	}
});

describe("oracle sanity: rtNumberI64", () => {
	for (const v of edgeNumbers) {
		it(`agrees with oracle on ${describeValue(v)}`, () => {
			expect(mod.rtNumberI64(v)).toBe(oracleI64(v));
		});
	}
});

/** Two's-complement low 64 bits, signed. */
function oracleBigIntI64(b: bigint): bigint {
	return BigInt.asIntN(64, b);
}

/** Low 64 bits, unsigned. */
function oracleBigIntU64(b: bigint): bigint {
	return BigInt.asUintN(64, b);
}

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

function expectedLosslessI64(b: bigint): { value: bigint; lossless: boolean } {
	const losslessRange = b >= -(1n << 63n) && b < 1n << 63n;
	return { value: BigInt.asIntN(64, b), lossless: losslessRange };
}

function expectedLosslessU64(b: bigint): { value: bigint; lossless: boolean } {
	const losslessRange = b >= 0n && b < 1n << 64n;
	return { value: BigInt.asUintN(64, b), lossless: losslessRange };
}

describe("oracle sanity: losslessI64", () => {
	for (const b of edgeBigInts) {
		it(`agrees with oracle on ${b}n`, () => {
			expect(modL.losslessI64(b)).toEqual(expectedLosslessI64(b));
		});
	}
});

describe("oracle sanity: losslessU64", () => {
	for (const b of edgeBigInts) {
		it(`agrees with oracle on ${b}n`, () => {
			expect(modL.losslessU64(b)).toEqual(expectedLosslessU64(b));
		});
	}
});

const modI128 = require("../../zig-out/lib/test_fuzz_numeric.node") as {
	rtBigIntI128(b: bigint): bigint;
};

const I128_MIN = -(1n << 127n);
const I128_MAX = (1n << 127n) - 1n;

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
		expect(modI128.rtBigIntI128(b)).toBe(BigInt.asIntN(128, b));
	});

	it("-(1n << 127n) - 1n (just out-of-range negative) → BigInt.asIntN(128, -(1n << 127n) - 1n)", () => {
		const b = -(1n << 127n) - 1n;
		expect(modI128.rtBigIntI128(b)).toBe(BigInt.asIntN(128, b));
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
