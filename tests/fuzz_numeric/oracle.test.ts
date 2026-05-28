import { describe, it, expect } from "vitest";
import { createRequire } from "node:module";
import { edgeNumbers } from "./edges.ts";

const require = createRequire(import.meta.url);
const mod = require("../../zig-out/lib/test_fuzz_numeric.node") as {
	rtNumberF64(n: number): number;
	rtNumberI32(n: number): number;
	rtNumberU32(n: number): number;
	rtNumberI64(n: number): bigint;
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
