const std = @import("std");
const Chunk = @import("Chunk.zig");
const OpCode = Chunk.OpCode;
const values = @import("value.zig");

pub fn disassembleChunk(chunk: *const Chunk, name: []const u8, writer: std.io.AnyWriter) !void {
    try writer.print("== {s} ==\n", .{name});

    var i: usize = 0;
    while (i < chunk.code.items.len) {
        i = try disassembleInstruction(chunk, i, writer);
    }
}

pub fn disassembleInstruction(chunk: *const Chunk, offset: usize, writer: std.io.AnyWriter) !usize {
    try writer.print("{d:0>4} ", .{offset});
    if (offset > 0 and chunk.getLine(offset) == chunk.getLine(offset - 1)) {
        _ = try writer.write("   | ");
    } else {
        try writer.print("{d: >4} ", .{chunk.getLine(offset)});
    }

    const instruction: OpCode = @enumFromInt(chunk.code.items[offset]);
    return switch (instruction) {
        .OP_RETURN, .OP_ADD, .OP_SUBTRACT, .OP_MULTIPLY, .OP_DIVIDE, .OP_NEGATE => simpleInstruction(instruction, offset, writer),
        .OP_CONSTANT => constantInstruction(instruction, offset, writer, chunk),
        .OP_CONSTANT_LONG => constantLongInstruction(offset, writer, chunk),
        _ => unknownOpcode(instruction, offset, writer),
    };
}

fn constantInstruction(instruction: OpCode, offset: usize, writer: std.io.AnyWriter, chunk: *const Chunk) !usize {
    const constant_id = chunk.code.items[offset + 1];
    const constant = chunk.constants.items[constant_id];
    try writer.print("{s: <16} {d: >4} '{d}'\n", .{ @tagName(instruction), constant_id, constant });

    return offset + 2;
}

fn constantLongInstruction(offset: usize, writer: std.io.AnyWriter, chunk: *const Chunk) !usize {
    const constant_id: u24 = std.mem.bytesAsValue(u24, &chunk.code.items[offset + 1]).*;
    const constant = chunk.constants.items[constant_id];
    try writer.print("{s: <16} {d: >4} '{d}'\n", .{ @tagName(OpCode.OP_CONSTANT_LONG), constant_id, constant });

    return offset + 4;
}

fn simpleInstruction(instruction: OpCode, offset: usize, writer: std.io.AnyWriter) !usize {
    try writer.print("{s}\n", .{@tagName(instruction)});
    return offset + 1;
}

fn unknownOpcode(instruction: OpCode, offset: usize, writer: std.io.AnyWriter) !usize {
    try writer.print("Unknown opcode {d}\n", .{@intFromEnum(instruction)});
    return offset + 1;
}

test "disassembling" {
    const alloc = std.testing.allocator;
    var chunk = Chunk.init(alloc);
    defer chunk.free();

    try chunk.writeInstruction(OpCode.OP_RETURN, 1);
    try chunk.writeInstruction(OpCode.OP_RETURN, 2);

    var out = std.ArrayList(u8).init(alloc);
    defer out.deinit();
    try disassembleChunk(&chunk, "test chunk", out.writer().any());

    try std.testing.expect(std.mem.eql(u8, out.items,
        \\== test chunk ==
        \\0000    1 OP_RETURN
        \\0001    2 OP_RETURN
        \\
    ));
}
