const std = @import("std");
const bytecode = @import("bytecode.zig");
const Chunk = bytecode.Chunk;
const OpCode = bytecode.OpCode;
const Value = @import("value.zig").Value;

const VM = @This();

const DEBUG_TRACE_EXECUTION = true and !@import("builtin").is_test;
const STACK_MAX = 1 << 8;

chunk: *Chunk,
ip: [*]u8,
stack: [STACK_MAX]Value,
stack_top: [*]Value,

pub fn interpret(chunk: *Chunk, writer: std.io.AnyWriter) !InterpretResult {
    var vm = VM{
        .chunk = chunk,
        .ip = chunk.code.items.ptr,
        .stack = undefined,
        .stack_top = undefined,
    };
    vm.stack_top = &vm.stack;

    while (true) {
        if (DEBUG_TRACE_EXECUTION) {
            const stderr = std.io.getStdErr().writer().any();
            _ = try stderr.write("          ");
            var slot: [*]Value = &vm.stack;
            while (vm.stack_top - slot > 0) : (slot += 1) {
                _ = try stderr.print("[ {d} ]", .{slot[0]});
            }
            _ = try stderr.write("\n");
            _ = try @import("debug.zig").disassembleInstruction(vm.chunk, vm.ip - vm.chunk.code.items.ptr, stderr);
        }
        switch (vm.read_instruction()) {
            .OP_RETURN => {
                try writer.print("{d}\n", .{vm.pop()});
                return .OK;
            },
            .OP_CONSTANT => {
                const constant = vm.read_constant();
                vm.push(constant);
            },
            .OP_CONSTANT_LONG => {
                const constant = vm.read_constant_long();
                vm.push(constant);
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

fn push(self: *VM, value: Value) void {
    self.stack_top[0] = value;
    self.stack_top += 1;
}

fn pop(self: *VM) Value {
    self.stack_top -= 1;
    return self.stack_top[0];
}

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
