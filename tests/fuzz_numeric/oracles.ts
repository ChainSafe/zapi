/**
 * Shared JS-side reference transforms for numeric fuzz targets.
 *
 * These are intentionally small and spec-shaped: the properties and oracle
 * sanity tests should import the same functions so they cannot drift.
 */

export const I64_MAX = (1n << 63n) - 1n;
export const I64_MIN = -(1n << 63n);
export const I128_MIN = -(1n << 127n);
export const I128_MAX = (1n << 127n) - 1n;

export function oracleNumberF64(value: number): number {
	return value;
}

export function oracleNumberI32(value: number): number {
	return value | 0;
}

export function oracleNumberU32(value: number): number {
	return value >>> 0;
}

export function oracleNumberI64(value: number): bigint {
	if (Number.isNaN(value) || !Number.isFinite(value)) return 0n;
	if (value >= 2 ** 63) return I64_MAX;
	if (value < -(2 ** 63)) return I64_MIN;
	return BigInt(Math.trunc(value));
}

export function oracleBigIntI64(value: bigint): bigint {
	return BigInt.asIntN(64, value);
}

export function oracleBigIntU64(value: bigint): bigint {
	return BigInt.asUintN(64, value);
}

export function oracleLosslessI64(value: bigint): {
	value: bigint;
	lossless: boolean;
} {
	const lossless = value >= I64_MIN && value <= I64_MAX;
	return { value: oracleBigIntI64(value), lossless };
}

export function oracleLosslessU64(value: bigint): {
	value: bigint;
	lossless: boolean;
} {
	const lossless = value >= 0n && value < 1n << 64n;
	return { value: oracleBigIntU64(value), lossless };
}

export function oracleBigIntI128(value: bigint): bigint {
	return value >= I128_MIN && value <= I128_MAX
		? value
		: BigInt.asIntN(128, value);
}
