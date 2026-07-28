const std = @import("std");
const zbuild = @import("zbuild");

pub fn build(b: *std.Build) !void {
    @setEvalBranchQuota(200_000);
    const manifest = @import("build.zig.zon");
    const result = try zbuild.configureBuild(b, manifest, .{});

    configureExampleAddonIdentities(b, manifest, result);
}

/// Makes the final addon's package and artifact identity available to its root
/// module as `@import("zapi_addon_identity")`. Distinct logical addons in one
/// package must use unique compile-step names and root modules.
pub fn addAddonIdentity(
    b: *std.Build,
    addon: *std.Build.Step.Compile,
    comptime manifest: anytype,
) void {
    const import_name = "zapi_addon_identity";
    if (addon.root_module.import_table.contains(import_name)) {
        @panic(
            "this root module already has a zapi addon identity; configure it once " ++
                "for aliases of the same addon, or create a separate root module " ++
                "for a distinct addon",
        );
    }

    const identity = b.addOptions();
    identity.addOption([]const u8, "package_name", @tagName(manifest.name));
    identity.addOption([]const u8, "package_version", manifest.version);
    identity.addOption(u64, "package_fingerprint", manifest.fingerprint);
    identity.addOption([]const u8, "addon_name", addon.name);
    addon.root_module.addOptions(import_name, identity);
}

fn configureExampleAddonIdentities(
    b: *std.Build,
    comptime manifest: anytype,
    result: zbuild.BuildResult,
) void {
    addAddonIdentity(b, result.library("example_js_dsl").?, manifest);
    addAddonIdentity(b, result.library("example_addon_isolation").?, manifest);
}
