const std = @import("std");
const Value = @import("value.zig").Value;
const Table = @import("table.zig").Table;

const Chunk = @This();

code: std.ArrayList(u8),
constants: std.ArrayList(Value),
lines: std.ArrayList(LineInfo),
strings_indices: Table(usize),

pub const OpCode = enum(u8) {
    Constant,
    ConstantLong,
    Nil,
    True,
    False,
    Pop,
    GetGlobal,
    GetGlobalLong,
    DefineGlobal,
    DefineGlobalLong,
    SetGlobal,
    SetGlobalLong,
    Equal,
    Greater,
    Less,
    Add,
    Subtract,
    Multiply,
    Divide,
    Not,
    Negate,
    Print,
    Return,
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
        .constants = std.ArrayList(Value).init(alloc),
        .lines = std.ArrayList(LineInfo).init(alloc),
        .strings_indices = Table(usize).init(alloc),
    };
}

/// bytecode must have been allocated by allocator
pub fn from_bytecode(bytecode: []u8, allocator: std.mem.Allocator) Chunk {
    return Chunk{
        .code = std.ArrayList(u8).fromOwnedSlice(allocator, bytecode),
        .constants = std.ArrayList(Value).init(allocator),
        .lines = std.ArrayList(LineInfo).init(allocator),
        .strings_indices = Table(usize).init(allocator),
    };
}

pub fn free(self: *Chunk) void {
    self.code.deinit();
    self.constants.deinit();
    self.lines.deinit();
    self.strings_indices.deinit();
}

pub fn writeInstruction(self: *Chunk, instr: OpCode, line: u32) !void {
    return self.writeChunk(@intFromEnum(instr), line);
}

pub fn writeChunk(self: *Chunk, byte: u8, line: u32) !void {
    try self.code.append(byte);
    try self.updateLines(line, 1);
}

/// Writes a constant to the static data and returns its index
pub fn addConstant(self: *Chunk, value: Value) !usize {
    if (value.asObj()) |obj| if (obj.asString()) |str| {
        if (self.strings_indices.get(str)) |i| {
            return i;
        }
        _ = try self.strings_indices.set(str, self.constants.items.len);
    };
    try self.constants.append(value);
    return self.constants.items.len - 1;
}

/// Inserts a constant in the static data and a constant opcode into the bytecode
pub fn writeConstant(self: *Chunk, value: Value, line: u32) !void {
    const constant_id = try self.addConstant(value);

    if (constant_id > 255) {
        try self.writeInstruction(OpCode.ConstantLong, line);

        const bytes = try self.code.addManyAt(self.code.items.len, 3);
        const constant_id_ptr = std.mem.bytesAsValue(u24, bytes);
        constant_id_ptr.* = @intCast(constant_id);
        try self.updateLines(line, 3);
    } else {
        try self.writeInstruction(OpCode.Constant, line);

        const byte: u8 = @intCast(constant_id);
        try self.writeChunk(byte, line);
    }
}

pub fn writeGlobal(self: *Chunk, global_id: usize, line: u32) !void {
    if (global_id > 255) {
        try self.writeInstruction(OpCode.DefineGlobalLong, line);

        const bytes = try self.code.addManyAt(self.code.items.len, 3);
        const constant_id_ptr = std.mem.bytesAsValue(u24, bytes);
        constant_id_ptr.* = @intCast(global_id);
        try self.updateLines(line, 3);
    } else {
        try self.writeInstruction(OpCode.DefineGlobal, line);

        const byte: u8 = @intCast(global_id);
        try self.writeChunk(byte, line);
    }
}

pub fn writeConstantId(self: *Chunk, global_id: usize, line: u32) !void {
    if (global_id > 255) {
        const bytes = try self.code.addManyAt(self.code.items.len, 3);
        const constant_id_ptr = std.mem.bytesAsValue(u24, bytes);
        constant_id_ptr.* = @intCast(global_id);
        try self.updateLines(line, 3);
    } else {
        const byte: u8 = @intCast(global_id);
        try self.writeChunk(byte, line);
    }
}

pub fn getLine(self: *const Chunk, index: usize) u32 {
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

fn updateLines(self: *Chunk, line: u32, bytes_added_count: u32) !void {
    if (self.lines.items.len == 0 or self.lines.items[self.lines.items.len - 1].line_number != line) {
        try self.lines.append(.{ .instruction_count = bytes_added_count, .line_number = line });
    } else {
        self.lines.items[self.lines.items.len - 1].instruction_count += bytes_added_count;
    }
}

test "constants" {
    var chunk = Chunk.init(std.testing.allocator);
    defer chunk.free();
    const one = try chunk.addConstant(1);
    const two = try chunk.addConstant(2);
    const three = try chunk.addConstant(3);

    try std.testing.expect(chunk.constants.items[one] == 1);
    try std.testing.expect(chunk.constants.items[two] == 2);
    try std.testing.expect(chunk.constants.items[three] == 3);
}

test "long constants" {
    var chunk = Chunk.init(std.testing.allocator);
    defer chunk.free();

    var i: u32 = 0;
    while (i < 257) : (i += 1) {
        try chunk.writeConstant(@floatFromInt(i), 0);
    }

    try std.testing.expect(chunk.code.items[chunk.code.items.len - 4] == @intFromEnum(OpCode.ConstantLong));
    try std.testing.expect(chunk.code.items[chunk.code.items.len - 6] == @intFromEnum(OpCode.Constant));
}
