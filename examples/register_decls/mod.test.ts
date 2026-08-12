import { createRequire } from "node:module";
import { describe, expect, it } from "vitest";

const require = createRequire(import.meta.url);
const mod = require("../../zig-out/lib/example_register_decls.node");

describe("registerDecls", () => {
	it("registers functions and strings", () => {
		expect(mod.add(1, 2)).toEqual(3);
		expect(mod.greeting).toEqual("hello");
	});
});
