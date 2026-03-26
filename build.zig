const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const options_build_options = b.addOptions();
    const option_napi_version = b.option([]const u8, "napi_version", "") orelse "10";
    options_build_options.addOption([]const u8, "napi_version", option_napi_version);
    const options_module_build_options = options_build_options.createModule();

    const module_zapi = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    module_zapi.addIncludePath(b.path("include"));
    b.modules.put(b.dupe("zapi"), module_zapi) catch @panic("OOM");

    // TODO: example_hello_world needs std.time.Timer/sleep migration (moved to std.Io in 0.16)

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

    const test_zapi = b.addTest(.{
        .name = "zapi",
        .root_module = module_zapi,
        .filters = b.option([][]const u8, "zapi.filters", "zapi test filters") orelse &[_][]const u8{},
    });
    const install_test_zapi = b.addInstallArtifact(test_zapi, .{});
    const tls_install_test_zapi = b.step("build-test:zapi", "Install the zapi test");
    tls_install_test_zapi.dependOn(&install_test_zapi.step);

    const run_test_zapi = b.addRunArtifact(test_zapi);
    const tls_run_test_zapi = b.step("test:zapi", "Run the zapi test");
    tls_run_test_zapi.dependOn(&run_test_zapi.step);
    tls_run_test.dependOn(&run_test_zapi.step);

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

    module_zapi.addImport("build_options", options_module_build_options);

    module_example_type_tag.addImport("zapi", module_zapi);
}
