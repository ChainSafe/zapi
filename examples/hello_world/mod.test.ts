import { describe, it, expect } from "vitest";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const example = require("../../zig-out/lib/example_hello_world.node");

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

	it("shares mutable storage with an external Buffer", () => {
		const buffer = example.externalBuffer();
		expect(Buffer.isBuffer(buffer)).toBe(true);
		buffer[0] = 9;
		expect(example.externalBufferFirstByte()).toEqual(9);
	});
});
