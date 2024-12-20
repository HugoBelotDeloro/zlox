const std = @import("std");
const Chunk = @import("Chunk.zig");
const OpCode = Chunk.OpCode;
const Value = @import("value.zig").Value;
const Obj = @import("Obj.zig");
const Table = @import("table.zig").Table;

const Vm = @This();

const DebugTraceExecution = true and !@import("builtin").is_test;
const StackBaseSize = 1 << 8;

const Error = error{
    NotANumber,
    NotAString,
    NotANumberOrString,
    UnknownOpCode,
    UndefinedSymbol,
};

fn errorString(err: anyerror) ?[]const u8 {
    return switch (err) {
        Error.NotANumber => "Operand must be a number.",
        Error.NotAString => "Not a string",
        Error.NotANumberOrString => "Not a number or a string",
        Error.UnknownOpCode => "Unknown OpCode",
        Error.UndefinedSymbol => "Undefined Symbol",
        else => null,
    };
}

const FramesMax: usize = 64;

frames: [FramesMax]CallFrame,
frameCount: u8,
stack: []Value,
stack_top: [*]Value,
/// Value is not used but must be non-zero to distinguish tombstones from empty cells.
strings: *Table(u8),
globals: Table(Value),

allocator: std.mem.Allocator,

const CallFrame = struct {
    function: *Obj.Function,
    ip: [*]u8,
    slots: []Value,
};

pub fn interpret(function: *Obj.Function, strings: *Table(u8), allocator: std.mem.Allocator, writer: std.io.AnyWriter) !InterpretResult {
    var vm = try Vm.init(allocator, function, strings);
    defer vm.deinit();

    return vm.run(writer) catch |err| {
        if (errorString(err)) |msg| {
            _ = try writer.print("[line {d} in script] {s}\n", .{ vm.currentFrame().function.chunk.getLine(vm.instructionIndex()), msg });
        }
        vm.resetStack();
        return error.RuntimeError;
    };
}

fn run(self: *Vm, writer: std.io.AnyWriter) !InterpretResult {
    var frame = &self.frames[self.frameCount - 1];

    while (true) {
        if (DebugTraceExecution) {
            const stderr = std.io.getStdErr().writer().any();
            try self.printStack(stderr);
            const chunk = &frame.function.chunk;
            _ = try @import("debug.zig")
            .disassembleInstruction(chunk, frame.ip - chunk.code.items.ptr, stderr);
        }

        try switch (self.readInstruction()) {
            .Print => try writer.print("{}\n", .{self.pop()}),
            .Jump => {
                const offset = self.readShort();
                frame.ip += offset;
            },
            .JumpIfFalse => {
                const offset = self.readShort();
                if (isFalsey(self.peek(0))) frame.ip += offset;
            },
            .Loop => {
                const offset = self.readShort();
                frame.ip -= offset;
            },
            .Return => {
                return .Ok;
            },
            .Constant => {
                const constant = self.readConstant();
                try self.pushConstant(constant);
            },
            .ConstantLong => {
                const constant = self.readConstantLong();
                try self.pushConstant(constant);
            },
            .Nil => self.push(Value.nil()),
            .True => self.push(Value.boolean(true)),
            .False => self.push(Value.boolean(false)),
            .Dup => self.push(self.peek(0)),
            .Pop => {
                _ = self.pop();
            },
            .PopN => {
                const n = self.currentFrame().ip[0];
                frame.ip += 1;
                self.popN(n);
            },
            .GetLocal => {
                const slot = frame.ip[0];
                frame.ip += 1;
                try self.push(frame.slots[slot]);
            },
            .SetLocal => {
                const slot = frame.ip[0];
                frame.ip += 1;
                frame.slots[slot] = self.peek(0);
            },
            .GetGlobal => {
                const name = try self.readString();
                if (self.globals.get(name)) |global| {
                    try self.push(global);
                } else {
                    return Error.UndefinedSymbol;
                }
            },
            .GetGlobalLong => {
                const name = try self.readStringLong();
                if (self.globals.get(name)) |global| {
                    try self.push(global);
                } else {
                    return Error.UndefinedSymbol;
                }
            },
            .DefineGlobal => {
                const name = try self.readString();
                _ = try self.globals.set(name, self.peek(0));
                _ = self.pop();
            },
            .DefineGlobalLong => {
                const name = try self.readStringLong();
                _ = try self.globals.set(name, self.peek(0));
                _ = self.pop();
            },
            .SetGlobal => {
                const name = try self.readString();
                if (try self.globals.set(name, self.peek(0))) {
                    _ = self.globals.delete(name);
                    return Error.UndefinedSymbol;
                }
            },
            .SetGlobalLong => {
                const name = try self.readStringLong();
                if (try self.globals.set(name, self.peek(0))) {
                    _ = self.globals.delete(name);
                    return Error.UndefinedSymbol;
                }
            },
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
            else => return Error.UnknownOpCode,
        };
    }
    unreachable;
}

fn init(allocator: std.mem.Allocator, function: *Obj.Function, strings: *Table(u8)) !Vm {
    const stack = try allocator.alloc(Value, StackBaseSize);

    var self = Vm{
        .frames = .{undefined} ** FramesMax,
        .frameCount = 0,
        .stack = stack,
        .stack_top = stack.ptr,
        .allocator = allocator,
        .strings = strings,
        .globals = Table(Value).init(allocator),
    };

    try self.push(Value.any(function));

    self.frames[0] = CallFrame{
        .function = function,
        .ip = function.chunk.code.items.ptr,
        .slots = self.stack,
    };
    self.frameCount += 1;

    return self;
}

fn deinit(self: *Vm) void {
    self.allocator.free(self.stack);
    self.globals.deinit();
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

fn popN(self: *Vm, n: usize) void {
    self.stack_top -= n;
}

fn readInstruction(self: *Vm) OpCode {
    const instr = self.currentFrame().ip[0];
    self.currentFrame().ip += 1;
    return @enumFromInt(instr);
}

fn readConstant(self: *Vm) Value {
    const id = self.currentFrame().ip[0];
    self.currentFrame().ip += 1;
    return self.currentFrame().function.chunk.constants.items[id];
}

fn readShort(self: *Vm) u16 {
    const val: u16 = @as(u16, self.currentFrame().ip[0]) << 8 | self.currentFrame().ip[1];
    self.currentFrame().ip += 2;
    return val;
}

fn readString(self: *Vm) !*Obj.String {
    const obj = self.readConstant().asObj() orelse return Error.NotAString;
    return obj.asString() orelse return Error.NotAString;
}

fn readConstantLong(self: *Vm) Value {
    const id = std.mem.bytesAsValue(u24, self.currentFrame().ip).*;
    self.currentFrame().ip += 3;
    return self.currentFrame().function.chunk.constants.items[id];
}

fn readStringLong(self: *Vm) !*Obj.String {
    const obj = self.readConstantLong().asObj() orelse return Error.NotAString;
    return obj.asString() orelse return Error.NotAString;
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
    _ = try writer.write("        > ");
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
    return self.currentFrame().ip - self.currentFrame().function.chunk.code.items.ptr;
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
            const Args = struct {
                a: []const u8,
                b: []const u8,

                fn copySlices(buf: []u8, data: *const anyopaque) void {
                    const args: *const @This() = @ptrCast(@alignCast(data));
                    const slice_a = args.a;
                    const slice_b = args.b;
                    @memcpy(buf[0..slice_a.len], slice_a);
                    @memcpy(buf[slice_a.len..], slice_b);
                }
            };

            const slice_a = str_a.getString();
            const slice_b = str_b.getString();

            const args = Args{
                .a = slice_a,
                .b = slice_b,
            };

            const len = slice_a.len + slice_b.len;

            const str_c = try Obj.String.withFn(Args.copySlices, @ptrCast(&args), len, self.allocator);
            if (self.strings.findString(str_c.getString(), str_c._hash)) |interned| {
                return interned.getObj();
            }
            _ = try self.strings.set(str_c, 0);
            return str_c.getObj();
        }
    }

    return Error.NotAString;
}

fn pushConstant(self: *Vm, constant: Value) !void {
    if (constant.asObj()) |obj| {
        if (obj.asString()) |str| {
            return self.pushString(str);
        }
    }
    try self.push(constant);
}

fn pushString(self: *Vm, str: *Obj.String) !void {
    if (self.strings.findString(str.getString(), str._hash)) |interned| {
        return self.push(Value.any(interned));
    }
    _ = try self.strings.set(str, 0);
    try self.push(Value.any(str));
}

fn currentFrame(self: *Vm) *CallFrame {
    return &self.frames[self.frameCount - 1];
}
