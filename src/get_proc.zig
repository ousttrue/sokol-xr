const std = @import("std");
const xr_gen = @import("openxr");
const xr = xr_gen.c;

extern fn xrGetInstanceProcAddr(
    instance: *anyopaque,
    procname: [*:0]const u8,
    function: *anyopaque,
) i64;

pub fn getProcs(
    instance: *anyopaque,
    table: anytype,
) void {
    inline for (std.meta.fields(@typeInfo(@TypeOf(table)).pointer.child)) |field| {
        const name: [*:0]const u8 = @ptrCast(field.name ++ "\x00");
        var cmd_ptr: xr.PFN_xrVoidFunction = undefined;
        const result = xrGetInstanceProcAddr(instance, name, @ptrCast(&cmd_ptr));
        if (result != 0) @panic("loader");
        @field(table, field.name) = @ptrCast(cmd_ptr);
    }
}
