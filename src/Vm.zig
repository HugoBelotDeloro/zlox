const std = @import("std");
const Chunk = @import("Chunk.zig");
const OpCode = Chunk.OpCode;
const Value = @import("value.zig").Value;

const Vm = @This();

const DEBUG_TRACE_EXECUTION = true and !@import("builtin").is_test;
const STACK_BASE_SIZE = 1 << 8;

/// Not owned by Vm
chunk: *const Chunk,
ip: [*]u8,
stack: []Value,
stack_top: [*]Value,

allocator: std.mem.Allocator,

pub fn interpret(chunk: *const Chunk, allocator: std.mem.Allocator, writer: std.io.AnyWriter) !InterpretResult {
    var vm = try Vm.init(allocator, chunk);
    defer vm.deinit();

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
                try vm.push(constant);
            },
            .OP_CONSTANT_LONG => {
                const constant = vm.readConstantLong();
                try vm.push(constant);
            },
            .OP_ADD => {
                const r = vm.pop();
                const l = vm.pop();
                try vm.push(l + r);
            },
            .OP_SUBTRACT => {
                const r = vm.pop();
                const l = vm.pop();
                try vm.push(l - r);
            },
            .OP_MULTIPLY => {
                const r = vm.pop();
                const l = vm.pop();
                try vm.push(l * r);
            },
            .OP_DIVIDE => {
                const r = vm.pop();
                const l = vm.pop();
                try vm.push(l / r);
            },
            .OP_NEGATE => {
                try vm.push(-vm.pop());
            },
            else => {},
        }
    }
    unreachable;
}

fn init(allocator: std.mem.Allocator, chunk: *const Chunk) !Vm {
  const stack = try allocator.alloc(f64, STACK_BASE_SIZE);
    return Vm{
            .chunk = chunk,
            .ip = chunk.code.items.ptr,
            .stack = stack,
            .stack_top = stack.ptr,
            .allocator = allocator,
    };
}

fn deinit(self: *Vm) void {
    self.allocator.free(self.stack);
}

pub const InterpretResult = enum {
    OK,
    COMPILE_ERROR,
    RUNTIME_ERROR,
};

fn push(self: *Vm, value: Value) !void {
    const stack_size = self.stack_top - self.stack.ptr;
    if (stack_size == self.stack.len) {
        const new_stack = try self.allocator.realloc(self.stack, stack_size * 2);
        std.mem.copyForwards(Value, new_stack, self.stack);
    }
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
    var slot: [*]Value = self.stack.ptr;
    while (self.stack_top - slot > 0) : (slot += 1) {
        _ = try writer.print("[ {d} ]", .{slot[0]});
    }
    _ = try writer.write("\n");
}
