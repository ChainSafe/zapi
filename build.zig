const std = @import("std");
const zbuild = @import("zbuild");

pub fn build(b: *std.Build) !void {
    @setEvalBranchQuota(200_000);
    const result = try zbuild.configureBuild(b, @import("build.zig.zon"), .{});

    // Example tests reference napi C symbols (`napi_wrap`, `napi_typeof`, …)
    // which Node provides at dlopen time. Standalone zig test binaries don't
    // have Node around, so allow undefined shared-library symbols. zbuild
    // exposes this option only for libraries; apply it post-hoc to tests.
    for ([_][]const u8{ "example_hello_world", "example_type_tag", "example_js_dsl" }) |name| {
        if (result.testArtifact(name)) |t| {
            t.linker_allow_shlib_undefined = true;
        }
    }
}
