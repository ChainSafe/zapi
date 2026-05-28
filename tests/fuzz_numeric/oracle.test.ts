import { describe, it, expect } from "vitest";
import { createRequire } from "node:module";
import { edgeNumbers } from "./edges.ts";

const require = createRequire(import.meta.url);
const mod = require("../../zig-out/lib/test_fuzz_numeric.node") as {
	rtNumberF64(n: number): number;
};

/**
 * Oracle for rtNumberF64: identity over all finite JS numbers; NaN ↔ NaN;
 * ±0 preserved (distinguished via Object.is).
 */
function oracleF64(value: number): number {
	return value;
}

function describe_value(v: number): string {
	if (Number.isNaN(v)) return "NaN";
	if (Object.is(v, -0)) return "-0";
	return String(v);
}

describe("oracle sanity: rtNumberF64", () => {
	for (const v of edgeNumbers) {
		it(`agrees with oracle on ${describe_value(v)}`, () => {
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
