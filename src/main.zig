const std = @import("std");
const bytecode = @import("bytecode.zig");
const debug = @import("debug.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var chunk = bytecode.Chunk.init(gpa.allocator());
    defer chunk.free();
    try chunk.write_chunk(bytecode.OpCode.OP_RETURN);

    var stdout = std.io.getStdOut().writer();
    try debug.disassembleChunk(&chunk, "test chunk", &stdout.any());
}

test "disassembling" {
    const alloc = std.testing.allocator;
    var chunk = bytecode.Chunk.init(alloc);
    defer chunk.free();

    try chunk.write_chunk(bytecode.OpCode.OP_RETURN);
    try chunk.write_chunk(bytecode.OpCode.OP_RETURN);

    var out = std.ArrayList(u8).init(alloc);
    defer out.deinit();
    try debug.disassembleChunk(&chunk, "test chunk", &out.writer().any());

    try std.testing.expect(std.mem.eql(u8, out.items,
        \\== test chunk ==
        \\0000 OP_RETURN
        \\0001 OP_RETURN
        \\
    ));
}
