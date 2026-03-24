import { describe, it, expect } from "vitest";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const mod = require("../../zig-out/lib/example_js_dsl.node");

describe("js dsl - functions", () => {
    it("add two numbers", () => {
        expect(mod.add(1, 2)).toEqual(3);
    });

    it("add negative numbers", () => {
        expect(mod.add(-5, 3)).toEqual(-2);
    });

    it("greet returns formatted string", () => {
        expect(mod.greet("World")).toEqual("Hello, World!");
    });

    it("findValue returns index when found", () => {
        expect(mod.findValue([10, 20, 30], 20)).toEqual(1);
    });

    it("findValue returns undefined when not found", () => {
        expect(mod.findValue([10, 20, 30], 99)).toBeUndefined();
    });

    it("willThrow throws an error", () => {
        expect(() => mod.willThrow()).toThrow();
    });
});

describe("js dsl - Counter class", () => {
    it("creates counter with initial value", () => {
        const c = new mod.Counter(5);
        expect(c.getCount()).toEqual(5);
    });

    it("increments counter", () => {
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
