const std = @import("std");

pub const AccessorRef = union(enum) {
    none,
    derived,
    named: []const u8,
};

pub const FieldSpec = struct {
    pub const zapi_js_property_kind = "field";
    field_name: []const u8,
};

pub const PropSpec = struct {
    pub const zapi_js_property_kind = "prop";
    get: AccessorRef,
    set: AccessorRef,
};

fn ClassMeta(comptime Options: type) type {
    return struct {
        pub const zapi_js_meta_kind = "class";
        options: Options,
    };
}

pub fn class(comptime opts: anytype) ClassMeta(@TypeOf(opts)) {
    validateClassOptions(@TypeOf(opts), opts);
    return .{ .options = opts };
}

pub fn field(comptime name: []const u8) FieldSpec {
    return .{ .field_name = name };
}

pub fn prop(comptime spec: anytype) PropSpec {
    const Spec = @TypeOf(spec);
    if (@typeInfo(Spec) != .@"struct") {
        @compileError("js.prop expects a struct literal");
    }

    if (!@hasField(Spec, "get")) {
        @compileError("js.prop requires .get");
    }

    return .{
        .get = parseAccessor("get", @field(spec, "get")),
        .set = if (@hasField(Spec, "set")) parseAccessor("set", @field(spec, "set")) else .none,
    };
}

pub fn hasClassMeta(comptime T: type) bool {
    if (@typeInfo(T) != .@"struct") return false;
    return @hasDecl(T, "js_meta") and isClassMetaValue(@field(T, "js_meta"));
}

pub fn isClassType(comptime T: type) bool {
    return hasClassMeta(T) or isLegacyClassType(T);
}

pub fn isLegacyClassType(comptime T: type) bool {
    if (@typeInfo(T) != .@"struct") return false;
    return @hasDecl(T, "js_class") and
        @TypeOf(@field(T, "js_class")) == bool and
        @field(T, "js_class") == true;
}

pub fn isClassMetaValue(comptime value: anytype) bool {
    return @hasDecl(@TypeOf(value), "zapi_js_meta_kind") and
        std.mem.eql(u8, @field(@TypeOf(value), "zapi_js_meta_kind"), "class");
}

pub fn hasProperties(comptime T: type) bool {
    if (!hasClassMeta(T)) return false;
    return @hasField(@TypeOf(T.js_meta.options), "properties");
}

pub fn propertyFields(comptime T: type) []const std.builtin.Type.StructField {
    if (!hasProperties(T)) return &.{};
    return @typeInfo(@TypeOf(T.js_meta.options.properties)).@"struct".fields;
}

pub fn getClassName(comptime T: type, comptime default_name: []const u8) []const u8 {
    if (!hasClassMeta(T)) return default_name;
    if (!@hasField(@TypeOf(T.js_meta.options), "name")) return default_name;
    const name = T.js_meta.options.name;
    switch (@typeInfo(@TypeOf(name))) {
        .optional => return if (name) |n| coerceStringLike(n) else default_name,
        else => return coerceStringLike(name),
    }
}

pub fn propertyKind(comptime value: anytype) enum { computed, field, prop, invalid } {
    if (@TypeOf(value) == bool) {
        return if (value) .computed else .invalid;
    }
    if (isFieldSpec(value)) return .field;
    if (isPropSpec(value)) return .prop;
    return .invalid;
}

pub fn isFieldSpec(comptime value: anytype) bool {
    return @hasDecl(@TypeOf(value), "zapi_js_property_kind") and
        std.mem.eql(u8, @field(@TypeOf(value), "zapi_js_property_kind"), "field");
}

pub fn isPropSpec(comptime value: anytype) bool {
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
            .computed, .field, .prop => {},
            .invalid => @compileError("unsupported property spec for '" ++ field_info.name ++ "'"),
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

test "js.field accepts field names" {
    const spec = field("label_");
    try std.testing.expectEqualStrings("label_", spec.field_name);
}

test "js.prop accepts derived getter and setter" {
    const spec = prop(.{ .get = true, .set = true });
    try std.testing.expect(spec.get == .derived);
    try std.testing.expect(spec.set == .derived);
}
