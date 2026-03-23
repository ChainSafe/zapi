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

    const module_example_type_tag = b.createModule(.{
        .root_source_file = b.path("examples/type_tag/mod.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    b.modules.put(b.dupe("example_type_tag"), module_example_type_tag) catch @panic("OOM");

    const lib_example_type_tag = b.addLibrary(.{
        .name = "example_type_tag",
        .root_module = module_example_type_tag,
        .linkage = .dynamic,
    });

    lib_example_type_tag.linker_allow_shlib_undefined = true;
    const install_lib_example_type_tag = b.addInstallArtifact(lib_example_type_tag, .{
        .dest_sub_path = "example_type_tag.node",
    });

    const tls_install_lib_example_type_tag = b.step("build-lib:example_type_tag", "Install the example_type_tag library");
    tls_install_lib_example_type_tag.dependOn(&install_lib_example_type_tag.step);
    b.getInstallStep().dependOn(&install_lib_example_type_tag.step);

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

    const test_example_type_tag = b.addTest(.{
        .name = "example_type_tag",
        .root_module = module_example_type_tag,
        .filters = b.option([][]const u8, "example_type_tag.filters", "example_type_tag test filters") orelse &[_][]const u8{},
    });
    const install_test_example_type_tag = b.addInstallArtifact(test_example_type_tag, .{});
    const tls_install_test_example_type_tag = b.step("build-test:example_type_tag", "Install the example_type_tag test");
    tls_install_test_example_type_tag.dependOn(&install_test_example_type_tag.step);

    const run_test_example_type_tag = b.addRunArtifact(test_example_type_tag);
    const tls_run_test_example_type_tag = b.step("test:example_type_tag", "Run the example_type_tag test");
    tls_run_test_example_type_tag.dependOn(&run_test_example_type_tag.step);
    tls_run_test.dependOn(&run_test_example_type_tag.step);

    module_napi.addImport("build_options", options_module_build_options);

    module_example_type_tag.addImport("napi", module_napi);
}
