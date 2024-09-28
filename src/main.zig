const std = @import("std");
const Chunk = @import("Chunk.zig");
const OpCode = Chunk.OpCode;
const debug = @import("debug.zig");
const VM = @import("Vm.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var chunk = Chunk.init(gpa.allocator());
    defer chunk.free();

    try chunk.writeConstant(1.2, 0);
    try chunk.writeConstant(3.4, 1);
    try chunk.writeInstruction(.OP_ADD, 2);
    try chunk.writeConstant(5.6, 3);
    try chunk.writeInstruction(.OP_DIVIDE, 4);
    try chunk.writeInstruction(.OP_RETURN, 5);

    var stdout = std.io.getStdOut().writer();

    try debug.disassembleChunk(&chunk, "test chunk", stdout.any());

    _ = try stdout.write("\n\n== interpret ==\n");
    _ = try VM.interpret(&chunk, gpa.allocator(), stdout.any());
}

test "disassembling" {
    const alloc = std.testing.allocator;
    var chunk = Chunk.init(alloc);
    defer chunk.free();

    try chunk.writeInstruction(OpCode.OP_RETURN, 1);
    try chunk.writeInstruction(OpCode.OP_RETURN, 2);

    var out = std.ArrayList(u8).init(alloc);
    defer out.deinit();
    try debug.disassembleChunk(&chunk, "test chunk", out.writer().any());

    try std.testing.expect(std.mem.eql(u8, out.items,
        \\== test chunk ==
        \\0000    1 OP_RETURN
        \\0001    2 OP_RETURN
        \\
    ));
}
