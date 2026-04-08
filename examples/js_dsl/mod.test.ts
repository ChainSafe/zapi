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

	it("largeUnsignedBoundary survives u64 values above i64 max", () => {
		const value = mod.largeUnsignedBoundary();
		expect(Number.isFinite(value)).toBe(true);
		expect(value).toEqual(2 ** 63);
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

// Section 11: Module Lifecycle
describe("module lifecycle", () => {
	it("init was called at least once", () => {
		expect(mod.getInitCount()).toBeGreaterThanOrEqual(1);
	});

	it("first init received refcount 0", () => {
		expect(mod.getFirstRefcount()).toEqual(0);
	});

	it("current refcount is at least 1", () => {
		expect(mod.getEnvRefcount()).toBeGreaterThanOrEqual(1);
	});
});

// Section 12: Nested Namespaces
describe("nested namespaces", () => {
	it("math.multiply", () => {
		expect(mod.math.multiply(3, 4)).toEqual(12);
	});

	it("math.square", () => {
		expect(mod.math.square(5)).toEqual(25);
	});

	it("math.utils.clamp within range", () => {
		expect(mod.math.utils.clamp(5, 0, 10)).toEqual(5);
	});

	it("math.utils.clamp below min", () => {
		expect(mod.math.utils.clamp(-5, 0, 10)).toEqual(0);
	});

	it("math.utils.clamp above max", () => {
		expect(mod.math.utils.clamp(15, 0, 10)).toEqual(10);
	});
});

// Section 13: Static Factory Methods + Optional Parameters
describe("static factories", () => {
	it("Point.create returns new instance", () => {
		const p = mod.Point.create(3, 4);
		expect(p.getX()).toEqual(3);
		expect(p.getY()).toEqual(4);
	});

	it("Point.fromArray without offset", () => {
		const p = mod.Point.fromArray([10, 20]);
		expect(p.getX()).toEqual(10);
		expect(p.getY()).toEqual(20);
	});

	it("Point.fromArray with offset", () => {
		const p = mod.Point.fromArray([0, 0, 5, 7], 2);
		expect(p.getX()).toEqual(5);
		expect(p.getY()).toEqual(7);
	});

	it("new Point() creates zero point", () => {
		const p = new mod.Point();
		expect(p.getX()).toEqual(0);
		expect(p.getY()).toEqual(0);
	});

	it("preserves subclass constructor for same-class static returns", () => {
		class DerivedPoint extends mod.Point {}
		const p = DerivedPoint.create(3, 4);
		expect(p).toBeInstanceOf(DerivedPoint);
		expect(p.getX()).toEqual(3);
	});
});

describe("optional parameters", () => {
	it("translate with both args", () => {
		const p = mod.Point.create(1, 1);
		p.translate(5, 10);
		expect(p.getX()).toEqual(6);
		expect(p.getY()).toEqual(11);
	});

	it("translate with optional omitted", () => {
		const p = mod.Point.create(1, 1);
		p.translate(5);
		expect(p.getX()).toEqual(6);
		expect(p.getY()).toEqual(1);
	});

	it("translate treats explicit undefined like omitted optional", () => {
		const p = mod.Point.create(1, 1);
		p.translate(5, undefined);
		expect(p.getX()).toEqual(6);
		expect(p.getY()).toEqual(1);
	});

	it("fromArray treats explicit undefined like omitted optional", () => {
		const p = mod.Point.fromArray([10, 20], undefined);
		expect(p.getX()).toEqual(10);
		expect(p.getY()).toEqual(20);
	});
});

describe("class materialization", () => {
	it("static class return avoids constructor placeholder allocation", () => {
		const initBefore = mod.getFactoryResourceInitCount();
		const deinitBefore = mod.getFactoryResourceDeinitCount();

		const resource = mod.FactoryResource.withByte(7);

		expect(resource.getByte()).toEqual(7);
		expect(mod.getFactoryResourceInitCount()).toEqual(initBefore + 1);
		expect(mod.getFactoryResourceDeinitCount()).toEqual(deinitBefore);
	});

	it("instance class return avoids constructor placeholder allocation", () => {
		const base = mod.FactoryResource.withByte(1);
		const initBefore = mod.getFactoryResourceInitCount();
		const deinitBefore = mod.getFactoryResourceDeinitCount();

		const clone = base.cloneWithByte(9);

		expect(clone.getByte()).toEqual(9);
		expect(mod.getFactoryResourceInitCount()).toEqual(initBefore + 1);
		expect(mod.getFactoryResourceDeinitCount()).toEqual(deinitBefore);
	});

	it("preserves subclass constructor for same-class instance returns", () => {
		class DerivedFactoryResource extends mod.FactoryResource {}
		const base = DerivedFactoryResource.withByte(1);
		const clone = base.cloneWithByte(9);
		expect(clone).toBeInstanceOf(DerivedFactoryResource);
		expect(clone.getByte()).toEqual(9);
	});
});

// Section 15: Getters and Setters
describe("Settings class (getters/setters)", () => {
	it("has getter for volume with default value", () => {
		const s = new mod.Settings();
		expect(s.volume).toEqual(50);
	});

	it("has setter for volume", () => {
		const s = new mod.Settings();
		s.volume = 80;
		expect(s.volume).toEqual(80);
	});

	it("setter validates volume range", () => {
		const s = new mod.Settings();
		expect(() => { s.volume = 101; }).toThrow();
		expect(() => { s.volume = -1; }).toThrow();
		expect(s.volume).toEqual(50); // unchanged after errors
	});

	it("has getter/setter for muted", () => {
		const s = new mod.Settings();
		expect(s.muted).toBe(false);
		s.muted = true;
		expect(s.muted).toBe(true);
	});

	it("has read-only getter for label", () => {
		const s = new mod.Settings();
		expect(s.label).toEqual("default");
		// In ESM strict mode, assigning to a getter-only property throws TypeError
		expect(() => { (s as any).label = "changed"; }).toThrow();
	});

	it("has read-only field-backed property", () => {
		const s = new mod.Settings();
		expect(s.kind).toEqual("settings");
		expect(() => { (s as any).kind = "changed"; }).toThrow();
	});

	it("getter is not callable as a method", () => {
		const s = new mod.Settings();
		expect(typeof s.volume).toBe("number");
		expect(typeof s.volume).not.toBe("function");
	});

	it("reset method still works alongside getters", () => {
		const s = new mod.Settings();
		s.volume = 80;
		s.muted = true;
		s.reset();
		expect(s.volume).toEqual(50);
		expect(s.muted).toBe(false);
	});

	it("multiple instances have independent state", () => {
		const s1 = new mod.Settings();
		const s2 = new mod.Settings();
		s1.volume = 10;
		s2.volume = 90;
		expect(s1.volume).toEqual(10);
		expect(s2.volume).toEqual(90);
	});
});

describe("class return interop", () => {
	it("free function returning class materializes a Token instance", () => {
		const token = mod.makeToken(4);
		expect(token).toBeInstanceOf(mod.Token);
		expect(token.getValue()).toEqual(5);
	});

	it("instance method returning different class materializes a Token instance", () => {
		const issuer = new mod.TokenIssuer(6);
		const token = issuer.issue();
		expect(token).toBeInstanceOf(mod.Token);
		expect(token.getValue()).toEqual(12);
	});
});

describe("module lifecycle - worker threads", () => {
	it("worker thread increments refcount and cleanup decrements it", async () => {
		const { Worker } = await import("node:worker_threads");
		const { resolve } = await import("node:path");
		const { fileURLToPath } = await import("node:url");

		const refcountBefore = mod.getEnvRefcount();

		// Build an absolute path to the .node file so the worker can load it
		const thisDir = fileURLToPath(new URL(".", import.meta.url));
		const nativePath = resolve(thisDir, "../../zig-out/lib/example_js_dsl.node");

		// Spawn a worker that loads the same native module
		const worker = new Worker(
			`
			const { parentPort, workerData } = require("node:worker_threads");
			const m = require(workerData.nativePath);
			parentPort.postMessage({ refcount: m.getEnvRefcount() });
			`,
			{ eval: true, workerData: { nativePath } },
		);

		// Worker should see an incremented refcount
		const workerRefcount = await new Promise((resolve) => {
			worker.on("message", (msg) => {
				resolve(msg.refcount);
			});
		});
		expect(workerRefcount).toBeGreaterThan(refcountBefore);

		// Wait for worker to exit (triggers cleanup hook)
		await new Promise((resolve) => {
			worker.on("exit", () => resolve(undefined));
		});

		// After worker exits, refcount should be back to what it was
		// Give a small delay for cleanup hook to fire
		await new Promise((resolve) => setTimeout(resolve, 100));
		expect(mod.getEnvRefcount()).toEqual(refcountBefore);
	});
});
