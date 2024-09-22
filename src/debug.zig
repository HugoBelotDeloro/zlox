const std = @import("std");
const bytecode = @import("bytecode.zig");

pub fn disassembleChunk(chunk: *bytecode.Chunk, name: []const u8, writer: *const std.io.AnyWriter) !void {
    try writer.print("== {s} ==\n", .{name});

    var i: usize = 0;
    while (i < chunk.code.items.len) {
        i = try disassembleInstruction(chunk, i, writer);
    }
}

pub fn disassembleInstruction(chunk: *bytecode.Chunk, offset: usize, writer: *const std.io.AnyWriter) !usize {
    try writer.print("{d:0>4} ", .{offset});

    const instruction = chunk.code.items[offset];
    return switch (instruction) {
        bytecode.OpCode.OP_RETURN => simple_instruction(instruction, offset, writer),
        _ => unknown_opcode(instruction, offset, writer),
    };
}

fn simple_instruction(instruction: bytecode.OpCode, offset: usize, writer: *const std.io.AnyWriter) !usize {
    try writer.print("{s}\n", .{@tagName(instruction)});
    return offset + 1;
}

fn unknown_opcode(instruction: bytecode.OpCode, offset: usize, writer: *const std.io.AnyWriter) !usize {
    try writer.print("Unknown opcode {d}\n", .{@intFromEnum(instruction)});
    return offset + 1;
}
