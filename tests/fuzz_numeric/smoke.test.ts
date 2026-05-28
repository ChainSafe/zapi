import { describe, it, expect } from "vitest";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const mod = require("../../zig-out/lib/test_fuzz_numeric.node");

describe("fuzz_numeric addon loads", () => {
	it("exports a ping function returning 42", () => {
		expect(mod.ping()).toEqual(42);
	});
});
