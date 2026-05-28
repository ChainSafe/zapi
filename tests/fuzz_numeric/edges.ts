/**
 * Hand-curated edge values that any decent numeric converter should handle.
 * Mixed into fast-check generators via fc.constantFrom(...).
 *
 * BigInt list is added incrementally as BigInt-targeting tasks land.
 */

export const edgeNumbers: readonly number[] = [
	0,
	-0,
	NaN,
	Infinity,
	-Infinity,
	Number.MIN_VALUE,
	-Number.MIN_VALUE,
	Number.MAX_SAFE_INTEGER,
	-Number.MAX_SAFE_INTEGER,
	2 ** 31,
	-(2 ** 31),
	2 ** 31 - 1,
	-(2 ** 31) - 1,
	2 ** 32,
	2 ** 32 - 1,
	2 ** 53,
	2 ** 53 + 1,
	2 ** 63,
	-(2 ** 63),
];

export const edgeBigInts: readonly bigint[] = [
	0n,
	1n,
	-1n,
	1n << 63n,
	-(1n << 63n),
	(1n << 63n) - 1n,
	-((1n << 63n) - 1n),
	1n << 64n,
	(1n << 64n) - 1n,
	-(1n << 64n),
];
