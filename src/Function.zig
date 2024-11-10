const Obj = @import("Obj.zig");
const std = @import("std");
const Chunk = @import("Chunk.zig");

const Function = @This();

obj: Obj = Obj{ .typ = .Function },
arity: usize,
chunk: Chunk,
name: *Obj.String,

pub fn getObj(self: *Function) *Obj {
    return &self.obj;
}

pub fn init(alloc: std.mem.Allocator) Function {
    return Function{
        .arity = undefined,
        .chunk = Chunk.init(alloc),
        .name = undefined,
        .obj = .{ .typ = .Function },
    };
}

pub fn deinit(self: *Function) void {
    self.chunk.free();
}

pub fn eql(a: *Function, b: *Function) bool {
    return a == b;
}

pub fn format(
    self: *Function,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;

    try writer.print("<fn {s}>", .{self.name.getString()});
}
