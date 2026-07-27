import { execFileSync } from "node:child_process";
import { createRequire } from "node:module";
import { describe, expect, it } from "vitest";

const require = createRequire(import.meta.url);
const addonPath = require.resolve("../../zig-out/lib/example_hello_world.node");
const example = require(addonPath);

describe("example mod", () => {
	it("addon parameters", () => {
		expect(example.add(1, 2)).toEqual(3);
	});

	it("addon without parameters", () => {
		expect(example.surprise()).toEqual("Surprise!");
	});

	it("copies immutable input into independently writable buffers", () => {
		const arrayBuffer = example.copyArrayBuffer(false);
		const arrayBufferBytes = new Uint8Array(arrayBuffer);
		expect(new TextDecoder().decode(arrayBufferBytes)).toEqual("copy me");
		arrayBufferBytes[0] = "C".charCodeAt(0);
		expect(new TextDecoder().decode(arrayBufferBytes)).toEqual("Copy me");
		expect(new TextDecoder().decode(new Uint8Array(example.copyArrayBuffer(false)))).toEqual(
			"copy me"
		);

		const buffer = example.copyBuffer();
		expect(Buffer.isBuffer(buffer)).toBe(true);
		buffer[0] = "C".charCodeAt(0);
		expect(buffer.toString()).toEqual("Copy me");
		expect(example.copyBuffer().toString()).toEqual("copy me");
	});

	it("copies empty input into an empty ArrayBuffer", () => {
		const arrayBuffer = example.copyArrayBuffer(true);
		expect(arrayBuffer).toBeInstanceOf(ArrayBuffer);
		expect(arrayBuffer.byteLength).toEqual(0);
	});

	it("copies mutable slices returned without an external hint", () => {
		const buffer = example.copySlice();
		buffer[0] = 9;
		expect(example.copySlice()[0]).toEqual(1);
	});

	it("returns an allocator-owned external Buffer", () => {
		const buffer = example.externalBuffer();
		expect(Buffer.isBuffer(buffer)).toBe(true);
		expect([...buffer]).toEqual([1, 2, 3]);
		buffer[0] = 9;
		expect([...buffer]).toEqual([9, 2, 3]);
	});

	it("releases an external Buffer through its GC finalizer", () => {
		const script = `
			const addon = require(${JSON.stringify(addonPath)});
			const baseline = addon.externalBufferFinalizedCount();
			let buffer = addon.externalBuffer();
			if (addon.externalBufferFinalizedCount() !== baseline) {
				throw new Error("external Buffer was released while still reachable");
			}
			buffer = null;

			const deadline = Date.now() + 5000;
			function collect() {
				global.gc();
				const finalized = addon.externalBufferFinalizedCount();
				if (finalized === baseline + 1) return;
				if (finalized > baseline + 1) {
					throw new Error("external Buffer was finalized more than once");
				}
				if (Date.now() >= deadline) {
					throw new Error("external Buffer finalizer did not run");
				}
				setImmediate(collect);
			}
			setImmediate(collect);
		`;

		execFileSync(process.execPath, ["--expose-gc", "-e", script], {
			stdio: "pipe",
			timeout: 10_000,
		});
	});
});
