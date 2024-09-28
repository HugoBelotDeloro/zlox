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
    self.start = self.current;
    if (self.start == self.end) {
        return self.makeToken(.EOF);
    }

    return null;
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
