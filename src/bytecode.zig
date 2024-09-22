const std = @import("std");

pub const OpCode = enum(u8) {
    OP_RETURN,
    _,
};

pub const Chunk = struct {
    code: std.ArrayList(OpCode),

    pub fn init(alloc: std.mem.Allocator) Chunk {
        return Chunk{ .code = std.ArrayList(OpCode).init(alloc) };
    }

    pub fn free(self: *Chunk) void {
        self.code.deinit();
    }

    pub fn write_chunk(self: *Chunk, byte: OpCode) !void {
        try self.code.append(byte);
    }
};
