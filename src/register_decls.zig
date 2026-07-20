const Env = @import("Env.zig");
const Value = @import("Value.zig");
const createCallback = @import("create_callback.zig").createCallback;
const register = @import("module.zig").register;

pub fn registerDecls(comptime decls: anytype, comptime options: anytype) void {
    _ = options;

    const mod = (struct {
        pub fn mod(env: Env, module: Value) anyerror!void {
            inline for (@typeInfo(@TypeOf(decls)).@"struct".fields) |field| {
                const decl = @field(decls, field.name);
                const value = switch (@typeInfo(@TypeOf(decl.value))) {
                    .@"fn" => try env.createFunction(
                        field.name,
                        @typeInfo(@TypeOf(decl.value)).@"fn".params.len,
                        createCallback(
                            @typeInfo(@TypeOf(decl.value)).@"fn".params.len,
                            decl.value,
                            .{},
                        ),
                        null,
                    ),
                    .pointer => |p| if (p.size == .slice)
                        if (p.child == u8)
                            try env.createStringUtf8(decl.value)
                        else
                            @compileError("unsupported slice type")
                    else
                        @compileError("unsupported pointer type"),
                    else => @compileError("unsupported value type"),
                };

                try module.setNamedProperty(field.name, value);
            }
        }
    }).mod;

    register(mod);
}
