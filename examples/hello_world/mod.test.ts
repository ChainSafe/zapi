import { describe, it, expect } from "vitest";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const example = require("../../zig-out/lib/hello_world.node");

describe("example mod", () => {
	it("addon parameters", () => {
		expect(example.add(1, 2)).toEqual(3);
	});

	it("addon without parameters", () => {
		expect(example.surprise()).toEqual("Surprise!");
	});
});
