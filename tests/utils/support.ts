import { createRequire } from "node:module";
import * as fs from "node:fs";
import * as path from "node:path";
import * as url from "node:url";

export type FuzzAddon = {
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

const require = createRequire(import.meta.url);

export const mod = require("../../zig-out/lib/test_fuzz_numeric.node") as FuzzAddon;
export const FUZZ_RUNS = Number(process.env.FUZZ_RUNS ?? 10_000);

const __dirname = path.dirname(url.fileURLToPath(import.meta.url));
const seedsDir = path.join(__dirname, "../fuzz/seeds");

/**
 * Load persisted regression cases for a target.
 *
 * Each file under tests/fuzz/seeds/ is a JSON array of values.
 * Missing file -> empty examples list; not an error.
 */
export function loadSeeds<T>(target: string, revive: (raw: unknown) => T): T[] {
	const file = path.join(seedsDir, `${target}.json`);
	if (!fs.existsSync(file)) return [];
	const raw = JSON.parse(fs.readFileSync(file, "utf8")) as unknown[];
	return raw.map(revive);
}

export function reviveBigInt(raw: unknown): bigint {
	if (typeof raw === "object" && raw !== null && "__bigint" in raw) {
		return BigInt((raw as { __bigint: string }).__bigint);
	}
	throw new Error(`Cannot revive as bigint: ${JSON.stringify(raw)}`);
}

export function reviveUint8Array(raw: unknown): Uint8Array {
	if (Array.isArray(raw) && raw.every((v) => Number.isInteger(v))) {
		return new Uint8Array(raw);
	}
	throw new Error(`Cannot revive as Uint8Array: ${JSON.stringify(raw)}`);
}
