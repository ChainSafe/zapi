import { copyFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { describe, expect, it } from "vitest";

const require = createRequire(import.meta.url);
const primaryPath = require.resolve("../../zig-out/lib/example_js_dsl.node");
const primary = require(primaryPath);
const secondary = require("../../zig-out/lib/example_addon_isolation.node");
const duplicatePath = join(dirname(primaryPath), "example_js_dsl_duplicate.node");
copyFileSync(primaryPath, duplicatePath);
const duplicate = require(duplicatePath);

describe("DSL class isolation across addons", () => {
	it("keeps matching class names isolated by addon", () => {
		const primaryCounter = new primary.Counter(1);
		const secondaryCounter = new secondary.Counter(2);

		primary.incrementCounter(primaryCounter);
		secondary.incrementCounter(secondaryCounter);
		expect(primaryCounter.getCount()).toBe(2);
		expect(secondaryCounter.getCount()).toBe(3);

		expect(() => primary.incrementCounter(secondaryCounter)).toThrow(TypeError);
		expect(() => secondary.incrementCounter(primaryCounter)).toThrow(TypeError);
	});

	it("keeps class identity across two loaded copies of one addon", () => {
		const primaryCounter = new primary.Counter(1);
		const duplicateCounter = new duplicate.Counter(2);

		primary.incrementCounter(duplicateCounter);
		duplicate.incrementCounter(primaryCounter);
		expect(primaryCounter.getCount()).toBe(2);
		expect(duplicateCounter.getCount()).toBe(3);
	});
});
