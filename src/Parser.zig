const std = @import("std");
const Scanner = @import("Scanner.zig");
const Token = Scanner.Token;
const TokenType = Scanner.TokenType;
const Chunk = @import("Chunk.zig");
const OpCode = Chunk.OpCode;
const Value = @import("value.zig").Value;
const Obj = @import("Obj.zig");

const Parser = @This();

const DebugPrintChunk = true and !@import("builtin").is_test;

const Error = error{
    ExpectEndOfExpression,
    ExpectExpression,
    UnclosedParenthese,
    MissingSemicolon,
} || std.mem.Allocator.Error || std.fmt.ParseFloatError;

var error_token: ?Token = null;

current: Token,
previous: Token,
scanner: Scanner,
chunk: *Chunk,
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
    prefix: ?*const fn (*Parser) Error!void,
    infix: ?*const fn (*Parser) Error!void,
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
        .Identifier = .{ .prefix = null, .infix = null, .precedence = .None },
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

fn init(source: []const u8, chunk: *Chunk, alloc: std.mem.Allocator) Parser {
    return Parser{
        .scanner = Scanner.init(source),
        .chunk = chunk,
        .previous = undefined,
        .current = undefined,
        .alloc = alloc,
    };
}

pub fn compile(source: []const u8, chunk: *Chunk, alloc: std.mem.Allocator) !void {
    var self = Parser.init(source, chunk, alloc);

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
            std.debug.print("{any}", .{token});
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

fn emitInstructions(self: *Parser, comptime instructions: anytype) !void {
    inline for (instructions) |instruction| {
        try self.emitInstruction(instruction);
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

fn number(self: *Parser) Error!void {
    const value = try std.fmt.parseFloat(f64, self.previous.lexeme);
    return self.emitConstant(Value{
        .Number = value,
    });
}

fn string(self: *Parser) Error!void {
    const str = self.previous.lexeme[1 .. self.previous.lexeme.len - 1];
    const str_obj = try Obj.String.fromConstant(str, self.alloc);
    const obj = Value.obj(str_obj.getObj());
    try self.chunk.writeConstant(obj, self.previous.line);
}

fn grouping(self: *Parser) Error!void {
    try self.expression();
    try self.consume(.RightParen, Error.UnclosedParenthese);
}

fn unary(self: *Parser) Error!void {
    const operator = self.previous.typ;
    try self.parsePrecedence(.Unary);

    switch (operator) {
        .Minus => try self.emitInstruction(.Negate),
        .Bang => try self.emitInstruction(.Not),
        else => unreachable,
    }
}

fn binary(self: *Parser) !void {
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

fn nil(self: *Parser) !void {
    try self.emitInstruction(.Nil);
}

fn @"true"(self: *Parser) !void {
    try self.emitInstruction(.True);
}

fn @"false"(self: *Parser) !void {
    try self.emitInstruction(.False);
}

fn expression(self: *Parser) !void {
    try self.parsePrecedence(.Assignment);
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

fn declaration(self: *Parser) !void {
    try self.statement();

    if (self.panic_mode) try self.synchronize();
}

fn statement(self: *Parser) !void {
    if (try self.match(.Print)) {
        return self.printStatement();
    } else {
        return self.expressionStatement();
    }
}

fn parsePrecedence(self: *Parser, precedence: Precedence) Error!void {
    try self.advance();

    if (getRule(self.previous.typ).prefix) |prefixFn| {
        try prefixFn(self);
    } else {
        try self.errorAtCurrent(Error.ExpectExpression);
    }

    while (@intFromEnum(precedence) <= @intFromEnum(getRule(self.current.typ).precedence)) {
        try self.advance();
        if (getRule(self.previous.typ).infix) |infixFn| {
            try infixFn(self);
        } else unreachable;
    }
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
