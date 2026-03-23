import { describe, it, expect } from "vitest";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const mod = require("../../zig-out/lib/example_type_tag.node");

describe("type-tagged classes", () => {
	it("Cat.name() returns the name", () => {
		const cat = new mod.Cat("Whiskers");
		expect(cat.name()).toEqual("Whiskers");
	});

	it("Dog.name() returns the name", () => {
		const dog = new mod.Dog("Buddy");
		expect(dog.name()).toEqual("Buddy");
	});

	it("calling Cat.name() on a Dog throws (type tag mismatch)", () => {
		const dog = new mod.Dog("Buddy");
		const cat = new mod.Cat("Whiskers");

		// Steal Cat's prototype method and call it with a Dog as `this`.
		// unwrapChecked should reject this with InvalidArg.
		expect(() => {
			mod.Cat.prototype.name.call(dog);
		}).toThrow();

		// And the reverse
		expect(() => {
			mod.Dog.prototype.name.call(cat);
		}).toThrow();
	});
});
