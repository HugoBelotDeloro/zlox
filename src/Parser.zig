const std = @import("std");
const Scanner = @import("Scanner.zig");
const Token = Scanner.Token;
const TokenType = Scanner.TokenType;
const Chunk = @import("Chunk.zig");
const OpCode = Chunk.OpCode;
const Value = @import("value.zig").Value;
const Obj = @import("Obj.zig");
const Table = @import("table.zig").Table;

const Parser = @This();

const DebugPrintChunk = true and !@import("builtin").is_test;

const Error = error{
    AlreadyDeclared,
    ExpectEndOfExpression,
    ExpectExpression,
    JumpTooLong,
    InvalidAssignmentTarget,
    NotInLoop,
    TooManyLocalVariables,
    Unexpected,
    VariableUsedInItsOwnInitialization,

    /// Generic error
    ParsingError,
} || std.mem.Allocator.Error || std.fmt.ParseFloatError || std.io.AnyWriter.Error;

var error_token: ?Token = null;

var expected: ?[]const u8 = null;

current: Token,
previous: Token,
scanner: Scanner,
strings: *Table(u8),
compiler: *Compiler,
had_error: bool = false,
panic_mode: bool = false,
continue_offsets: std.ArrayList(usize),
break_jumps: std.ArrayList(std.ArrayList(usize)),

alloc: std.mem.Allocator,

const Precedence = enum {
    None,
    Assignment, // =
    Or, // or
    And, // and
    Equality, // == !=
    Comparison, // < > <= >=
    Term, // + -
    Factor, // * /
    Unary, // ! -
    Call, // . ()
    Primary,
};

const ParseRule = struct {
    prefix: ?*const fn (*Parser, bool) Error!void,
    infix: ?*const fn (*Parser, bool) Error!void,
    precedence: Precedence,

    const rules = std.EnumArray(TokenType, ParseRule).init(.{
        .LeftParen = .{ .prefix = grouping, .infix = null, .precedence = .None },
        .RightParen = .{ .prefix = null, .infix = null, .precedence = .None },
        .LeftBrace = .{ .prefix = null, .infix = null, .precedence = .None },
        .RightBrace = .{ .prefix = null, .infix = null, .precedence = .None },
        .Colon = .{ .prefix = null, .infix = null, .precedence = .None },
        .Comma = .{ .prefix = null, .infix = null, .precedence = .None },
        .Dot = .{ .prefix = null, .infix = null, .precedence = .None },
        .Minus = .{ .prefix = unary, .infix = binary, .precedence = .Term },
        .Plus = .{ .prefix = null, .infix = binary, .precedence = .Term },
        .Semicolon = .{ .prefix = null, .infix = null, .precedence = .None },
        .Slash = .{ .prefix = null, .infix = binary, .precedence = .Factor },
        .Star = .{ .prefix = null, .infix = binary, .precedence = .Factor },
        .Bang = .{ .prefix = unary, .infix = null, .precedence = .None },
        .BangEqual = .{ .prefix = binary, .infix = null, .precedence = .None },
        .Equal = .{ .prefix = null, .infix = null, .precedence = .None },
        .EqualEqual = .{ .prefix = null, .infix = binary, .precedence = .Equality },
        .Greater = .{ .prefix = null, .infix = binary, .precedence = .Comparison },
        .GreaterEqual = .{ .prefix = null, .infix = binary, .precedence = .Comparison },
        .Less = .{ .prefix = null, .infix = binary, .precedence = .Comparison },
        .LessEqual = .{ .prefix = null, .infix = binary, .precedence = .Comparison },
        .Identifier = .{ .prefix = variable, .infix = null, .precedence = .None },
        .String = .{ .prefix = string, .infix = null, .precedence = .None },
        .Number = .{ .prefix = number, .infix = null, .precedence = .None },
        .And = .{ .prefix = null, .infix = @"and", .precedence = .And },
        .Break = .{ .prefix = null, .infix = null, .precedence = .None },
        .Case = .{ .prefix = null, .infix = null, .precedence = .None },
        .Class = .{ .prefix = null, .infix = null, .precedence = .None },
        .Continue = .{ .prefix = null, .infix = null, .precedence = .None },
        .Default = .{ .prefix = null, .infix = null, .precedence = .None },
        .Else = .{ .prefix = null, .infix = null, .precedence = .None },
        .False = .{ .prefix = @"false", .infix = null, .precedence = .None },
        .For = .{ .prefix = null, .infix = null, .precedence = .None },
        .Fun = .{ .prefix = null, .infix = null, .precedence = .None },
        .If = .{ .prefix = null, .infix = null, .precedence = .None },
        .Nil = .{ .prefix = nil, .infix = null, .precedence = .None },
        .Or = .{ .prefix = null, .infix = @"or", .precedence = .Or },
        .Print = .{ .prefix = null, .infix = null, .precedence = .None },
        .Return = .{ .prefix = null, .infix = null, .precedence = .None },
        .Super = .{ .prefix = null, .infix = null, .precedence = .None },
        .Switch = .{ .prefix = null, .infix = null, .precedence = .None },
        .This = .{ .prefix = null, .infix = null, .precedence = .None },
        .True = .{ .prefix = @"true", .infix = null, .precedence = .None },
        .Var = .{ .prefix = null, .infix = null, .precedence = .None },
        .While = .{ .prefix = null, .infix = null, .precedence = .None },
        .Error = .{ .prefix = null, .infix = null, .precedence = .None },
        .Eof = .{ .prefix = null, .infix = null, .precedence = .None },
    });
};

const Local = struct {
    name: Token,
    depth: ?u8,
};

const FunctionType = enum {
    Function,
    Script,
};

const Compiler = struct {
    enclosing: ?*Compiler,
    function: *Obj.Function,
    typ: FunctionType,

    locals: [std.math.maxInt(u8) + 1]Local,
    localCount: u8,
    scopeDepth: u8,

    pub fn init(self: *Compiler, typ: FunctionType, parser: *Parser, is_root: bool, alloc: std.mem.Allocator) !void{
        const main_function = try alloc.create(Obj.Function);
        main_function.* = Obj.Function.init(alloc);

        self.* = Compiler {
            .enclosing = if (!is_root) parser.compiler else null,
            .typ = typ,
            .function = main_function,
            .locals = undefined,
            .localCount = 0,
            .scopeDepth = 0,
        };
        parser.compiler = self;

        self.locals[self.localCount] = Local{
            .depth = 0,
            .name = Token{
                .lexeme = "",
                .typ = .Identifier,
                .line = 0,
            }
        };
        self.localCount += 1;
    }

    pub fn deinit(self: *Compiler, parser: *Parser) *Obj.Function {
        if (self.enclosing) |enclosing|
            parser.compiler = enclosing;
        const fun = self.function;
        parser.alloc.destroy(self);
        return fun;
    }
};

fn init(source: []const u8, strings: *Table(u8), alloc: std.mem.Allocator) !Parser {
    const compiler = try alloc.create(Compiler);
    var self = Parser{
        .scanner = Scanner.init(source),
        .strings = strings,
        .compiler = compiler,
        .previous = undefined,
        .current = undefined,
        .continue_offsets = std.ArrayList(usize).init(alloc),
        .break_jumps = std.ArrayList(std.ArrayList(usize)).init(alloc),
        .alloc = alloc,
    };
    try self.compiler.init(.Script, &self, true, alloc);

    return self;
}

fn deinit(self: *Parser) *Obj.Function {
    std.debug.assert(self.continue_offsets.items.len == 0);
    std.debug.assert(self.break_jumps.items.len == 0);
    self.continue_offsets.deinit();
    self.break_jumps.deinit();
    const fun = self.compiler.deinit(self);
    return fun;
}

pub fn compile(source: []const u8, strings: *Table(u8), alloc: std.mem.Allocator) !?*Obj.Function {
    var self = try Parser.init(source, strings, alloc);

    try self.advance();

    while (self.current.typ != .Eof) {
        self.declaration() catch |err| try reportError(error_token.?, err, std.io.getStdErr().writer().any());
    }
    try self.consume(.Eof);
    const fun = try self.endCompiler();
    return if (self.had_error) null else fun;
}

fn advance(self: *Parser) Error!void {
    self.previous = self.current;
    self.current = self.scanner.next() orelse return self.errorAtCurrent(Error.ExpectEndOfExpression);

    while (self.current.typ == .Error) {
        if (self.scanner.next()) |token| {
            self.current = token;
        }
    }
}

fn consume(self: *Parser, typ: TokenType) Error!void {
    if (self.current.typ == typ) {
        try self.advance();
        return;
    }
    expected = @tagName(typ);
    return self.errorAtCurrent(Error.Unexpected);
}

fn check(self: *Parser, typ: TokenType) bool {
    return self.current.typ == typ;
}

fn match(self: *Parser, typ: TokenType) !bool {
    if (!self.check(typ)) return false;
    try self.advance();
    return true;
}

fn emitInstruction(self: *Parser, instr: OpCode) !void {
    return self.currentChunk().writeInstruction(instr, self.previous.line);
}

fn emitInstructions(self: *Parser, instructions: anytype) !void {
    inline for (instructions) |instruction| {
        if (@TypeOf(instruction) == u8 or @TypeOf(instruction) == comptime_int) {
            try self.emitInstruction(@enumFromInt(instruction));
        } else {
            try self.emitInstruction(instruction);
        }
    }
}

fn emitConstant(self: *Parser, constant: Value) !void {
    return self.currentChunk().writeConstant(constant, self.previous.line);
}

fn emitLoop(self: *Parser, loop_start: usize) !void {
    try self.emitInstruction(.Loop);

    const offset = self.currentChunk().code.items.len - loop_start + 2;
    if (offset > std.math.maxInt(u16)) return self.errorAtCurrent(Error.JumpTooLong);

    try self.emitInstructions(.{ @as(u8, @truncate(offset >> 8)), @as(u8, @truncate(offset)) });
}

fn emitJump(self: *Parser, instr: OpCode) !usize {
    try self.emitInstructions(.{ instr, 0xff, 0xff });
    return self.currentChunk().code.items.len - 2;
}

fn patchJump(self: *Parser, offset: usize) !void {
    const jump = self.currentChunk().code.items.len - offset - 2;

    if (jump > std.math.maxInt(u16)) {
        return self.errorAtCurrent(Error.JumpTooLong);
    }

    self.currentChunk().code.items[offset] = @truncate(jump >> 8);
    self.currentChunk().code.items[offset + 1] = @truncate(jump);
}

fn errorAtCurrent(self: *Parser, err: Error) Error {
    return self.errorAt(&self.current, err);
}

fn errorAt(self: *Parser, token: *Token, err: Error) Error {
    if (self.panic_mode) return err;
    self.panic_mode = true;
    self.had_error = true;

    error_token = token.*;
    return err;
}

fn endCompiler(self: *Parser) Error!*Obj.Function {
    try self.emitInstruction(.Return);

    if (self.had_error)
        return Error.ParsingError;
    if (DebugPrintChunk)
        try @import("debug.zig").disassembleFunction(self.compiler.function, std.io.getStdErr().writer().any());

    return self.deinit();
}

fn beginScope(self: *Parser) void {
    self.compiler.scopeDepth += 1;
}

fn endScope(self: *Parser) !void {
    self.compiler.scopeDepth -= 1;

    const initial: u8 = self.compiler.localCount;
    while (self.compiler.localCount > 0 and (self.compiler.locals[self.compiler.localCount - 1].depth orelse 0) > self.compiler.scopeDepth) {
        self.compiler.localCount -= 1;
    }

    try self.emitInstruction(.PopN);
    try self.emitInstruction(@enumFromInt(initial - self.compiler.localCount));
}

fn beginLoop(self: *Parser) !usize {
    const loop_start = self.currentChunk().code.items.len;
    try self.continue_offsets.append(loop_start);
    try self.break_jumps.append(std.ArrayList(usize).init(self.alloc));
    return loop_start;
}

fn endLoop(self: *Parser) !void {
    for (self.break_jumps.getLast().items) |jump| {
        try self.patchJump(jump);
    }

    _ = self.continue_offsets.pop();
    _ = self.break_jumps.pop();
}

fn number(self: *Parser, can_assign: bool) Error!void {
    _ = can_assign;
    const value = try std.fmt.parseFloat(f64, self.previous.lexeme);
    return self.emitConstant(Value{
        .Number = value,
    });
}

fn @"or"(self: *Parser, can_assign: bool) !void {
    _ = can_assign;

    const else_jump = try self.emitJump(.JumpIfFalse);
    const jump = try self.emitJump(.Jump);

    try self.patchJump(else_jump);
    try self.emitInstruction(.Pop);

    try self.parsePrecedence(.Or);
    try self.patchJump(jump);
}

fn string(self: *Parser, can_assign: bool) Error!void {
    _ = can_assign;
    const str = self.previous.lexeme[1 .. self.previous.lexeme.len - 1];
    const str_obj = try self.tryIntern(str);
    const obj = Value.obj(str_obj.getObj());
    try self.currentChunk().writeConstant(obj, self.previous.line);
}

fn variable(self: *Parser, can_assign: bool) Error!void {
    try self.namedVariable(can_assign);
}

fn namedVariable(self: *Parser, can_assign: bool) Error!void {
    const arg = try self.resolveLocal(&self.previous);
    const x: usize = if (arg == null) 1 else 0;
    const y: usize = if (arg orelse 0 <= 255) 0 else 1;
    const opcodes: [2][2][2]OpCode = .{ .{ .{ .SetLocal, undefined }, .{ .GetLocal, undefined } }, .{ .{ .SetGlobal, .SetGlobalLong }, .{ .GetGlobal, .GetGlobalLong } } };
    const set_op = opcodes[x][0][y];
    const get_op = opcodes[x][1][y];
    const arg2: usize = arg orelse try self.identifierConstant(&self.previous);

    if (can_assign and try self.match(.Equal)) {
        try self.expression();
        try self.emitInstruction(set_op);
        try self.currentChunk().writeConstantId(arg2, self.previous.line);
    } else {
        try self.emitInstruction(get_op);
        try self.currentChunk().writeConstantId(arg2, self.previous.line);
    }
}

fn grouping(self: *Parser, can_assign: bool) Error!void {
    _ = can_assign;
    try self.expression();
    try self.consume(.RightParen);
}

fn unary(self: *Parser, can_assign: bool) Error!void {
    _ = can_assign;
    const operator = self.previous.typ;
    try self.parsePrecedence(.Unary);

    switch (operator) {
        .Minus => try self.emitInstruction(.Negate),
        .Bang => try self.emitInstruction(.Not),
        else => unreachable,
    }
}

fn binary(self: *Parser, can_assign: bool) !void {
    _ = can_assign;
    const operator = self.previous.typ;
    const rule = getRule(operator);

    try self.parsePrecedence(@enumFromInt(@intFromEnum(rule.precedence) + 1));

    try switch (operator) {
        .BangEqual => self.emitInstructions(.{ .Equal, .Not }),
        .EqualEqual => self.emitInstruction(.Equal),
        .Greater => self.emitInstruction(.Greater),
        .GreaterEqual => self.emitInstructions(.{ .Less, .Not }),
        .Less => self.emitInstruction(.Less),
        .LessEqual => self.emitInstructions(.{ .Greater, .Not }),
        .Plus => self.emitInstruction(.Add),
        .Minus => self.emitInstruction(.Subtract),
        .Star => self.emitInstruction(.Multiply),
        .Slash => self.emitInstruction(.Divide),
        else => unreachable,
    };
}

fn nil(self: *Parser, can_assign: bool) !void {
    _ = can_assign;
    try self.emitInstruction(.Nil);
}

fn @"true"(self: *Parser, can_assign: bool) !void {
    _ = can_assign;
    try self.emitInstruction(.True);
}

fn @"false"(self: *Parser, can_assign: bool) !void {
    _ = can_assign;
    try self.emitInstruction(.False);
}

fn expression(self: *Parser) !void {
    try self.parsePrecedence(.Assignment);
}

fn block(self: *Parser) !void {
    while (!self.check(.RightBrace) and !self.check(.Eof)) {
        try self.declaration();
    }

    try self.consume(.RightBrace);
}

fn function(self: *Parser, typ: FunctionType) Error!void {
    var compiler: Compiler = undefined;
    try compiler.init(typ, self, false, self.alloc);
    self.beginScope();

    try self.consume(.LeftParen);
    while (!self.check(.RightParen)) {
        if (!try self.match(.Comma)) break;
    }
    try self.consume(.RightParen);
    try self.consume(.LeftBrace);
    try self.block();

    const fun = try self.endCompiler();
    try self.emitInstruction(.Constant);
    try self.emitConstant(Value.any(fun.getObj()));

    _ = compiler.deinit(self);
}

fn funDeclaration(self: *Parser) !void {
    const global = try self.parseVariable();
    self.markInitialized();
    try self.function(.Function);
    try self.defineVariable(global);
}

fn varDeclaration(self: *Parser) !void {
    const global_id = try self.parseVariable();

    if (try self.match(.Equal)) {
        try self.expression();
    } else {
        try self.emitInstruction(.Nil);
    }
    try self.consume(.Semicolon);

    try self.defineVariable(global_id);
}

fn expressionStatement(self: *Parser) !void {
    try self.expression();
    try self.consume(.Semicolon);
    try self.emitInstruction(.Pop);
}

fn forStatement(self: *Parser) !void {
    self.beginScope();
    try self.consume(.LeftParen);
    if (!try self.match(.Semicolon)) {
        if (try self.match(.Var)) {
            try self.varDeclaration();
        } else {
            try self.expressionStatement();
        }
    }

    var loop_start = try self.beginLoop();

    const exit_jump: ?usize = blk: {
        if (try self.match(.Semicolon)) break :blk null;
        try self.expression();
        try self.consume(.Semicolon);

        const exit_jump = try self.emitJump(.JumpIfFalse);
        try self.emitInstruction(.Pop);
        break :blk exit_jump;
    };

    if (!try self.match(.RightParen)) {
        const body_jump = try self.emitJump(.Jump);
        const increment_start = self.currentChunk().code.items.len;
        self.continue_offsets.items[self.continue_offsets.items.len - 1] = increment_start;
        try self.expression();
        try self.emitInstruction(.Pop);
        try self.consume(.RightParen);

        try self.emitLoop(loop_start);
        loop_start = increment_start;
        try self.patchJump(body_jump);
    }

    try self.statement();
    try self.emitLoop(loop_start);

    if (exit_jump) |jmp| {
        try self.patchJump(jmp);
        try self.emitInstruction(.Pop);
    }

    try self.endLoop();
    try self.endScope();
}

fn ifStatement(self: *Parser) !void {
    try self.consume(.LeftParen);
    try self.expression();
    try self.consume(.RightParen);

    const then_jump = try self.emitJump(.JumpIfFalse);
    try self.emitInstruction(.Pop);
    try self.statement();

    const else_jump = try self.emitJump(.Jump);

    try self.patchJump(then_jump);
    try self.emitInstruction(.Pop);

    if (try self.match(.Else)) try self.statement();
    try self.patchJump(else_jump);
}

fn switchStatement(self: *Parser) !void {
    try self.consume(.LeftParen);
    try self.expression();
    try self.consume(.RightParen);

    try self.consume(.LeftBrace);

    var jumps_to_end = std.ArrayList(usize).init(self.alloc);
    var jump_from_previous: usize = 0;
    var is_first = true;
    var has_default = false;

    while (try self.match(.Case)) {
        if (!is_first) {
            try self.patchJump(jump_from_previous);
            try self.emitInstruction(.Pop);
        }
        is_first = false;

        try self.emitInstruction(.Dup);
        try self.expression();
        try self.emitInstruction(.Equal);
        jump_from_previous = try self.emitJump(.JumpIfFalse);

        try self.emitInstruction(.Pop);
        try self.consume(.Colon);
        while (!self.check(.Case) and !self.check(.Default) and !self.check(.RightBrace)) {
            try self.statement();
        }
        if (!self.check(.RightBrace))
            try jumps_to_end.append(try self.emitJump(.Jump));
    }

    if (try self.match(.Default)) {
        has_default = true;
        if (!is_first) {
            try self.patchJump(jump_from_previous);
            try self.emitInstruction(.Pop);
        }
        try self.consume(.Colon);
        while (!self.check(.RightBrace)) {
            try self.statement();
        }
    }

    if (!has_default) try self.patchJump(jump_from_previous);
    for (jumps_to_end.items) |jump|
        try self.patchJump(jump);
    try self.emitInstruction(.Pop);
    try self.consume(.RightBrace);
}

fn continueStatement(self: *Parser) !void {
    if (self.continue_offsets.items.len == 0) return Error.NotInLoop;
    try self.emitLoop(self.continue_offsets.getLast());
    try self.consume(.Semicolon);
}

fn breakStatement(self: *Parser) !void {
    if (self.break_jumps.items.len == 0) return Error.NotInLoop;

    const jumps_list = &self.break_jumps.items[self.break_jumps.items.len - 1];
    try jumps_list.append(try self.emitJump(.Jump));
    try self.consume(.Semicolon);
}

fn printStatement(self: *Parser) !void {
    try self.expression();
    try self.consume(.Semicolon);
    try self.emitInstruction(.Print);
}

fn whileStatement(self: *Parser) !void {
    const loop_start = try self.beginLoop();

    try self.consume(.LeftParen);
    try self.expression();
    try self.consume(.RightParen);

    const exit_jump = try self.emitJump(.JumpIfFalse);
    try self.emitInstruction(.Pop);
    try self.statement();
    try self.emitLoop(loop_start);

    try self.patchJump(exit_jump);
    try self.emitInstruction(.Pop);

    try self.endLoop();
}

fn synchronize(self: *Parser) !void {
    if (try self.discardTokens()) {
        self.panic_mode = false;
    }
}

fn discardTokens(self: *Parser) !bool {
    while (!self.check(.Eof)) {
        if (self.previous.typ == .Semicolon) return true;
        switch (self.current.typ) {
            .Class, .Fun, .Var, .For, .If, .Switch, .While, .Print, .Return => return true,
            else => try self.advance(),
        }
    }
    return false;
}

fn declaration(self: *Parser) Error!void {
    if (try self.match(.Fun)) {
        try self.funDeclaration();
    } else if (try self.match(.Var)) {
        try self.varDeclaration();
    } else {
        try self.statement();
    }

    if (self.panic_mode) try self.synchronize();
}

fn statement(self: *Parser) Error!void {
    if (try self.match(.Print))
        return self.printStatement();
    if (try self.match(.If))
        return self.ifStatement();
    if (try self.match(.While))
        return self.whileStatement();
    if (try self.match(.For))
        return self.forStatement();
    if (try self.match(.Switch))
        return self.switchStatement();
    if (try self.match(.Continue))
        return self.continueStatement();
    if (try self.match(.Break))
        return self.breakStatement();

    if (try self.match(.LeftBrace)) {
        self.beginScope();
        try self.block();
        try self.endScope();
    } else {
        return self.expressionStatement();
    }
}

fn parsePrecedence(self: *Parser, precedence: Precedence) Error!void {
    try self.advance();

    const prefixRule = getRule(self.previous.typ).prefix orelse return self.errorAtCurrent(Error.ExpectExpression);

    const can_assign = @intFromEnum(precedence) <= @intFromEnum(Precedence.Assignment);
    try prefixRule(self, can_assign);

    while (@intFromEnum(precedence) <= @intFromEnum(getRule(self.current.typ).precedence)) {
        try self.advance();
        if (getRule(self.previous.typ).infix) |infixRule| {
            try infixRule(self, can_assign);
        } else unreachable;
    }

    if (can_assign and try self.match(.Equal)) {
        return self.errorAtCurrent(Error.InvalidAssignmentTarget);
    }
}

fn identifierConstant(self: *Parser, token: *Token) !usize {
    const obj = try self.tryIntern(token.lexeme);
    const val = Value.any(obj);
    return self.currentChunk().addConstant(val);
}

fn resolveLocal(self: *Parser, name: *Token) !?u8 {
    var i: u8 = 0;
    while (i < self.compiler.localCount) : (i += 1) {
        const local = &self.compiler.locals[self.compiler.localCount - i - 1];
        if (std.mem.eql(u8, name.lexeme, local.name.lexeme)) {
            if (local.depth == null) return self.errorAtCurrent(Error.VariableUsedInItsOwnInitialization);
            return self.compiler.localCount - i - 1;
        }

        if (i == self.compiler.localCount) break;
    }

    return null;
}

fn addLocal(self: *Parser, name: Token) !void {
    if (self.compiler.localCount == std.math.maxInt(u8))
        return self.errorAtCurrent(Error.TooManyLocalVariables);
    const local = &self.compiler.locals[self.compiler.localCount];
    self.compiler.localCount += 1;
    local.name = name;
    local.depth = null;
}

fn declareVariable(self: *Parser) !void {
    if (self.compiler.scopeDepth == 0) return;

    const name = &self.previous;
    var i: u8 = 0;
    while (i < self.compiler.localCount) : (i += 1) {
        const local = &self.compiler.locals[self.compiler.localCount - i - 1];
        if (local.depth) |depth| if (depth < self.compiler.scopeDepth) break;

        if (std.mem.eql(u8, name.lexeme, local.name.lexeme))
            return self.errorAtCurrent(Error.AlreadyDeclared);

        if (i == self.compiler.localCount) break;
    }
    try self.addLocal(name.*);
}

fn tryIntern(self: *Parser, str: []const u8) !*Obj.String {
    const hash = Obj.String.hash(str);
    if (self.strings.findString(str, hash)) |obj| {
        return obj;
    }
    const obj = try Obj.String.fromConstant(str, self.alloc);
    _ = try self.strings.set(obj, 0);
    return obj;
}

fn parseVariable(self: *Parser) !usize {
    try self.consume(.Identifier);

    try self.declareVariable();
    if (self.compiler.scopeDepth > 0) return 0;

    return self.identifierConstant(&self.previous);
}

fn markInitialized(self: *Parser) void {
    if (self.compiler.scopeDepth == 0) return;
    self.compiler.locals[self.compiler.localCount - 1].depth = self.compiler.scopeDepth;
}

fn defineVariable(self: *Parser, global_id: usize) !void {
    if (self.compiler.scopeDepth > 0) {
        self.markInitialized();
        return;
    }
    return self.currentChunk().writeGlobal(global_id, self.previous.line);
}

fn @"and"(self: *Parser, can_assign: bool) !void {
    _ = can_assign;

    const jump = try self.emitJump(.JumpIfFalse);

    try self.emitInstruction(.Pop);
    try self.parsePrecedence(.And);

    try self.patchJump(jump);
}

fn getRule(typ: TokenType) ParseRule {
    return ParseRule.rules.get(typ);
}

fn reportError(token: Token, err: Error, writer: std.io.AnyWriter) !void {
    try writer.print("[line {d}] Error", .{token.line});
    _ = switch (token.typ) {
        .Eof => try writer.write(" at end"),
        .Error => {},
        else => try writer.print(" at '{s}'", .{token.lexeme}),
    };
    switch (err) {
        Error.Unexpected => try writer.print(": expected {s}\n", .{expected orelse "unknown token"}),
        else => try writer.print(": {s}\n", .{@errorName(err)}),
    }
}

pub fn printTokens(source: []const u8, writer: std.io.AnyWriter) !void {
    var scanner = Scanner.init(source);

    var line: u32 = 0;
    while (scanner.next()) |token| {
        if (token.line != line) {
            try writer.print("{d: >4} ", .{token.line});
            line = token.line;
        } else {
            _ = try writer.write("   | ");
        }

        try writer.print("{s: <13} {s}\n", .{ @tagName(token.typ), token.lexeme });

        if (token.typ == .Eof) {
            break;
        }
    }
}

fn currentChunk(self: *Parser) *Chunk {
    return &self.compiler.function.chunk;
}
