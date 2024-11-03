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
    ExpectIdentifier,
    UnclosedBlock,
    UnclosedParenthese,
    MissingSemicolon,
    InvalidAssignmentTarget,
    TooManyLocalVariables,
} || std.mem.Allocator.Error || std.fmt.ParseFloatError;

var error_token: ?Token = null;

current: Token,
previous: Token,
scanner: Scanner,
chunk: *Chunk,
strings: *Table(u8),
compiler: Compiler,
had_error: bool = false,
panic_mode: bool = false,

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
        .And = .{ .prefix = null, .infix = null, .precedence = .None },
        .Class = .{ .prefix = null, .infix = null, .precedence = .None },
        .Else = .{ .prefix = null, .infix = null, .precedence = .None },
        .False = .{ .prefix = @"false", .infix = null, .precedence = .None },
        .For = .{ .prefix = null, .infix = null, .precedence = .None },
        .Fun = .{ .prefix = null, .infix = null, .precedence = .None },
        .If = .{ .prefix = null, .infix = null, .precedence = .None },
        .Nil = .{ .prefix = nil, .infix = null, .precedence = .None },
        .Or = .{ .prefix = null, .infix = null, .precedence = .None },
        .Print = .{ .prefix = null, .infix = null, .precedence = .None },
        .Return = .{ .prefix = null, .infix = null, .precedence = .None },
        .Super = .{ .prefix = null, .infix = null, .precedence = .None },
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

const Compiler = struct {
    locals: [std.math.maxInt(u8) + 1]Local,
    localCount: u8,
    scopeDepth: u8,
};

fn init(source: []const u8, chunk: *Chunk, strings: *Table(u8), alloc: std.mem.Allocator) Parser {
    return Parser{
        .scanner = Scanner.init(source),
        .chunk = chunk,
        .strings = strings,
        .compiler = Compiler{
            .locals = undefined,
            .localCount = 0,
            .scopeDepth = 0,
        },
        .previous = undefined,
        .current = undefined,
        .alloc = alloc,
    };
}

pub fn compile(source: []const u8, chunk: *Chunk, strings: *Table(u8), alloc: std.mem.Allocator) !void {
    var self = Parser.init(source, chunk, strings, alloc);

    try self.advance();

    while (self.current.typ != .Eof) {
        self.declaration() catch |err| try reportError(error_token.?, @errorName(err), std.io.getStdErr().writer().any());
    }
    try self.consume(.Eof, Error.ExpectEndOfExpression);
    try self.endCompiler();

    if (self.had_error) {
        return error.ParsingError;
    } else if (DebugPrintChunk) {
        try @import("debug.zig").disassembleChunk(self.chunk, "compilation result", std.io.getStdErr().writer().any());
    }
}

fn advance(self: *Parser) Error!void {
    self.previous = self.current;
    self.current = self.scanner.next() orelse return Error.ExpectEndOfExpression;

    while (self.current.typ == .Error) {
        if (self.scanner.next()) |token| {
            self.current = token;
        }
    }
}

fn consume(self: *Parser, typ: TokenType, err: Error) Error!void {
    if (self.current.typ == typ) {
        try self.advance();
        return;
    }
    try self.errorAtCurrent(err);
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
    return self.chunk.writeInstruction(instr, self.previous.line);
}

fn emitInstructions(self: *Parser, instructions: anytype) !void {
    inline for (instructions) |instruction| {
        if (@TypeOf(instruction) == u8) {
            try self.emitInstruction(@enumFromInt(instruction));
        } else {
            try self.emitInstruction(instruction);
        }
    }
}

fn emitConstant(self: *Parser, constant: Value) !void {
    return self.chunk.writeConstant(constant, self.previous.line);
}

fn errorAtCurrent(self: *Parser, err: Error) Error!void {
    try self.errorAt(&self.current, err);
}

fn errorAt(self: *Parser, token: *Token, err: Error) Error!void {
    if (self.panic_mode) return;
    self.panic_mode = true;
    self.had_error = true;

    error_token = token.*;
    return err;
}

fn endCompiler(self: *Parser) !void {
    return self.emitInstruction(.Return);
}

fn beginScope(self: *Parser) void {
    self.compiler.scopeDepth += 1;
}

fn endScope(self: *Parser) !void {
    self.compiler.scopeDepth -= 1;

    const initial: u8 = self.compiler.localCount;
    while (self.compiler.localCount > 0 and (self.compiler.locals[self.compiler.localCount - 1].depth
orelse 0) > self.compiler.scopeDepth) {
        self.compiler.localCount -= 1;
    }

    try self.emitInstruction(.PopN);
    try self.emitInstruction(@enumFromInt(initial - self.compiler.localCount));
}

fn number(self: *Parser, can_assign: bool) Error!void {
    _ = can_assign;
    const value = try std.fmt.parseFloat(f64, self.previous.lexeme);
    return self.emitConstant(Value{
        .Number = value,
    });
}

fn string(self: *Parser, can_assign: bool) Error!void {
    _ = can_assign;
    const str = self.previous.lexeme[1 .. self.previous.lexeme.len - 1];
    const str_obj = try self.tryIntern(str);
    const obj = Value.obj(str_obj.getObj());
    try self.chunk.writeConstant(obj, self.previous.line);
}

fn variable(self: *Parser, can_assign: bool) Error!void {
    try self.namedVariable(can_assign);
}

fn namedVariable(self: *Parser, can_assign: bool) Error!void {
    const arg = self.resolveLocal(&self.previous);
    const x: usize = if (arg == null) 1 else 0;
    const y: usize = if (arg orelse 0 <= 255) 0 else 1;
    const opcodes: [2][2][2]OpCode = .{ .{ .{.SetLocal, undefined},
        .{.GetLocal, undefined}},
        .{.{.SetGlobal, .SetGlobalLong},
        .{.GetGlobal, .GetGlobalLong}}};
    const set_op = opcodes[x][0][y];
    const get_op = opcodes[x][1][y];
    const arg2: usize = arg orelse try self.identifierConstant(&self.previous);

    if (can_assign and try self.match(.Equal)) {
        try self.expression();
        try self.emitInstruction(set_op);
        try self.chunk.writeConstantId(arg2, self.previous.line);
    } else {
        try self.emitInstruction(get_op);
        try self.chunk.writeConstantId(arg2, self.previous.line);
    }
}

fn grouping(self: *Parser, can_assign: bool) Error!void {
    _ = can_assign;
    try self.expression();
    try self.consume(.RightParen, Error.UnclosedParenthese);
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

    try self.consume(.RightBrace, Error.UnclosedBlock);
}

fn varDeclaration(self: *Parser) !void {
    const global_id = try self.parseVariable(Error.ExpectIdentifier);

    if (try self.match(.Equal)) {
        try self.expression();
    } else {
        try self.emitInstruction(.Nil);
    }
    try self.consume(.Semicolon, Error.MissingSemicolon);

    try self.defineVariable(global_id);
}

fn expressionStatement(self: *Parser) !void {
    try self.expression();
    try self.consume(.Semicolon, Error.MissingSemicolon);
    try self.emitInstruction(.Pop);
}

fn printStatement(self: *Parser) !void {
    try self.expression();
    try self.consume(.Semicolon, Error.MissingSemicolon);
    try self.emitInstruction(.Print);
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
            .Class, .Fun, .Var, .For, .If, .While, .Print, .Return => return true,
            else => try self.advance(),
        }
    }
    return false;
}

fn declaration(self: *Parser) Error!void {
    if (try self.match(.Var)) {
        try self.varDeclaration();
    } else {
        try self.statement();
    }

    if (self.panic_mode) try self.synchronize();
}

fn statement(self: *Parser) !void {
    if (try self.match(.Print)) {
        return self.printStatement();
    }
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
    return self.chunk.addConstant(val);
}

fn resolveLocal(self: *Parser, name: *Token) ?u8 {
    var i: u8 = 0;
    while (i < self.compiler.localCount) : (i += 1) {
        const local = &self.compiler.locals[self.compiler.localCount - i - 1];
        if (std.mem.eql(u8, name.lexeme, local.name.lexeme)) {
            return self.compiler.localCount - i - 1;
        }

        if (i == self.compiler.localCount) break;
    }

    return null;
}

fn addLocal(self: *Parser, name: Token) !void {
    if (self.compiler.localCount == std.math.maxInt(u8))
        return Error.TooManyLocalVariables;
    const local = &self.compiler.locals[self.compiler.localCount];
    self.compiler.localCount += 1;
    local.name = name;
    local.depth = self.compiler.scopeDepth;
}

fn declareVariable(self: *Parser) !void {
    if (self.compiler.scopeDepth == 0) return;

    const name = &self.previous;
    var i: u8 = 0;
    while (i < self.compiler.localCount) : (i += 1) {
        const local = &self.compiler.locals[self.compiler.localCount - i - 1];
        if (local.depth) |depth| if (depth < self.compiler.scopeDepth) break;

        if (std.mem.eql(u8, name.lexeme, local.name.lexeme))
            return Error.AlreadyDeclared;

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

fn parseVariable(self: *Parser, err: Error) !usize {
    try self.consume(.Identifier, err);

    try self.declareVariable();
    if (self.compiler.scopeDepth > 0) return 0;

    return self.identifierConstant(&self.previous);
}

fn defineVariable(self: *Parser, global_id: usize) !void {
    if (self.compiler.scopeDepth > 0) return;
    return self.chunk.writeGlobal(global_id, self.previous.line);
}

fn getRule(typ: TokenType) ParseRule {
    return ParseRule.rules.get(typ);
}

fn reportError(token: Token, msg: []const u8, writer: std.io.AnyWriter) !void {
    try writer.print("[line {d}] Error", .{token.line});
    _ = switch (token.typ) {
        .Eof => try writer.write(" at end"),
        .Error => {},
        else => try writer.print(" at '{s}'", .{token.lexeme}),
    };
    try writer.print(": {s}\n", .{msg});
}

pub fn printTokens(source: []const u8, writer: std.mem.AnyWriter) void {
    var scanner = Scanner.init(source);

    var line: u32 = 0;
    while (try scanner.next()) |token| {
        if (token.line != line) {
            try writer.print("{d: >4} ", .{token.line});
            line = token.line;
        } else {
            _ = try writer.write("   | ");
        }

        try writer.print("{s: <13} {s}\n", .{ @tagName(token.typ), token.start[0..token.length] });

        if (token.typ == .Eof) {
            break;
        }
    }
}
