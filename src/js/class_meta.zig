const std = @import("std");

/// Represents a reference to a getter or setter accessor function.
///
/// This union is used within `PropSpec` to define how a property's getter or
/// setter is resolved:
/// - `.none`: The accessor does not exist (e.g., a read-only property has no setter).
/// - `.derived`: The accessor function's name is implicitly derived (e.g., `setMyProp` for `myProp`).
/// - `.named`: The accessor function has an explicitly provided name.
pub const AccessorRef = union(enum) {
    none,
    derived,
    named: []const u8,
};

/// Defines the specification for a single JavaScript property exposed by a DSL class.
///
/// This struct is the return type of `js.prop` and is used to configure how a
/// property's getter and setter methods are linked to Zig functions.
///
/// - `get`: An `AccessorRef` indicating how the getter function is specified.
/// - `set`: An `AccessorRef` indicating how the setter function is specified.
pub const PropSpec = struct {
    pub const zapi_js_property_kind = "prop";
    get: AccessorRef,
    set: AccessorRef,
};

/// Constructor for `ClassMeta`.
fn ClassMeta(comptime Options: type) type {
    return struct {
        pub const zapi_js_meta_kind = "class";
        options: Options,
    };
}

/// Declares JavaScript class metadata for a Zig struct.
///
/// This comptime function is central to exposing Zig structs as JavaScript
/// classes. It takes a struct literal `opts` that configures various aspects
/// of the JS class, such as its name and properties.
///
/// The returned `ClassMeta` struct must be assigned to `pub const js_meta` within
/// the Zig struct that is intended to be a JavaScript class.
///
/// `opts` can contain:
/// - `.name: ?[]const u8`: Optional JS class name. If omitted, the Zig struct's
///   name is used. Can be an `?[]const u8` or `[]const u8`.
/// - `.properties: struct`: A struct literal where each field corresponds to a
///   JS property. The value for each field must be a `js.prop(...)` call.
///
/// Compile-time errors will be raised if `opts` contains unsupported fields or
/// if `properties` are not correctly defined using `js.prop`.
pub fn class(comptime opts: anytype) ClassMeta(@TypeOf(opts)) {
    validateClassOptions(@TypeOf(opts), opts);
    return .{ .options = opts };
}

/// Declares metadata for a JavaScript property exposed from a ZAPI DSL class.
///
/// This comptime function is used inside `js.class(.{ .properties = .{ ... } })`
/// to define individual properties (getters/setters) for a JavaScript class.
///
/// The `spec` argument must be a struct literal with:
/// - `.get: AccessorRef | bool | []const u8`: Configures the getter. Can be:
///   - `true` (derived name, e.g., `myProp` -> `myProp` getter function).
///   - `false` (no getter).
///   - `[]const u8` (explicit getter function name).
/// - `.set: AccessorRef | bool | []const u8`: Configures the setter. Can be:
///   - `true` (derived name, e.g., `myProp` -> `setMyProp` setter function).
///   - `false` (read-only property, no setter).
///   - `[]const u8` (explicit setter function name).
///
/// Compile-time errors are raised if `get` or `set` are missing or invalid.
pub fn prop(comptime spec: anytype) PropSpec {
    const Spec = @TypeOf(spec);
    if (@typeInfo(Spec) != .@"struct") {
        @compileError("js.prop expects a struct literal");
    }

    if (!@hasField(Spec, "get")) {
        @compileError("js.prop requires .get");
    }

    if (!@hasField(Spec, "set")) {
        @compileError("js.prop requires .set (use false for read-only properties)");
    }

    return .{
        .get = parseAccessor("get", @field(spec, "get")),
        .set = parseAccessor("set", @field(spec, "set")),
    };
}

/// Checks if a given Zig type `T` has valid class metadata (`pub const js_meta = js.class(...)`).
///
/// This comptime function returns `true` if `T` is a struct and contains a
/// `pub const js_meta` field that is a `ClassMeta` instance (created by `js.class`).
/// It's used to identify types designed to be JavaScript classes.
pub fn hasClassMeta(comptime T: type) bool {
    if (@typeInfo(T) != .@"struct") return false;
    return @hasDecl(T, "js_meta") and isClassMetaValue(@field(T, "js_meta"));
}

/// Alias for `hasClassMeta`.
///
/// This comptime function is a convenience alias to check if a Zig type `T`
/// is considered a ZAPI DSL class type.
pub fn isClassType(comptime T: type) bool {
    return hasClassMeta(T);
}

/// Checks if a compile-time value is a `ClassMeta` instance.
///
/// This function is used internally to verify the structure and kind of the
/// `js_meta` field within a Zig struct.
pub fn isClassMetaValue(comptime value: anytype) bool {
    return @hasDecl(@TypeOf(value), "zapi_js_meta_kind") and
        std.mem.eql(u8, @field(@TypeOf(value), "zapi_js_meta_kind"), "class");
}

/// Checks if a ZAPI DSL class type `T` has properties defined in its `js_meta`.
///
/// This comptime function returns `true` if `T` has class metadata and that
/// metadata includes a `.properties` field.
pub fn hasProperties(comptime T: type) bool {
    if (!hasClassMeta(T)) return false;
    return @hasField(@TypeOf(T.js_meta.options), "properties");
}

/// Returns a slice of `std.builtin.Type.StructField` for the properties defined
/// in a ZAPI DSL class `T`'s `js_meta`.
///
/// This comptime function is used to iterate over the declared properties of a
/// class. Returns an empty slice if the class has no properties.
pub fn propertyFields(comptime T: type) []const std.builtin.Type.StructField {
    if (!hasProperties(T)) return &.{};
    return @typeInfo(@TypeOf(T.js_meta.options.properties)).@"struct".fields;
}

/// Determines the JavaScript class name for a given Zig class type `T`.
///
/// This comptime function tries to retrieve the class name from `T.js_meta.options.name`.
/// If `.name` is not present, `default_name` is used. Handles `?[]const u8` for the name.
pub fn getClassName(comptime T: type, comptime default_name: []const u8) []const u8 {
    if (!hasClassMeta(T)) return default_name;
    if (!@hasField(@TypeOf(T.js_meta.options), "name")) return default_name;
    const name = T.js_meta.options.name;
    switch (@typeInfo(@TypeOf(name))) {
        .optional => return if (name) |n| coerceStringLike(n) else default_name,
        else => return coerceStringLike(name),
    }
}

/// Determines the kind of property specification for a given compile-time value.
///
/// This internal comptime function classifies whether a value is a valid
/// `js.prop` specification (`.prop`) or an invalid one (`.invalid`).
pub fn propertyKind(comptime value: anytype) enum { prop, invalid } {
    if (isPropSpec(value)) return .prop;
    return .invalid;
}

/// Checks if a compile-time value is a `PropSpec` instance.
///
/// This internal comptime function is used to verify that a property is defined
/// using `js.prop(...)`.
pub fn isPropSpec(comptime value: anytype) bool {
    switch (@typeInfo(@TypeOf(value))) {
        .@"struct" => {},
        .@"enum" => {},
        .@"union" => {},
        .@"opaque" => {},
        else => return false,
    }
    return @hasDecl(@TypeOf(value), "zapi_js_property_kind") and
        std.mem.eql(u8, @field(@TypeOf(value), "zapi_js_property_kind"), "prop");
}

fn validateClassOptions(comptime Opts: type, comptime opts: Opts) void {
    if (@typeInfo(Opts) != .@"struct") {
        @compileError("js.class expects a struct literal");
    }

    inline for (@typeInfo(Opts).@"struct".fields) |field_info| {
        if (!std.mem.eql(u8, field_info.name, "name") and !std.mem.eql(u8, field_info.name, "properties")) {
            @compileError("js.class only supports .name and .properties");
        }
    }

    if (@hasField(Opts, "name")) {
        const NameType = @TypeOf(opts.name);
        switch (@typeInfo(NameType)) {
            .optional => |opt| {
                _ = comptime coerceStringLikeType(opt.child, "js.class .name");
            },
            else => _ = comptime coerceStringLikeType(NameType, "js.class .name"),
        }
    }

    if (@hasField(Opts, "properties")) {
        validateProperties(@TypeOf(opts.properties), opts.properties);
    }
}

fn validateProperties(comptime Props: type, comptime props: Props) void {
    if (@typeInfo(Props) != .@"struct") {
        @compileError("js.class .properties must be a struct literal");
    }

    inline for (@typeInfo(Props).@"struct".fields) |field_info| {
        const value = @field(props, field_info.name);
        switch (propertyKind(value)) {
            .prop => {},
            .invalid => @compileError("unsupported property spec for '" ++ field_info.name ++ "' (use js.prop)"),
        }
    }
}

fn parseAccessor(comptime _: []const u8, comptime value: anytype) AccessorRef {
    return switch (@TypeOf(value)) {
        bool => if (value) .derived else .none,
        else => .{ .named = coerceStringLike(value) },
    };
}

fn coerceStringLike(comptime value: anytype) []const u8 {
    const T = @TypeOf(value);
    _ = comptime coerceStringLikeType(T, "string");
    switch (@typeInfo(T)) {
        .pointer => |ptr| {
            if (ptr.size == .slice and ptr.child == u8 and ptr.is_const) return value;
            if (ptr.size == .one and @typeInfo(ptr.child) == .array) {
                const arr = @typeInfo(ptr.child).array;
                if (arr.child == u8) return value[0..arr.len];
            }
        },
        else => {},
    }
    unreachable;
}

fn coerceStringLikeType(comptime T: type, comptime label: []const u8) type {
    switch (@typeInfo(T)) {
        .pointer => |ptr| {
            if (ptr.size == .slice and ptr.child == u8 and ptr.is_const) return T;
            if (ptr.size == .one and @typeInfo(ptr.child) == .array) {
                const arr = @typeInfo(ptr.child).array;
                if (arr.child == u8) return T;
            }
        },
        else => {},
    }
    @compileError(label ++ " must be a string literal or []const u8");
}

test "js.class accepts empty options" {
    const meta = class(.{});
    try std.testing.expect(isClassMetaValue(meta));
}

test "js.prop accepts derived getter and setter" {
    const spec = prop(.{ .get = true, .set = true });
    try std.testing.expect(spec.get == .derived);
    try std.testing.expect(spec.set == .derived);
}

test "js.prop accepts named getter without setter" {
    const spec = prop(.{ .get = "kindValue", .set = false });
    try std.testing.expect(spec.get == .named);
    try std.testing.expectEqualStrings("kindValue", spec.get.named);
    try std.testing.expect(spec.set == .none);
}

test "js.prop accepts explicit read-only derived getter" {
    const spec = prop(.{ .get = true, .set = false });
    try std.testing.expect(spec.get == .derived);
    try std.testing.expect(spec.set == .none);
}

test "bare bool property specs are invalid" {
    try std.testing.expect(propertyKind(true) == .invalid);
}
