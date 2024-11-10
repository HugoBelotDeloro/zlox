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
        .Print, .Return, .Equal, .Greater, .Less, .Add, .Subtract, .Multiply, .Divide, .Not, .Negate, .True, .False, .Dup, .Pop, .Nil => simpleInstruction(instruction, offset, writer),
        .Constant, .GetGlobal, .DefineGlobal, .SetGlobal => constantInstruction(instruction, offset, writer, chunk),
        .ConstantLong, .GetGlobalLong, .DefineGlobalLong, .SetGlobalLong => constantLongInstruction(instruction, offset, writer, chunk),
        .PopN, .GetLocal, .SetLocal => byteInstruction(instruction, offset, writer, chunk.code.items[offset + 1]),
        .Jump, .JumpIfFalse => jumpInstruction(instruction, 1, chunk, offset, writer),
        .Loop => jumpInstruction(instruction, -1, chunk, offset, writer),
        _ => unknownOpcode(instruction, offset, writer),
    };
}

fn constantInstruction(instruction: OpCode, offset: usize, writer: std.io.AnyWriter, chunk: *const Chunk) !usize {
    const constant_id = chunk.code.items[offset + 1];
    const constant = chunk.constants.items[constant_id];
    try writer.print("{s: <16} {d: >4} '{}'\n", .{ @tagName(instruction), constant_id, constant });

    return offset + 2;
}

fn constantLongInstruction(instruction: OpCode, offset: usize, writer: std.io.AnyWriter, chunk: *const Chunk) !usize {
    const constant_id: u24 = std.mem.bytesAsValue(u24, &chunk.code.items[offset + 1]).*;
    const constant = chunk.constants.items[constant_id];
    try writer.print("{s: <16} {d: >4} '{d}'\n", .{ @tagName(instruction), constant_id, constant });

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

fn byteInstruction(instruction: OpCode, offset: usize, writer: std.io.AnyWriter, byte: u8) !usize {
    try writer.print("{s: <16} {d: >4}\n", .{ @tagName(instruction), byte });
    return offset + 2;
}

fn jumpInstruction(instr: OpCode, sign: i32, chunk: *const Chunk, offset: usize, writer: std.io.AnyWriter) !usize {
    const jump: u16 = (@as(u16, chunk.code.items[offset + 1]) << 8) | (chunk.code.items[offset + 2]);
    try writer.print("{s: <16} {d: >4} -> {d}\n", .{ @tagName(instr), offset, @as(i32, @intCast(offset)) + 3 + sign * jump });
    return offset + 3;
}

test "disassembling" {
    const alloc = std.testing.allocator;
    var chunk = Chunk.init(alloc);
    defer chunk.free();

    try chunk.writeInstruction(OpCode.Return, 1);
    try chunk.writeInstruction(OpCode.Return, 2);

    var out = std.ArrayList(u8).init(alloc);
    defer out.deinit();
    try disassembleChunk(&chunk, "test chunk", out.writer().any());

    try std.testing.expect(std.mem.eql(u8, out.items,
        \\== test chunk ==
        \\0000    1 Return
        \\0001    2 Return
        \\
    ));
}
