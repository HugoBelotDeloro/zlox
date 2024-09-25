const std = @import("std");
const bytecode = @import("bytecode.zig");
const Chunk = bytecode.Chunk;
const OpCode = bytecode.OpCode;
const Value = @import("value.zig").Value;

const VM = @This();

chunk: *Chunk,
ip: [*]u8,

pub fn interpret(chunk: *Chunk, writer: std.io.AnyWriter) !InterpretResult {
    var vm = VM{ .chunk = chunk, .ip = chunk.code.items.ptr };

    while (true) {
        switch (vm.read_instruction()) {
            .OP_RETURN => return .OK,
            .OP_CONSTANT => {
                const constant = vm.read_constant();
                try writer.print("{d}\n", .{constant});
            },
            .OP_CONSTANT_LONG => {
                const constant = vm.read_constant_long();
                try writer.print("{d}\n", .{constant});
            },
            else => {},
        }
    }
    return .OK;
}

pub const InterpretResult = enum {
    OK,
    COMPILE_ERROR,
    RUNTIME_ERROR,
};

fn read_instruction(self: *VM) OpCode {
    const instr = self.ip[0];
    self.ip += 1;
    return @enumFromInt(instr);
}

fn read_constant(self: *VM) Value {
    const id = self.ip[0];
    self.ip += 1;
    return self.chunk.constants.items[id];
}

fn read_constant_long(self: *VM) Value {
    const constant_id = std.mem.bytesAsValue(u24, self.ip).*;
    self.ip += 3;
    return self.chunk.constants.items[constant_id];
}
