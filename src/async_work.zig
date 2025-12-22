const std = @import("std");
const c = @import("c.zig");
const status = @import("status.zig");
const NapiError = @import("status.zig").NapiError;
const Env = @import("Env.zig");
const Value = @import("Value.zig");
const Status = status.Status;

pub fn AsyncExecuteCallback(comptime Data: type) type {
    return *const fn (Env, *Data) void;
}

pub fn wrapAsyncExecuteCallback(
    comptime Data: type,
    comptime cb: AsyncExecuteCallback(Data),
) c.napi_async_execute_callback {
    const wrapper = struct {
        pub fn f(
            raw_env: c.napi_env,
            raw_data: ?*anyopaque,
        ) callconv(.C) void {
            if (raw_data == null) return;
            const env = Env{ .env = raw_env };
            const data: *Data = @ptrCast(@alignCast(raw_data));
            cb(env, data);
        }
    };
    return wrapper.f;
}

pub fn AsyncCompleteCallback(comptime Data: type) type {
    return *const fn (Env, Status, *Data) void;
}

pub fn wrapAsyncCompleteCallback(
    comptime Data: type,
    comptime cb: AsyncCompleteCallback(Data),
) c.napi_async_complete_callback {
    const wrapper = struct {
        pub fn f(
            raw_env: c.napi_env,
            raw_status: c.napi_status,
            raw_data: ?*anyopaque,
        ) callconv(.C) void {
            if (raw_data == null) return;
            const env = Env{ .env = raw_env };
            const stat: Status = @enumFromInt(raw_status);
            const data: *Data = @ptrCast(@alignCast(raw_data));
            cb(env, stat, data);
        }
    };
    return wrapper.f;
}

pub fn AsyncWork(comptime Data: type) type {
    return struct {
        env: c.napi_env,
        work: c.napi_async_work,

        const Self = @This();

        pub fn create(
            raw_env: Env,
            async_resource: ?Value,
            async_resource_name: ?Value,
            comptime execute_cb: AsyncExecuteCallback(Data),
            comptime complete_cb: AsyncCompleteCallback(Data),
            data: *Data,
        ) NapiError!Self {
            var work: c.napi_async_work = undefined;
            try status.check(
                c.napi_create_async_work(
                    raw_env.env,
                    if (async_resource) |r| r.value else null,
                    if (async_resource_name) |n| n.value else null,
                    wrapAsyncExecuteCallback(Data, execute_cb),
                    wrapAsyncCompleteCallback(Data, complete_cb),
                    data,
                    &work,
                ),
            );
            return Self{
                .env = raw_env.env,
                .work = work,
            };
        }

        pub fn queue(self: Self) NapiError!void {
            try status.check(
                c.napi_queue_async_work(self.env, self.work),
            );
        }

        pub fn cancel(self: Self) NapiError!void {
            try status.check(
                c.napi_cancel_async_work(self.env, self.work),
            );
        }

        pub fn delete(self: Self) NapiError!void {
            try status.check(
                c.napi_delete_async_work(self.env, self.work),
            );
        }
    };
}
