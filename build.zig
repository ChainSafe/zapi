const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const options_build_options = b.addOptions();
    const option_napi_version = b.option([]const u8, "napi_version", "") orelse "10";
    options_build_options.addOption([]const u8, "napi_version", option_napi_version);
    const options_module_build_options = options_build_options.createModule();

    const module_napi = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    module_napi.addIncludePath(b.path("include"));
    module_napi.addImport("build_options", options_module_build_options);
    b.modules.put(b.dupe("napi"), module_napi) catch @panic("OOM");

    const tls_run_test = b.step("test", "Run all tests");

    const test_napi = b.addTest(.{
        .name = "napi",
        .root_module = module_napi,
        .filters = b.option([][]const u8, "napi.filters", "napi test filters") orelse &[_][]const u8{},
    });
    const run_test_napi = b.addRunArtifact(test_napi);
    const tls_run_test_napi = b.step("test:napi", "Run the napi test");
    tls_run_test_napi.dependOn(&run_test_napi.step);
    tls_run_test.dependOn(&run_test_napi.step);

    // TODO: example_hello_world needs std.time.Timer/sleep migration (moved to std.Io)
}
