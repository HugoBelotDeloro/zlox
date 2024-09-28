const std = @import("std");
const Chunk = @import("Chunk.zig");
const OpCode = Chunk.OpCode;
const Value = @import("value.zig").Value;

const Vm = @This();

const DEBUG_TRACE_EXECUTION = true and !@import("builtin").is_test;
const STACK_MAX = 1 << 8;

chunk: *Chunk,
ip: [*]u8,
stack: [STACK_MAX]Value,
stack_top: [*]Value,

pub fn interpret(chunk: *Chunk, writer: std.io.AnyWriter) !InterpretResult {
    var vm = Vm{
        .chunk = chunk,
        .ip = chunk.code.items.ptr,
        .stack = undefined,
        .stack_top = undefined,
    };
    vm.stack_top = &vm.stack;

    while (true) {
        if (DEBUG_TRACE_EXECUTION) {
            const stderr = std.io.getStdErr().writer().any();
            try vm.printStack(stderr);
            _ = try @import("debug.zig").disassembleInstruction(vm.chunk, vm.ip - vm.chunk.code.items.ptr, stderr);
        }
        switch (vm.readInstruction()) {
            .OP_RETURN => {
                try writer.print("{d}\n", .{vm.pop()});
                return .OK;
            },
            .OP_CONSTANT => {
                const constant = vm.readConstant();
                vm.push(constant);
            },
            .OP_CONSTANT_LONG => {
                const constant = vm.readConstantLong();
                vm.push(constant);
            },
            .OP_ADD => {
                const r = vm.pop();
                const l = vm.pop();
                vm.push(l + r);
            },
            .OP_SUBTRACT => {
                const r = vm.pop();
                const l = vm.pop();
                vm.push(l - r);
            },
            .OP_MULTIPLY => {
                const r = vm.pop();
                const l = vm.pop();
                vm.push(l * r);
            },
            .OP_DIVIDE => {
                const r = vm.pop();
                const l = vm.pop();
                vm.push(l / r);
            },
            .OP_NEGATE => {
                vm.push(-vm.pop());
            },
            else => {},
        }
    }
    unreachable;
}

pub const InterpretResult = enum {
    OK,
    COMPILE_ERROR,
    RUNTIME_ERROR,
};

fn push(self: *Vm, value: Value) void {
    self.stack_top[0] = value;
    self.stack_top += 1;
}

fn pop(self: *Vm) Value {
    self.stack_top -= 1;
    return self.stack_top[0];
}

fn readInstruction(self: *Vm) OpCode {
    const instr = self.ip[0];
    self.ip += 1;
    return @enumFromInt(instr);
}

fn readConstant(self: *Vm) Value {
    const id = self.ip[0];
    self.ip += 1;
    return self.chunk.constants.items[id];
}

fn readConstantLong(self: *Vm) Value {
    const constant_id = std.mem.bytesAsValue(u24, self.ip).*;
    self.ip += 3;
    return self.chunk.constants.items[constant_id];
}

fn printStack(self: *Vm, writer: std.io.AnyWriter) !void {
    _ = try writer.write("          ");
    var slot: [*]Value = &self.stack;
    while (self.stack_top - slot > 0) : (slot += 1) {
        _ = try writer.print("[ {d} ]", .{slot[0]});
    }
    _ = try writer.write("\n");
}
