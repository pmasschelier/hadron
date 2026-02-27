const std = @import("std");

const Token = @This();

pub const Span = struct {
    start: usize,
    len: usize,
};

pub const Error = error{
    NewlineInSimpleQuotes,
    ExpectedBangEqual,
    UnexpectedCharacter,
    IntegerTooBig,
    UnexpectedCharacterInInteger,
};

pub const Type = union(enum) {
    integer: struct { len: usize, value: i64 },
    string: Span,
    formatted_string: Span,
    identifier: struct { len: usize },
    @"error": Error,

    // Single-character tokens.
    LEFT_PAREN,
    RIGHT_PAREN,
    LEFT_BRACE,
    RIGHT_BRACE,
    LEFT_BRACKET,
    RIGHT_BRACKET,
    COMMA,
    DOT,
    SEMICOLON,
    COLON,

    // AdditiveOperator
    MINUS,
    PLUS,

    // AssignmentOperator
    EQUAL,
    PLUS_EQUAL,

    // EqualityOperator
    BANG_EQUAL,
    EQUAL_EQUAL,

    // MultiplicativeOperator
    SLASH,
    MODULO,
    STAR,

    // RelationalOperator
    GREATER,
    GREATER_EQUAL,
    LESS,
    LESS_EQUAL,

    // Keywords.
    IN,
    NOT,
    AND,
    OR,
    FOREACH,
    ENDFOREACH,
    BREAK,
    CONTINUE,
    IF,
    ELIF,
    ELSE,
    ENDIF,
    FALSE,
    TRUE,

    NEWLINE,

    /// Returns the length of the token (for strings it omits the quote)
    pub fn len(self: Type) usize {
        return switch (self) {
            .@"error" => 0,
            .integer => |integer| integer.len,
            .string, .formatted_string => |string| string.len,
            .identifier => |identifier| identifier.len,

            .LEFT_PAREN, .RIGHT_PAREN, .LEFT_BRACE, .RIGHT_BRACE, .LEFT_BRACKET, .RIGHT_BRACKET, .COMMA, .DOT, .SEMICOLON, .COLON, .MINUS, .PLUS, .EQUAL, .SLASH, .MODULO, .STAR, .GREATER, .LESS, .NEWLINE => 1,
            .PLUS_EQUAL, .BANG_EQUAL, .EQUAL_EQUAL, .GREATER_EQUAL, .LESS_EQUAL, .IN, .OR, .IF => 2,
            .NOT, .AND => 3,
            .ELIF, .ELSE, .TRUE => 4,
            .BREAK, .ENDIF, .FALSE => 5,

            .FOREACH => 7,
            .CONTINUE => 8,
            .ENDFOREACH => 10,
        };
    }
};

pub const Tag = std.meta.Tag(Type);

pub const Location = struct {
    row: usize,
    col: usize,
};

type: Type,
start: usize,

pub fn lexeme(self: Token, source: []const u8) []const u8 {
    return switch (self.type) {
        .string, .formatted_string => |string| source[string.start..][0..string.len],
        else => |t| source[self.start..][0..t.len()],
    };
}

pub fn location(self: Token, source: []const u8) Location {
    var line_start: usize = 0;
    var line_end: usize = std.mem.indexOfPos(u8, source, 0, "\n") orelse source.len;
    var line_no: usize = 1;
    while (self.start > line_end) {
        line_no += 1;
        line_start = line_end + 1;
        line_end = std.mem.indexOfPos(u8, source, line_start, "\n") orelse break;
    }
    return Location{
        .col = self.start - line_start,
        .row = line_no,
    };
}

test "size" {
    std.debug.print("Token: {} bytes\n", .{@sizeOf(@This())});
}
