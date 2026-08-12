import {afterEach, describe, expect, it, vi} from "vitest";

afterEach(() => {
	vi.doUnmock("node:fs");
	vi.resetModules();
});

describe("aarch64 musl target", () => {
	it("maps package and Zig target metadata", async () => {
		const {getTargetParts} = await import("../../ts/config.js");
		const {TARGETS, getZigTriple} = await import("../../ts/lib.js");

		expect(TARGETS).toContain("aarch64-unknown-linux-musl");
		expect(getZigTriple("aarch64-unknown-linux-musl")).toBe("aarch64-linux-musl");
		expect(getTargetParts("aarch64-unknown-linux-musl")).toEqual({
			abi: "musl",
			arch: "arm64",
			platform: "linux",
		});
	});

	it("selects the target on an ARM64 musl runtime", async () => {
		vi.doMock("node:fs", async () => {
			const fs = await vi.importActual<typeof import("node:fs")>("node:fs");
			return {...fs, readFileSync: vi.fn(() => "musl libc")};
		});

		const {getTarget} = await import("../../ts/lib.js");

		expect(getTarget("linux", "arm64")).toBe("aarch64-unknown-linux-musl");
	});
});
