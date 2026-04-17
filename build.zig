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
    b.modules.put(b.allocator, b.dupe("zapi"), module_zapi) catch @panic("OOM");

    const module_example_hello_world = b.createModule(.{
        .root_source_file = b.path("examples/hello_world/mod.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    b.modules.put(b.allocator, b.dupe("example_hello_world"), module_example_hello_world) catch @panic("OOM");

    const lib_example_hello_world = b.addLibrary(.{
        .name = "example_hello_world",
        .root_module = module_example_hello_world,
        .linkage = .dynamic,
    });

    lib_example_hello_world.linker_allow_shlib_undefined = true;
    const install_lib_example_hello_world = b.addInstallArtifact(lib_example_hello_world, .{
        .dest_sub_path = "example_hello_world.node",
    });

    const tls_install_lib_example_hello_world = b.step("build-lib:example_hello_world", "Install the example_hello_world library");
    tls_install_lib_example_hello_world.dependOn(&install_lib_example_hello_world.step);
    b.getInstallStep().dependOn(&install_lib_example_hello_world.step);

    const module_example_type_tag = b.createModule(.{
        .root_source_file = b.path("examples/type_tag/mod.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    b.modules.put(b.allocator, b.dupe("example_type_tag"), module_example_type_tag) catch @panic("OOM");

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

    const test_example_hello_world = b.addTest(.{
        .name = "example_hello_world",
        .root_module = module_example_hello_world,
        .filters = b.option([][]const u8, "example_hello_world.filters", "example_hello_world test filters") orelse &[_][]const u8{},
    });
    const install_test_example_hello_world = b.addInstallArtifact(test_example_hello_world, .{});
    const tls_install_test_example_hello_world = b.step("build-test:example_hello_world", "Install the example_hello_world test");
    tls_install_test_example_hello_world.dependOn(&install_test_example_hello_world.step);

    const run_test_example_hello_world = b.addRunArtifact(test_example_hello_world);
    const tls_run_test_example_hello_world = b.step("test:example_hello_world", "Run the example_hello_world test");
    tls_run_test_example_hello_world.dependOn(&run_test_example_hello_world.step);
    tls_run_test.dependOn(&run_test_example_hello_world.step);

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

    module_example_hello_world.addImport("zapi", module_zapi);

    module_example_type_tag.addImport("zapi", module_zapi);
}
