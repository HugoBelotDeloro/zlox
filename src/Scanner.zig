const std = @import("std");

const Scanner = @This();

start: [*]const u8,
current: [*]const u8,
end: [*]const u8,
line: u32,

pub const Token = struct {
    typ: TokenType,
    lexeme: []const u8,
    line: u32,
};

pub const TokenType = enum {
    // Single-character tokens.
    LeftParen,
    RightParen,
    LeftBrace,
    RightBrace,
    Colon,
    Comma,
    Dot,
    Minus,
    Plus,
    Semicolon,
    Slash,
    Star,
    // One or two character tokens.
    Bang,
    BangEqual,
    Equal,
    EqualEqual,
    Greater,
    GreaterEqual,
    Less,
    LessEqual,
    // Literals.
    Identifier,
    String,
    Number,
    // Keywords.
    And,
    Case,
    Class,
    Continue,
    Default,
    Else,
    False,
    For,
    Fun,
    If,
    Nil,
    Or,
    Print,
    Return,
    Super,
    Switch,
    This,
    True,
    Var,
    While,

    Error,
    Eof,
};

pub fn init(source: []const u8) Scanner {
    return Scanner{
        .start = source.ptr,
        .current = source.ptr,
        .end = source.ptr + source.len,
        .line = 1,
    };
}

pub fn next(self: *Scanner) ?Token {
    self.skipWhitespace();
    self.start = self.current;
    if (self.isAtEnd()) {
        return self.makeToken(.Eof);
    }

    const char = self.advance() orelse unreachable;

    if (isAlpha(char)) return self.identifer();
    if (isDigit(char)) return self.number();

    switch (char) {
        '(' => return self.makeToken(.LeftParen),
        ')' => return self.makeToken(.RightParen),
        '{' => return self.makeToken(.LeftBrace),
        '}' => return self.makeToken(.RightBrace),
        ':' => return self.makeToken(.Colon),
        ';' => return self.makeToken(.Semicolon),
        ',' => return self.makeToken(.Comma),
        '.' => return self.makeToken(.Dot),
        '-' => return self.makeToken(.Minus),
        '+' => return self.makeToken(.Plus),
        '/' => return self.makeToken(.Slash),
        '*' => return self.makeToken(.Star),
        '!' => return self.makeToken(if (self.match('=')) .BangEqual else .Bang),
        '=' => return self.makeToken(if (self.match('=')) .EqualEqual else .Equal),
        '<' => return self.makeToken(if (self.match('=')) .LessEqual else .Less),
        '>' => return self.makeToken(if (self.match('=')) .GreaterEqual else .Greater),
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
    const len = self.current - self.start;
    return Token{
        .typ = typ,
        .lexeme = self.start[0..len],
        .line = self.line,
    };
}

fn errorToken(self: *Scanner, msg: []const u8) Token {
    return Token{
        .typ = .Error,
        .lexeme = msg,
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
    return self.makeToken(.String);
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

    return self.makeToken(.Number);
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
    if (len == 0) return .Identifier;
    const word = self.start[0..len];
    const word_rest = word[1..];

    return switch (word[0]) {
        'a' => checkKeyword(word_rest, "nd", .And),
        'c' => if (len == 1) .Identifier else switch(word_rest[0]) {
            'a' => checkKeyword(word_rest[1..], "se", .Case),
            'l' => checkKeyword(word_rest[1..], "ass", .Class),
            'o' => checkKeyword(word_rest[1..], "ntinue", .Continue),
            else => .Identifier,
        },
        'd' => checkKeyword(word_rest, "efault", .Default),
        'e' => checkKeyword(word_rest, "lse", .Else),
        'i' => checkKeyword(word_rest, "f", .If),
        'n' => checkKeyword(word_rest, "il", .Nil),
        'o' => checkKeyword(word_rest, "r", .Or),
        'p' => checkKeyword(word_rest, "rint", .Print),
        'r' => checkKeyword(word_rest, "eturn", .Return),
        's' => if (len == 1) .Identifier else switch (word_rest[0]) {
            'u' => checkKeyword(word_rest[1..], "per", .Super),
            'w' => checkKeyword(word_rest[1..], "itch", .Switch),
            else => .Identifier,
        },
        'v' => checkKeyword(word_rest, "ar", .Var),
        'w' => checkKeyword(word_rest, "hile", .While),
        'f' => if (len == 1) .Identifier else switch (word_rest[0]) {
            'a' => checkKeyword(word_rest[1..], "lse", .False),
            'o' => checkKeyword(word_rest[1..], "r", .For),
            'u' => checkKeyword(word_rest[1..], "n", .Fun),
            else => .Identifier,
        },
        't' => if (len == 1) .Identifier else switch (word_rest[0]) {
            'h' => checkKeyword(word_rest[1..], "is", .This),
            'r' => checkKeyword(word_rest[1..], "ue", .True),
            else => .Identifier,
        },
        else => .Identifier,
    };
}

fn checkKeyword(word: []const u8, keyword: []const u8, typ: TokenType) TokenType {
    return if (std.mem.eql(u8, word, keyword)) typ else .Identifier;
}
