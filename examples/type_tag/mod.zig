///! Demonstrates type-tagged wrapping with unwrapChecked / removeWrapChecked.
///!
///! Type tags let you verify at runtime that a JS object wraps the expected
///! native type. Without them, passing the wrong `this` (e.g. a Dog to a Cat
///! method) silently reinterprets memory. With unwrapChecked the mismatch is
///! caught and returns error.InvalidArg instead.
const std = @import("std");
const napi = @import("zapi");
const allocator = std.heap.page_allocator;

comptime {
    napi.module.register(typeTagMod);
}

fn typeTagMod(env: napi.Env, module: napi.Value) anyerror!void {
    try module.setNamedProperty(
        "Cat",
        try env.defineClass(
            "Cat",
            1,
            Cat_ctor,
            null,
            &[_]napi.c.napi_property_descriptor{.{
                .utf8name = "name",
                .method = napi.wrapCallback(0, Cat_name),
            }},
        ),
    );

    try module.setNamedProperty(
        "Dog",
        try env.defineClass(
            "Dog",
            1,
            Dog_ctor,
            null,
            &[_]napi.c.napi_property_descriptor{.{
                .utf8name = "name",
                .method = napi.wrapCallback(0, Dog_name),
            }},
        ),
    );
}

// --- Cat ---

const Cat = struct { name_buf: [64]u8, len: usize };

const cat_type_tag = napi.c.napi_type_tag{
    .lower = 0xCAFEBABE_00000001,
    .upper = 0xAAAAAAAA_AAAAAAAA,
};

fn Cat_finalize(_: napi.Env, cat: *Cat, _: ?*anyopaque) void {
    allocator.destroy(cat);
}

fn Cat_ctor(env: napi.Env, cb: napi.CallbackInfo(1)) !napi.Value {
    const arg = cb.arg(0);
    var buf: [64]u8 = undefined;
    const name = try arg.getValueStringUtf8(&buf);

    const cat = try allocator.create(Cat);
    cat.* = Cat{ .name_buf = buf, .len = name.len };

    _ = try env.wrap(cb.this(), Cat, cat, Cat_finalize, null);
    try env.typeTagObject(cb.this(), cat_type_tag);
    return cb.this();
}

fn Cat_name(env: napi.Env, cb: napi.CallbackInfo(0)) !napi.Value {
    const cat = try env.unwrapChecked(Cat, cb.this(), cat_type_tag);
    return try env.createStringUtf8(cat.name_buf[0..cat.len]);
}

// --- Dog ---

const Dog = struct { name_buf: [64]u8, len: usize };

const dog_type_tag = napi.c.napi_type_tag{
    .lower = 0xDEADBEEF_00000002,
    .upper = 0xBBBBBBBB_BBBBBBBB,
};

fn Dog_finalize(_: napi.Env, dog: *Dog, _: ?*anyopaque) void {
    allocator.destroy(dog);
}

fn Dog_ctor(env: napi.Env, cb: napi.CallbackInfo(1)) !napi.Value {
    const arg = cb.arg(0);
    var buf: [64]u8 = undefined;
    const name = try arg.getValueStringUtf8(&buf);

    const dog = try allocator.create(Dog);
    dog.* = Dog{ .name_buf = buf, .len = name.len };

    _ = try env.wrap(cb.this(), Dog, dog, Dog_finalize, null);
    try env.typeTagObject(cb.this(), dog_type_tag);
    return cb.this();
}

fn Dog_name(env: napi.Env, cb: napi.CallbackInfo(0)) !napi.Value {
    const dog = try env.unwrapChecked(Dog, cb.this(), dog_type_tag);
    return try env.createStringUtf8(dog.name_buf[0..dog.len]);
}
