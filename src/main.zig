const std = @import("std");
const bytecode = @import("bytecode.zig");
const debug = @import("debug.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var chunk = bytecode.Chunk.init(gpa.allocator());
    defer chunk.free();

    const constant = try chunk.add_constant(1.2);
    const constant2 = try chunk.add_constant(42);

    try chunk.write_chunk(bytecode.OpCode.OP_CONSTANT, 1);
    try chunk.write_chunk(@enumFromInt(constant), 1);

    try chunk.write_chunk(bytecode.OpCode.OP_CONSTANT, 1);
    try chunk.write_chunk(@enumFromInt(constant2), 1);

    try chunk.write_chunk(bytecode.OpCode.OP_RETURN, 2);

    var stdout = std.io.getStdOut().writer();
    try debug.disassembleChunk(&chunk, "test chunk", &stdout.any());
}

test "disassembling" {
    const alloc = std.testing.allocator;
    var chunk = bytecode.Chunk.init(alloc);
    defer chunk.free();

    try chunk.write_chunk(bytecode.OpCode.OP_RETURN, 1);
    try chunk.write_chunk(bytecode.OpCode.OP_RETURN, 2);

    var out = std.ArrayList(u8).init(alloc);
    defer out.deinit();
    try debug.disassembleChunk(&chunk, "test chunk", &out.writer().any());

    try std.testing.expect(std.mem.eql(u8, out.items,
        \\== test chunk ==
        \\0000    1 OP_RETURN
        \\0001    2 OP_RETURN
        \\
    ));
}
