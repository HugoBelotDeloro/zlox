const std = @import("std");
const bytecode = @import("bytecode.zig");
const values = @import("value.zig");

pub fn disassembleChunk(chunk: *bytecode.Chunk, name: []const u8, writer: *const std.io.AnyWriter) !void {
    try writer.print("== {s} ==\n", .{name});

    var i: usize = 0;
    while (i < chunk.code.items.len) {
        i = try disassembleInstruction(chunk, i, writer);
    }
}

pub fn disassembleInstruction(chunk: *bytecode.Chunk, offset: usize, writer: *const std.io.AnyWriter) !usize {
    try writer.print("{d:0>4} ", .{offset});
    if (offset > 0 and chunk.get_line(offset) == chunk.get_line(offset - 1)) {
      _ = try writer.write("   | ");
    } else {
      try writer.print("{d: >4} ", .{chunk.get_line(offset)});
    }

    const instruction = chunk.code.items[offset];
    return switch (instruction) {
        bytecode.OpCode.OP_RETURN => simple_instruction(instruction, offset, writer),
        bytecode.OpCode.OP_CONSTANT => constant_instruction(instruction, offset, writer, chunk),
        _ => unknown_opcode(instruction, offset, writer),
    };
}

fn constant_instruction(instruction: bytecode.OpCode, offset: usize, writer: *const std.io.AnyWriter, chunk: *bytecode.Chunk) !usize {
  const constant_id = @intFromEnum(chunk.code.items[offset + 1]) ;
  const constant = chunk.constants.items[constant_id];
  try writer.print("{s: <16} {d: >4} '{d}'\n", .{@tagName(instruction) , constant_id, constant});

  return offset + 2;
}

fn simple_instruction(instruction: bytecode.OpCode, offset: usize, writer: *const std.io.AnyWriter) !usize {
    try writer.print("{s}\n", .{@tagName(instruction)});
    return offset + 1;
}

fn unknown_opcode(instruction: bytecode.OpCode, offset: usize, writer: *const std.io.AnyWriter) !usize {
    try writer.print("Unknown opcode {d}\n", .{@intFromEnum(instruction)});
    return offset + 1;
}
