import { describe, it, expect } from "vitest";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const mod = require("../../zig-out/lib/example_js_dsl.node");

// Section 1: Basic Functions
describe("basic functions", () => {
	it("add two numbers", () => {
		expect(mod.add(1, 2)).toEqual(3);
	});

	it("add negative numbers", () => {
		expect(mod.add(-5, 3)).toEqual(-2);
	});

	it("greet returns formatted string", () => {
		expect(mod.greet("World")).toEqual("Hello, World!");
	});
});

// Section 2: Error Handling
describe("error handling", () => {
	it("safeDivide returns result", () => {
		expect(mod.safeDivide(10, 3)).toEqual(3);
	});

	it("safeDivide throws on zero", () => {
		expect(() => mod.safeDivide(10, 0)).toThrow();
	});

	it("findValue returns index when found", () => {
		expect(mod.findValue([10, 20, 30], 20)).toEqual(1);
	});

	it("findValue returns undefined when not found", () => {
		expect(mod.findValue([10, 20, 30], 99)).toBeUndefined();
	});
});

// Section 3: All Primitive Types
describe("primitive types", () => {
	it("doubleNumber", () => {
		expect(mod.doubleNumber(21)).toEqual(42);
	});

	it("toggleBool", () => {
		expect(mod.toggleBool(true)).toBe(false);
		expect(mod.toggleBool(false)).toBe(true);
	});

	it("reverseString", () => {
		expect(mod.reverseString("hello")).toEqual("olleh");
		expect(mod.reverseString("a")).toEqual("a");
	});

	it("doubleBigInt", () => {
		expect(mod.doubleBigInt(50n)).toEqual(100n);
	});

	it("tomorrow adds one day", () => {
		const now = new Date("2025-01-01T00:00:00Z");
		const result = mod.tomorrow(now);
		expect(result).toBeInstanceOf(Date);
		expect(result.toISOString()).toEqual("2025-01-02T00:00:00.000Z");
	});
});

// Section 4: Typed Objects
describe("typed objects", () => {
	it("formatConfig returns formatted string", () => {
		const config = { host: "localhost", port: 8080, verbose: true };
		expect(mod.formatConfig(config)).toEqual("localhost:8080 (verbose: true)");
	});

	it("formatConfig with verbose false", () => {
		const config = { host: "example.com", port: 443, verbose: false };
		expect(mod.formatConfig(config)).toEqual("example.com:443 (verbose: false)");
	});
});

// Section 5: Arrays
describe("arrays", () => {
	it("arraySum sums all elements", () => {
		expect(mod.arraySum([1, 2, 3, 4])).toEqual(10);
	});

	it("arraySum of empty array", () => {
		expect(mod.arraySum([])).toEqual(0);
	});

	it("arrayLength returns length", () => {
		expect(mod.arrayLength([10, 20, 30])).toEqual(3);
	});
});

// Section 6: TypedArrays
describe("typed arrays", () => {
	it("uint8Sum sums bytes", () => {
		const data = new Uint8Array([1, 2, 3, 4, 5]);
		expect(mod.uint8Sum(data)).toEqual(15);
	});

	it("float64Scale scales values", () => {
		const data = new Float64Array([1.0, 2.0, 3.0]);
		const result = mod.float64Scale(data, 2.5);
		expect(result).toBeInstanceOf(Float64Array);
		expect(Array.from(result)).toEqual([2.5, 5.0, 7.5]);
	});
});

// Section 7: Promises
describe("promises", () => {
	it("resolvedPromise resolves with value", async () => {
		const result = await mod.resolvedPromise(42);
		expect(result).toEqual(42);
	});
});

// Section 8: Callbacks
describe("callbacks", () => {
	it("applyCallback invokes function", () => {
		const result = mod.applyCallback(5, (n: number) => n * 3);
		expect(result).toEqual(15);
	});
});

// Section 9: Classes
describe("Counter class", () => {
	it("creates with initial value", () => {
		const c = new mod.Counter(5);
		expect(c.getCount()).toEqual(5);
	});

	it("increments", () => {
		const c = new mod.Counter(0);
		c.increment();
		c.increment();
		expect(c.getCount()).toEqual(2);
	});

	it("isAbove returns boolean", () => {
		const c = new mod.Counter(10);
		expect(c.isAbove(5)).toBe(true);
		expect(c.isAbove(15)).toBe(false);
	});
});

describe("Buffer class", () => {
	it("creates with size", () => {
		const b = new mod.Buffer(16);
		expect(b.getSize()).toEqual(16);
	});

	it("getByte returns zero-initialized data", () => {
		const b = new mod.Buffer(4);
		expect(b.getByte(0)).toEqual(0);
		expect(b.getByte(3)).toEqual(0);
	});

	it("getByte throws on out of bounds", () => {
		const b = new mod.Buffer(4);
		expect(() => b.getByte(4)).toThrow();
	});
});

// Section 10: Mixed DSL + N-API
describe("mixed DSL + N-API", () => {
	it("getTypeOf coerces value to string", () => {
		expect(mod.getTypeOf(42)).toEqual("42");
		expect(mod.getTypeOf(true)).toEqual("true");
		expect(mod.getTypeOf("hello")).toEqual("hello");
	});

	it("makeObject creates object with property", () => {
		const obj = mod.makeObject("x", 10);
		expect(obj).toEqual({ x: 10 });
	});
});
