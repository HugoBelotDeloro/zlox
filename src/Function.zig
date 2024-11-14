const Obj = @import("Obj.zig");
const std = @import("std");
const Chunk = @import("Chunk.zig");

const Function = @This();

alloc: std.mem.Allocator,
obj: Obj = Obj{ .typ = .Function },
arity: usize,
chunk: Chunk,
name: ?*Obj.String,

pub fn getObj(self: *Function) *Obj {
    return &self.obj;
}

pub fn init(alloc: std.mem.Allocator) Function {
    return Function{
        .alloc = alloc,
        .arity = undefined,
        .chunk = Chunk.init(alloc),
        .name = null,
        .obj = .{ .typ = .Function },
    };
}

pub fn deinit(self: *Function) void {
    self.chunk.deinit();
    self.alloc.destroy(self);
}

pub fn deinitReturnChunk(self: *Function) Chunk {
    const chunk = self.chunk;
    self.alloc.destroy(self);
    return chunk;
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

    if (self.name) |name|
        return writer.print("<fn {s}>", .{name.getString()});
    _ = try writer.write("<script>");
}
