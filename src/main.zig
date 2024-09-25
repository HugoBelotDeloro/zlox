const std = @import("std");
const bytecode = @import("bytecode.zig");
const debug = @import("debug.zig");
const VM = @import("vm.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var chunk = bytecode.Chunk.init(gpa.allocator());
    defer chunk.free();

    var i: u32 = 0;
    while (i < 259) : (i += 1) {
        try chunk.write_constant(@floatFromInt(i), 0);
    }
    try chunk.write_instruction(.OP_RETURN, 1);

    var stdout = std.io.getStdOut().writer();
    try debug.disassembleChunk(&chunk, "test chunk", &stdout.any());

    _ = try VM.interpret(&chunk, stdout.any());
}

test "disassembling" {
    const alloc = std.testing.allocator;
    var chunk = bytecode.Chunk.init(alloc);
    defer chunk.free();

    try chunk.write_instruction(bytecode.OpCode.OP_RETURN, 1);
    try chunk.write_instruction(bytecode.OpCode.OP_RETURN, 2);

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
