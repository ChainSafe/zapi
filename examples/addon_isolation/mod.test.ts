import { describe, expect, it } from "vitest";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const primary = require("../../zig-out/lib/example_js_dsl.node");
const secondary = require("../../zig-out/lib/example_addon_isolation.node");

describe("DSL class isolation across addons", () => {
	it("keeps matching class names isolated by addon", () => {
		const primaryCounter = new primary.Counter(1);
		const secondaryCounter = new secondary.Counter(2);

		expect(() => primary.incrementCounter(secondaryCounter)).toThrow();
		expect(() => secondary.incrementCounter(primaryCounter)).toThrow();
	});
});
