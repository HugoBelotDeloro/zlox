const std = @import("std");
const values = @import("value.zig");

const Chunk = @This();

code: std.ArrayList(u8),
constants: values.ValueArray,
lines: std.ArrayList(LineInfo),

pub const OpCode = enum(u8) {
    OP_CONSTANT,
    OP_CONSTANT_LONG,
    OP_ADD,
    OP_SUBTRACT,
    OP_MULTIPLY,
    OP_DIVIDE,
    OP_NEGATE,
    OP_RETURN,
    _,
};

const LineInfo = struct {
    /// Number of the new line
    line_number: u32,
    /// Number of instructions at this line
    instruction_count: u32,
};

pub fn init(alloc: std.mem.Allocator) Chunk {
    return Chunk{
        .code = std.ArrayList(u8).init(alloc),
        .constants = std.ArrayList(values.Value).init(alloc),
        .lines = std.ArrayList(LineInfo).init(alloc),
    };
}

pub fn free(self: *Chunk) void {
    self.code.deinit();
    self.constants.deinit();
    self.lines.deinit();
}

pub fn write_instruction(self: *Chunk, instr: OpCode, line: u32) !void {
    return self.write_chunk(@intFromEnum(instr), line);
}

pub fn write_chunk(self: *Chunk, byte: u8, line: u32) !void {
    try self.code.append(byte);
    try self.update_lines(line, 1);
}

/// Writes a constant to the static data and returns its index
pub fn add_constant(self: *Chunk, value: values.Value) !usize {
    try self.constants.append(value);
    return self.constants.items.len - 1;
}

/// Inserts a constant in the static data and a constant opcode into the bytecode
pub fn write_constant(self: *Chunk, value: values.Value, line: u32) !void {
    const constant_id = try self.add_constant(value);

    if (constant_id > 255) {
        try self.write_instruction(OpCode.OP_CONSTANT_LONG, line);

        const bytes = try self.code.addManyAt(self.code.items.len, 3);
        const constant_id_ptr = std.mem.bytesAsValue(u24, bytes);
        constant_id_ptr.* = @intCast(constant_id);
        try self.update_lines(line, 3);
    } else {
        const byte: u8 = @intCast(constant_id);
        try self.write_instruction(OpCode.OP_CONSTANT, line);
        try self.write_chunk(byte, line);
    }
}

pub fn get_line(self: *Chunk, index: usize) u32 {
    var i: usize = 0; // Instruction index

    for (self.lines.items) |line_info| {
        if (i <= index and i + line_info.instruction_count > index) {
            return line_info.line_number;
        }
        i += line_info.instruction_count;
    }

    std.io.getStdErr().writer().print("index out of bounds {d}", .{index}) catch {};
    std.process.exit(1);
}

fn update_lines(self: *Chunk, line: u32, bytes_added_count: u32) !void {
    if (self.lines.items.len == 0 or self.lines.items[self.lines.items.len - 1].line_number != line) {
        try self.lines.append(.{ .instruction_count = bytes_added_count, .line_number = line });
    } else {
        self.lines.items[self.lines.items.len - 1].instruction_count += bytes_added_count;
    }
}

test "constants" {
    var chunk = Chunk.init(std.testing.allocator);
    defer chunk.free();
    const one = try chunk.add_constant(1);
    const two = try chunk.add_constant(2);
    const three = try chunk.add_constant(3);

    try std.testing.expect(chunk.constants.items[one] == 1);
    try std.testing.expect(chunk.constants.items[two] == 2);
    try std.testing.expect(chunk.constants.items[three] == 3);
}

test "long constants" {
    var chunk = Chunk.init(std.testing.allocator);
    defer chunk.free();

    var i: u32 = 0;
    while (i < 257) : (i += 1) {
        try chunk.write_constant(@floatFromInt(i), 0);
    }

    try std.testing.expect(chunk.code.items[chunk.code.items.len - 4] == @intFromEnum(OpCode.OP_CONSTANT_LONG));
    try std.testing.expect(chunk.code.items[chunk.code.items.len - 6] == @intFromEnum(OpCode.OP_CONSTANT));
}
