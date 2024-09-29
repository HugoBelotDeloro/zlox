const std = @import("std");

const Scanner = @This();

start: [*]const u8,
current: [*]const u8,
end: [*]const u8,
line: u32,

pub const Token = struct {
    typ: TokenType,
    start: [*]const u8,
    length: usize,
    line: u32,
};

pub const TokenType = enum {
    // Single-character tokens.
    LEFT_PAREN,
    RIGHT_PAREN,
    LEFT_BRACE,
    RIGHT_BRACE,
    COMMA,
    DOT,
    MINUS,
    PLUS,
    SEMICOLON,
    SLASH,
    STAR,
    // One or two character tokens.
    BANG,
    BANG_EQUAL,
    EQUAL,
    EQUAL_EQUAL,
    GREATER,
    GREATER_EQUAL,
    LESS,
    LESS_EQUAL,
    // Literals.
    IDENTIFIER,
    STRING,
    NUMBER,
    // Keywords.
    AND,
    CLASS,
    ELSE,
    FALSE,
    FOR,
    FUN,
    IF,
    NIL,
    OR,
    PRINT,
    RETURN,
    SUPER,
    THIS,
    TRUE,
    VAR,
    WHILE,

    ERROR,
    EOF,
};

pub fn init(source: []const u8) Scanner {
    return Scanner{
        .start = source.ptr,
        .current = source.ptr,
        .end = source.ptr + source.len,
        .line = 1,
    };
}

pub fn next(self: *Scanner) !?Token {
    self.skipWhitespace();
    self.start = self.current;
    if (self.isAtEnd()) {
        return self.makeToken(.EOF);
    }

    const char = self.advance() orelse unreachable;

    if (isAlpha(char)) return self.identifer();
    if (isDigit(char)) return self.number();

    switch (char) {
        '(' => return self.makeToken(.LEFT_PAREN),
        ')' => return self.makeToken(.RIGHT_PAREN),
        '{' => return self.makeToken(.LEFT_BRACE),
        '}' => return self.makeToken(.RIGHT_BRACE),
        ';' => return self.makeToken(.SEMICOLON),
        ',' => return self.makeToken(.COMMA),
        '.' => return self.makeToken(.DOT),
        '-' => return self.makeToken(.MINUS),
        '+' => return self.makeToken(.PLUS),
        '/' => return self.makeToken(.SLASH),
        '*' => return self.makeToken(.STAR),
        '!' => return self.makeToken(if (self.match('=')) .BANG_EQUAL else .BANG),
        '=' => return self.makeToken(if (self.match('=')) .EQUAL_EQUAL else .EQUAL),
        '<' => return self.makeToken(if (self.match('=')) .LESS_EQUAL else .LESS),
        '>' => return self.makeToken(if (self.match('=')) .GREATER_EQUAL else .GREATER),
        '"' => return self.string(),
        else => {},
    }

    return null;
}

fn skipWhitespace(self: *Scanner) void {
    while (self.peek()) |char| switch (char) {
        ' ', '\t', '\r' => {
            _ = self.advance();
        },
        '\n' => {
            self.line += 1;
            _ = self.advance();
        },
        '/' => if (self.peekNext() == '/') {
            while (self.peek() != '\n' and !self.isAtEnd()) {
                _ = self.advance();
            }
        } else {
            return;
        },
        else => return,
    };
}

fn peek(self: *Scanner) ?u8 {
    if (self.isAtEnd()) return null;
    return self.current[0];
}

fn peekNext(self: *Scanner) ?u8 {
    if (self.isAtEnd() or self.current + 1 == self.end) return null;
    return self.current[1];
}

fn advance(self: *Scanner) ?u8 {
    if (self.isAtEnd()) return null;
    const char = self.current[0];
    self.current += 1;
    return char;
}

fn match(self: *Scanner, expected: u8) bool {
    if (self.isAtEnd() or self.current[0] != expected) {
        return false;
    }

    self.current += 1;
    return true;
}

fn isAtEnd(self: *Scanner) bool {
    return self.current == self.end;
}

fn makeToken(self: *Scanner, typ: TokenType) Token {
    return Token{
        .typ = typ,
        .start = self.start,
        .length = self.current - self.start,
        .line = self.line,
    };
}

fn errorToken(self: *Scanner, msg: []const u8) Token {
    return Token{
        .typ = .ERROR,
        .start = msg.ptr,
        .length = msg.len,
        .line = self.line,
    };
}

fn string(self: *Scanner) Token {
    while (self.peek() != '"' and !self.isAtEnd()) {
        if (self.peek() == '\n') self.line += 1;
        _ = self.advance();
    }

    if (self.isAtEnd()) return self.errorToken("Unterminated string");
    _ = self.advance(); // Closing quote
    return self.makeToken(.STRING);
}

fn isDigit(char: u8) bool {
    return char >= '0' and char <= '9';
}

fn number(self: *Scanner) Token {
    while (isDigit(self.peek() orelse '²')) { // Any non-digit will do
        _ = self.advance();
    }

    if (self.peek() == '.' and isDigit(self.peekNext() orelse '²')) {
        _ = self.advance();

        while (isDigit(self.peek() orelse '²')) {
            _ = self.advance();
        }
    }

    return self.makeToken(.NUMBER);
}

fn isAlpha(char: u8) bool {
    return (char >= 'a' and char <= 'z' or char >= 'A' and char <= 'Z' or char == '_');
}

fn identifer(self: *Scanner) Token {
    while (isAlpha(self.peek() orelse '²') or isDigit(self.peek() orelse '²')) {
        _ = self.advance();
    }
    return self.makeToken(self.identifierType());
}

fn identifierType(self: *Scanner) TokenType {
    const len = self.current - self.start;
    if (len == 0) return .IDENTIFIER;
    const word = self.start[0..len];
    const word_rest = word[1..];

    return switch (word[0]) {
        'a' => checkKeyword(word_rest, "nd", .AND),
        'c' => checkKeyword(word_rest, "lass", .CLASS),
        'e' => checkKeyword(word_rest, "lse", .ELSE),
        'i' => checkKeyword(word_rest, "f", .IF),
        'n' => checkKeyword(word_rest, "il", .NIL),
        'o' => checkKeyword(word_rest, "r", .OR),
        'p' => checkKeyword(word_rest, "rint", .PRINT),
        'r' => checkKeyword(word_rest, "eturn", .RETURN),
        's' => checkKeyword(word_rest, "uper", .SUPER),
        'v' => checkKeyword(word_rest, "ar", .VAR),
        'w' => checkKeyword(word_rest, "hile", .WHILE),
        'f' => if (len == 1) .IDENTIFIER else switch (word_rest[0]) {
            'a' => checkKeyword(word_rest[1..], "lse", .FALSE),
            'o' => checkKeyword(word_rest[1..], "r", .FOR),
            'u' => checkKeyword(word_rest[1..], "n", .FUN),
            else => .IDENTIFIER,
        },
        't' => if (len == 1) .IDENTIFIER else switch (word_rest[0]) {
            'h' => checkKeyword(word_rest[1..], "is", .THIS),
            'r' => checkKeyword(word_rest[1..], "ue", .TRUE),
            else => .IDENTIFIER,
        },
        else => .IDENTIFIER,
    };
}

fn checkKeyword(word: []const u8, keyword: []const u8, typ: TokenType) TokenType {
    return if (std.mem.eql(u8, word, keyword)) typ else .IDENTIFIER;
}
