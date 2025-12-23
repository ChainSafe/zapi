const napi_version = @import("build_options").napi_version;

pub usingnamespace @cImport({
    @cDefine("NAPI_VERSION", "10");
    // @cDefine("NAPI_VERSION", napi_version);
    @cInclude("node_api.h");
});
