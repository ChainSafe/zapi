const napi_version = @import("build_options").napi_version;

pub const c = @cImport({
    @cDefine("NAPI_VERSION", napi_version);
    @cInclude("node_api.h");
});
