const std = @import("std");
const bytecode = @import("bytecode.zig");
const Chunk = bytecode.Chunk;
const OpCode = bytecode.OpCode;
const values = @import("value.zig");

pub fn disassembleChunk(chunk: *Chunk, name: []const u8, writer: *const std.io.AnyWriter) !void {
    try writer.print("== {s} ==\n", .{name});

    var i: usize = 0;
    while (i < chunk.code.items.len) {
        i = try disassembleInstruction(chunk, i, writer);
    }
}

pub fn disassembleInstruction(chunk: *Chunk, offset: usize, writer: *const std.io.AnyWriter) !usize {
    try writer.print("{d:0>4} ", .{offset});
    if (offset > 0 and chunk.get_line(offset) == chunk.get_line(offset - 1)) {
        _ = try writer.write("   | ");
    } else {
        try writer.print("{d: >4} ", .{chunk.get_line(offset)});
    }

    const instruction: OpCode = @enumFromInt(chunk.code.items[offset]);
    return switch (instruction) {
        .OP_RETURN => simple_instruction(instruction, offset, writer),
        .OP_CONSTANT => constant_instruction(instruction, offset, writer, chunk),
        .OP_CONSTANT_LONG => constant_long_instruction(offset, writer, chunk),
        _ => unknown_opcode(instruction, offset, writer),
    };
}

fn constant_instruction(instruction: OpCode, offset: usize, writer: *const std.io.AnyWriter, chunk: *Chunk) !usize {
    const constant_id = chunk.code.items[offset + 1];
    const constant = chunk.constants.items[constant_id];
    try writer.print("{s: <16} {d: >4} '{d}'\n", .{ @tagName(instruction), constant_id, constant });

    return offset + 2;
}

fn constant_long_instruction(offset: usize, writer: *const std.io.AnyWriter, chunk: *Chunk) !usize {
    const constant_id: u24 = std.mem.bytesAsValue(u24, &chunk.code.items[offset + 1]).*;
    const constant = chunk.constants.items[constant_id];
    try writer.print("{s: <16} {d: >4} '{d}'\n", .{ @tagName(OpCode.OP_CONSTANT_LONG), constant_id, constant });

    return offset + 4;
}

fn simple_instruction(instruction: OpCode, offset: usize, writer: *const std.io.AnyWriter) !usize {
    try writer.print("{s}\n", .{@tagName(instruction)});
    return offset + 1;
}

fn unknown_opcode(instruction: OpCode, offset: usize, writer: *const std.io.AnyWriter) !usize {
    try writer.print("Unknown opcode {d}\n", .{@intFromEnum(instruction)});
    return offset + 1;
}
