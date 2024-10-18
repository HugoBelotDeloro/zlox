const std = @import("std");
const Chunk = @import("Chunk.zig");
const OpCode = Chunk.OpCode;
const Value = @import("value.zig").Value;
const Obj = @import("Obj.zig");

const Vm = @This();

const DebugTraceExecution = true and !@import("builtin").is_test;
const StackBaseSize = 1 << 8;

const Error = error{
    NotANumber,
    NotAString,
    NotANumberOrString,
};

fn errorString(err: anyerror) ?[]const u8 {
    return switch (err) {
        Error.NotANumber => "Operand must be a number.",
        else => null,
    };
}

/// Not owned by Vm
chunk: *const Chunk,
ip: [*]u8,
stack: []Value,
stack_top: [*]Value,

allocator: std.mem.Allocator,

pub fn interpret(chunk: *const Chunk, allocator: std.mem.Allocator, writer: std.io.AnyWriter) !InterpretResult {
    var vm = try Vm.init(allocator, chunk);
    defer vm.deinit();

    return vm.run(writer) catch |err| {
        if (errorString(err)) |msg| {
            _ = try writer.print("{s}\n[line {d} in script]\n", .{ msg, vm.chunk.getLine(vm.instructionIndex()) });
        }
        vm.resetStack();
        return error.RuntimeError;
    };
}

fn run(self: *Vm, writer: std.io.AnyWriter) !InterpretResult {
    while (true) {
        if (DebugTraceExecution) {
            const stderr = std.io.getStdErr().writer().any();
            try self.printStack(stderr);
            _ = try @import("debug.zig").disassembleInstruction(self.chunk, self.ip - self.chunk.code.items.ptr, stderr);
        }

        try switch (self.readInstruction()) {
            .Return => {
                try writer.print("{d}\n", .{self.pop()});
                return .Ok;
            },
            .Constant => {
                const constant = self.readConstant();
                try self.push(constant);
            },
            .ConstantLong => {
                const constant = self.readConstantLong();
                try self.push(constant);
            },
            .Nil => self.push(Value.nil()),
            .True => self.push(Value.boolean(true)),
            .False => self.push(Value.boolean(false)),
            .Equal => {
                const b = self.pop();
                const a = self.pop();
                try self.push(Value.boolean(a.eql(b)));
            },
            .Greater => self.binary(.Number, .Gre, Error.NotANumber),
            .Less => self.binary(.Number, .Les, Error.NotANumber),
            .Add => {
                try switch (self.peek(0)) {
                    .Number => self.binary(.Number, .Add, Error.NotANumber),
                    .Obj => self.binary(.Obj, .Cat, Error.NotAString),
                    else => Error.NotANumberOrString,
                };
            },
            .Subtract => self.binary(.Number, .Sub, Error.NotANumber),
            .Multiply => self.binary(.Number, .Mul, Error.NotANumber),
            .Divide => self.binary(.Number, .Div, Error.NotANumber),
            .Not => self.push(Value.boolean(isFalsey(self.pop()))),
            .Negate => switch (self.peek(0)) {
                .Number => |f| {
                    _ = self.pop();
                    try self.push(Value.number(-f));
                },
                else => Error.NotANumber,
            },
            else => {},
        };
    }
    unreachable;
}

fn init(allocator: std.mem.Allocator, chunk: *const Chunk) !Vm {
    const stack = try allocator.alloc(Value, StackBaseSize);
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
    Ok,
    CompileError,
    RuntimeError,
};

fn push(self: *Vm, value: Value) !void {
    const stack_size = self.stack_top - self.stack.ptr;
    if (stack_size == self.stack.len) {
        const index = self.stackIndex();
        self.stack = try self.allocator.realloc(self.stack, stack_size * 2);
        self.stack_top = self.stack.ptr + index;
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

fn peek(self: *Vm, n: usize) Value {
    return (self.stack_top - 1 - n)[0];
}

fn isFalsey(value: Value) bool {
    return switch (value) {
        .Bool => |b| !b,
        .Nil => true,
        else => false,
    };
}

fn printStack(self: *Vm, writer: std.io.AnyWriter) !void {
    _ = try writer.write("          ");
    var slot: [*]Value = self.stack.ptr;
    while (self.stack_top - slot > 0) : (slot += 1) {
        _ = try writer.print("[ {d} ]", .{slot[0]});
    }
    _ = try writer.write("\n");
}

fn stackIndex(self: *Vm) usize {
    return self.stack_top - self.stack.ptr;
}

fn instructionIndex(self: *Vm) usize {
    return self.ip - self.chunk.code.items.ptr;
}

fn resetStack(self: *Vm) void {
    self.stack_top = self.stack.ptr;
}

const BinOp = enum {
    Gre,
    Les,
    Add,
    Sub,
    Mul,
    Div,
    Cat,
};

fn binary(self: *Vm, comptime typ: std.meta.Tag(Value), comptime op: BinOp, comptime err: Error) !void {
    try switch (self.peek(0)) {
        typ => |r| switch (self.peek(1)) {
            typ => |l| {
                _ = self.pop();
                _ = self.pop();
                try self.push(Value.any(switch (op) {
                    inline .Gre => l > r,
                    inline .Les => l < r,
                    inline .Add => l + r,
                    inline .Sub => l - r,
                    inline .Mul => l * r,
                    inline .Div => l / r,
                    inline .Cat => try self.concat(l, r),
                }));
            },
            else => err,
        },
        else => err,
    };
}

fn concat(self: *Vm, a: *Obj, b: *Obj) !*Obj {
    if (a.asString()) |str_a| {
        if (b.asString()) |str_b| {
            const slice_a = str_a.getString();
            const slice_b = str_b.getString();
            const str_c = try Obj.withSize(slice_a.len + slice_b.len, self.allocator);
            const slice_c = str_c.getStringMut();
            @memcpy(slice_c[0..slice_a.len], slice_a);
            @memcpy(slice_c[slice_a.len..], slice_b);
            return str_c.getObj();
        }
    }

    return Error.NotAString;
}
