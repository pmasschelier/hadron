const std = @import("std");
const Token = @import("token.zig");

const Scanner = @This();
pub const ScanError = std.io.Reader.Error || StringError || std.mem.Allocator.Error || std.fmt.ParseIntError;

const QUOTE_CHAR: u8 = '\'';

start: usize = 0,
reader: std.Io.Reader,
line: []const u8 = &.{},
line_no: usize = 0,
col_no: usize = 0,
line_start: usize = 0,

paren_count: i32 = 0,
bracket_count: i32 = 0,
brace_count: i32 = 0,

const keywords = std.StaticStringMap(Token.Type).initComptime(.{
    .{ "in", .IN },
    .{ "not", .NOT },
    .{ "and", .AND },
    .{ "or", .OR },
    .{ "foreach", .FOREACH },
    .{ "endforeach", .ENDFOREACH },
    .{ "break", .BREAK },
    .{ "continue", .CONTINUE },
    .{ "if", .IF },
    .{ "elif", .ELIF },
    .{ "else", .ELSE },
    .{ "endif", .ENDIF },
    .{ "true", .TRUE },
    .{ "false", .FALSE },
});

pub fn create(reader: std.Io.Reader) !Scanner {
    return Scanner{ .reader = reader };
}

const PeekError = error{
    LineTooLong,
    ReadFailed,
    EndOfStream,
    ExpectedEndOfLine,
};

fn readLine(self: *Scanner) PeekError!void {
    if (self.line.len != 0) {
        if (self.line[self.line.len - 1] == '\n') {
            self.line_start += self.line.len;
            self.col_no = 0;
            self.line_no += 1;
        } else return error.ExpectedEndOfLine;
    }
    self.line = self.reader.takeDelimiterInclusive('\n') catch |err| switch (err) {
        error.EndOfStream => eos: {
            const buffered = self.reader.buffered();
            if (buffered.len == 0)
                return error.EndOfStream;
            self.reader.tossBuffered();
            break :eos buffered;
        },
        error.ReadFailed => return error.ReadFailed,
        error.StreamTooLong => return error.LineTooLong,
    };
}

fn current(self: Scanner) usize {
    return self.line_start + self.col_no;
}

// fn eof(self: Scanner) bool {
//     return self.current >= self.source.len;
// }
//

fn peek(self: *Scanner) PeekError!u8 {
    if (self.col_no >= self.line.len)
        try self.readLine();
    return self.line[self.col_no];
}

fn peekOnLine(self: Scanner) ?u8 {
    return if (self.col_no < self.line.len) self.line[self.col_no] else null;
}

fn toss(self: *Scanner, n: usize) void {
    std.debug.assert(self.col_no + n <= self.line.len);
    self.col_no += n;
}

fn take(self: *Scanner) PeekError!u8 {
    const c = try self.peek();
    self.toss(1);
    return c;
}

//
// fn peekNext(self: Scanner) ?u8 {
//     if (self.current + 1 >= self.source.len) return null;
//     return self.source[self.current + 1];
// }

fn match(self: *Scanner, expected: u8) bool {
    const c = self.peek() catch return false;
    if (c != expected) return false;
    self.toss(1);
    return true;
}

/// Tries to match a sequence of at the position on the current line
/// bytes should not contain a '\n'
fn matchBytes(self: *Scanner, bytes: []const u8) bool {
    if (self.col_no + bytes.len - 1 >= self.line.len) return false;
    for (bytes, 0..) |c, i| {
        if (self.line[self.col_no + i] != c) return false;
    }
    self.toss(bytes.len);
    return true;
}

fn skipWhitespace(self: *Scanner) ?u8 {
    return while (self.peekOnLine()) |c| {
        switch (c) {
            ' ', '\t', std.ascii.control_code.vt, std.ascii.control_code.ff, '\r' => _ = self.toss(1),
            else => {
                self.start = self.line_start + self.col_no;
                break c;
            },
        }
    } else null;
}

// fn recover(self: *Scanner) bool {
//     while (self.reader.takeByte()) |c| if (std.ascii.isWhitespace(c)) break;
//     return self.skipWhitespace();
// }

// fn skipAfterString(self: *Scanner) std.Io.Reader.Error!void {
//     while (self.reader.takeByte()) |c| {
//         if (c == QUOTE_CHAR) break;
//     }
// }

const StringError = error{
    UnterminatedString,
    LineTooLong,
    ReadFailed,
} || PeekError;

fn string(self: *Scanner, formatted: bool) StringError!Token.Type {
    const multiline = self.matchBytes(&.{ QUOTE_CHAR, QUOTE_CHAR }); // Triple quoted strings are multiline
    const offset: usize = if (multiline) 3 else 1;
    var subsequent_quotes: u32 = 0;
    var escaped = false; // Manage escaped characters
    var failed: ?Token.Error = null;
    while (self.take()) |c| {
        subsequent_quotes = if (c == QUOTE_CHAR and !escaped) subsequent_quotes + 1 else 0;
        if (subsequent_quotes == offset) break;
        if (c == '\n') {
            if (!multiline) failed = error.NewlineInSimpleQuotes;
        }
        escaped = c == '\\';
    } else |err| return switch (err) {
        error.EndOfStream => error.UnterminatedString,
        else => |e| e,
    };
    const span = Token.Span{
        .start = self.start + offset,
        .len = self.current() - 2 * offset - self.start,
    };
    return if (failed) |error_code|
        .{ .@"error" = error_code }
    else if (formatted)
        .{ .formatted_string = span }
    else
        .{ .string = span };
}

fn int(self: *Scanner) ScanError!Token.Type {
    self.identifier();
    return if (std.fmt.parseInt(i64, self.line[self.start - self.line_start .. self.col_no], 0)) |value|
        .{ .integer = .{ .len = self.current() - self.start, .value = value } }
    else |err| switch (err) {
        error.Overflow => .{ .@"error" = error.IntegerTooBig },
        error.InvalidCharacter => .{ .@"error" = error.UnexpectedCharacterInInteger },
    };
}

fn identifier(self: *Scanner) void {
    while (self.peekOnLine()) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_') break;
        self.toss(1);
    }
}

fn lineEnd(self: *Scanner) void {
    self.col_no = self.line.len - 1;
    self.start = self.current();
}

fn lexeme(self: Scanner) []const u8 {
    std.debug.assert(self.start >= self.line_start);
    return self.line[self.start - self.line_start .. self.col_no];
}

fn skipWord(self: *Scanner) void {
    while (self.peekOnLine()) |c|
        if (std.ascii.isWhitespace(c)) break;
    self.start = self.current();
}

fn scanToken(self: *Scanner) ScanError!Token {
    const skip_newline = self.paren_count > 0 or self.brace_count > 0 or self.bracket_count > 0;
    // Return the first matched token or null if EOF is reached
    self.start = self.current();
    return scan: while (self.take()) |c| : (self.start = self.current()) {
        const tag: Token.Type = switch (c) {
            '\n' => if (skip_newline) continue :scan else .NEWLINE,
            ' ', '\t', std.ascii.control_code.vt, std.ascii.control_code.ff, '\r' => continue :scan,
            '#' => {
                self.lineEnd();
                continue :scan;
            },
            '(',
            => left_paren: {
                self.paren_count += 1;
                break :left_paren .LEFT_PAREN;
            },
            ')' => right_paren: {
                self.paren_count -= 1;
                break :right_paren .RIGHT_PAREN;
            },
            '[' => left_bracket: {
                self.bracket_count += 1;
                break :left_bracket .LEFT_BRACKET;
            },
            ']' => right_bracket: {
                self.bracket_count -= 1;
                break :right_bracket .RIGHT_BRACKET;
            },
            '{' => left_brace: {
                self.brace_count += 1;
                break :left_brace .LEFT_BRACE;
            },
            '}' => right_brace: {
                self.brace_count -= 1;
                break :right_brace .RIGHT_BRACE;
            },
            ',' => .COMMA,
            '.' => .DOT,
            '-' => .MINUS,
            ';' => .SEMICOLON,
            ':' => .COLON,
            '*' => .STAR,
            '/' => .SLASH,
            '%' => .MODULO,
            '+' => if (self.match('=')) .PLUS_EQUAL else .PLUS,
            '>' => if (self.match('=')) .GREATER_EQUAL else .GREATER,
            '<' => if (self.match('=')) .LESS_EQUAL else .LESS,
            '=' => if (self.match('=')) .EQUAL_EQUAL else .EQUAL,
            '!' => if (self.match('=')) .BANG_EQUAL else .{ .@"error" = error.ExpectedBangEqual },
            '0'...'9' => try self.int(),
            QUOTE_CHAR => try self.string(false),
            'a'...'z', 'A'...'Z', '_' => |a| identifier: {
                if (a == 'f' and self.match(QUOTE_CHAR))
                    break :identifier try self.string(true);
                self.identifier();
                if (keywords.get(self.lexeme())) |keyword|
                    break :identifier keyword;
                break :identifier .{ .identifier = .{ .len = self.current() - self.start } };
            },
            else => {
                const err: Token = .{ .start = self.start, .type = .{ .@"error" = error.UnexpectedCharacter } };
                self.skipWord();
                break :scan err;
            },
        };
        break Token{ .start = self.start, .type = tag };
    } else |err| err;
}

pub fn pull(self: *Scanner, gpa: std.mem.Allocator, list: anytype) !void {
    return while (self.scanToken()) |token| {
        try list.append(gpa, token);
    } else |err| return switch (err) {
        error.EndOfStream => {},
        else => |e| e,
    };
}

// pub fn scan(source: []const u8, allocator: std.mem.Allocator) ScanError!std.ArrayList(Token) {
//     var tokens: std.ArrayList(Token) = .{};
//     const reader = std.Io.Reader.fixed(source);
//     var scanner = Scanner{ .reader = reader };
//     while (scanner.reader.peekByte()) {
//         if (scanner.scanToken()) |token| {
//             if (token) |t| {
//                 const next = try tokens.addOne(allocator);
//                 next.* = t;
//             }
//         } else |err| {
//             const log = try scanner.logs.addOne(allocator);
//             log.* = .{ .type = err, .line = scanner.line };
//         }
//     }
//     return tokens;
// }

pub fn scan(source: []const u8, gpa: std.mem.Allocator) ![]Token {
    const reader = std.Io.Reader.fixed(source);
    var scanner = Scanner{ .reader = reader };
    var tokens = std.ArrayList(Token).empty;
    errdefer tokens.deinit(gpa);
    scanner.pull(gpa, &tokens) catch |err| switch (err) {
        error.ExpectedEndOfLine => {},
        else => |e| return e,
    };
    return tokens.toOwnedSlice(gpa);
}

fn expect(source: []const u8, expected: []const Token) !void {
    const tokens = try scan(source, std.testing.allocator);
    defer std.testing.allocator.free(tokens);
    try std.testing.expectEqualDeep(expected, tokens);
}

fn expectError(source: []const u8, gpa: std.mem.Allocator, expected: anyerror, position: usize) !void {
    const reader = std.Io.Reader.fixed(source);
    var scanner = Scanner{ .reader = reader };
    var tokens = std.ArrayList(Token).empty;
    defer tokens.deinit(gpa);
    const err = scanner.pull(gpa, &tokens);
    try std.testing.expectError(expected, err);
    try std.testing.expectEqual(position, scanner.start);
}

test "+" {
    const source = "+\n";
    const expected = [_]Token{
        .{ .start = 0, .type = .PLUS },
        .{ .start = 1, .type = .NEWLINE },
    };
    try expect(source, &expected);
}

test "var1 = 'hello'" {
    const source = "var1 = 'hello'\n";
    const expected = [_]Token{
        .{ .start = 0, .type = .{ .identifier = .{ .len = 4 - 0 } } },
        .{ .start = 5, .type = .EQUAL },
        .{ .start = 7, .type = .{ .string = .{ .start = 8, .len = 5 } } },
        .{ .start = 14, .type = .NEWLINE },
    };
    try expect(source, &expected);
}

test "var2 = 102" {
    const source = "var2 = 102\n";
    const expected = [_]Token{
        .{ .start = 0, .type = .{ .identifier = .{ .len = 4 - 0 } } },
        .{ .start = 5, .type = .EQUAL },
        .{ .start = 7, .type = .{ .integer = .{ .len = 3, .value = 102 } } },
        .{ .start = 10, .type = .NEWLINE },
    };
    try expect(source, &expected);
}

test "var1 = [1, 2, 3]" {
    const source = "var1 = [1, 2, 3]\n";
    const expected = [_]Token{
        .{ .start = 0, .type = .{ .identifier = .{ .len = 4 - 0 } } },
        .{ .start = 5, .type = .EQUAL },
        .{ .start = 7, .type = .LEFT_BRACKET },
        .{ .start = 8, .type = .{ .integer = .{ .len = 1, .value = 1 } } },
        .{ .start = 9, .type = .COMMA },
        .{ .start = 11, .type = .{ .integer = .{ .len = 1, .value = 2 } } },
        .{ .start = 12, .type = .COMMA },
        .{ .start = 14, .type = .{ .integer = .{ .len = 1, .value = 3 } } },
        .{ .start = 15, .type = .RIGHT_BRACKET },
        .{ .start = 16, .type = .NEWLINE },
    };
    try expect(source, &expected);
}

test "var2 += [4]" {
    const source = "var2 += [4]\n";
    const expected = [_]Token{
        .{ .start = 0, .type = .{ .identifier = .{ .len = 4 - 0 } } },
        .{ .start = 5, .type = .PLUS_EQUAL },
        .{ .start = 8, .type = .LEFT_BRACKET },
        .{ .start = 9, .type = .{ .integer = .{ .len = 1, .value = 4 } } },
        .{ .start = 10, .type = .RIGHT_BRACKET },
        .{ .start = 11, .type = .NEWLINE },
    };
    try expect(source, &expected);
}

test "int_255 = 0xFF" {
    const source = "int_255 = 0xFF\n";
    const expected = [_]Token{
        .{ .start = 0, .type = .{ .identifier = .{ .len = 7 - 0 } } },
        .{ .start = 8, .type = .EQUAL },
        .{ .start = 10, .type = .{ .integer = .{ .len = 4, .value = 255 } } },
        .{ .start = 14, .type = .NEWLINE },
    };
    try expect(source, &expected);
}

test "int_493 = 0o755" {
    const source = "int_493 = 0o755\n";
    const expected = [_]Token{
        .{ .start = 0, .type = .{ .identifier = .{ .len = 7 - 0 } } },
        .{ .start = 8, .type = .EQUAL },
        .{ .start = 10, .type = .{ .integer = .{ .len = 5, .value = 493 } } },
        .{ .start = 15, .type = .NEWLINE },
    };
    try expect(source, &expected);
}

test "int_1365 = 0b10101010101" {
    const source = "int_1365 = 0b10101010101\n";
    const expected = [_]Token{
        .{ .start = 0, .type = .{ .identifier = .{ .len = 8 - 0 } } },
        .{ .start = 9, .type = .EQUAL },
        .{ .start = 11, .type = .{ .integer = .{ .len = 13, .value = 1365 } } },
        .{ .start = 24, .type = .NEWLINE },
    };
    try expect(source, &expected);
}

test "bool_var = true" {
    const source = "bool_var = true\n";
    const expected = [_]Token{
        .{ .start = 0, .type = .{ .identifier = .{ .len = 8 - 0 } } },
        .{ .start = 9, .type = .EQUAL },
        .{ .start = 11, .type = .TRUE },
        .{ .start = 15, .type = .NEWLINE },
    };
    try expect(source, &expected);
}

test "string_var = bool_var.to_string()" {
    const source = "string_var = bool_var.to_string()\n";
    const expected = [_]Token{
        .{ .start = 0, .type = .{ .identifier = .{ .len = 10 - 0 } } },
        .{ .start = 11, .type = .EQUAL },
        .{ .start = 13, .type = .{ .identifier = .{ .len = 21 - 13 } } },
        .{ .start = 21, .type = .DOT },
        .{ .start = 22, .type = .{ .identifier = .{ .len = 31 - 22 } } },
        .{ .start = 31, .type = .LEFT_PAREN },
        .{ .start = 32, .type = .RIGHT_PAREN },
        .{ .start = 33, .type = .NEWLINE },
    };
    try expect(source, &expected);
}

test "single_quote = 'contains a \' character'" {
    const source = "single_quote = 'contains a \\' character'\n";
    const expected = [_]Token{
        .{ .start = 0, .type = .{ .identifier = .{ .len = 12 - 0 } } },
        .{ .start = 13, .type = .EQUAL },
        .{ .start = 15, .type = .{ .string = .{ .start = 16, .len = 23 } } },
        .{ .start = 40, .type = .NEWLINE },
    };
    try expect(source, &expected);
}

test "end line comment" {
    const source = "joined = '/usr/share' / 'projectname'    # => /usr/share/projectname\n";
    const expected = [_]Token{
        .{ .start = 0, .type = .{ .identifier = .{ .len = 6 - 0 } } },
        .{ .start = 7, .type = .EQUAL },
        .{ .start = 9, .type = .{ .string = .{ .start = 10, .len = 10 } } },
        .{ .start = 22, .type = .SLASH },
        .{ .start = 24, .type = .{ .string = .{ .start = 25, .len = 11 } } },
        .{ .start = 68, .type = .NEWLINE },
    };
    try expect(source, &expected);
}

test "multiline string" {
    const source =
        \\multiline_string = '''#include <foo.h>
        \\int main (int argc, char ** argv) {
        \\  return FOO_SUCCESS;
        \\}'''
        \\
    ;
    const expected = [_]Token{
        .{ .start = 0, .type = .{ .identifier = .{ .len = 16 - 0 } } },
        .{ .start = 17, .type = .EQUAL },
        .{ .start = 19, .type = .{ .string = .{ .start = 22, .len = 98 - 22 } } },
        .{ .start = 101, .type = .NEWLINE },
    };
    try expect(source, &expected);
}

test "'3.6'.version_compare('>=3.6.0') == false" {
    const source = "'3.6'.version_compare('>=3.6.0') == false\n";
    const expected = [_]Token{
        .{ .start = 0, .type = .{ .string = .{ .start = 1, .len = 4 - 1 } } },
        .{ .start = 5, .type = .DOT },
        .{ .start = 6, .type = .{ .identifier = .{ .len = 21 - 6 } } },
        .{ .start = 21, .type = .LEFT_PAREN },
        .{ .start = 22, .type = .{ .string = .{ .start = 23, .len = 30 - 23 } } },
        .{ .start = 31, .type = .RIGHT_PAREN },
        .{ .start = 33, .type = .EQUAL_EQUAL },
        .{ .start = 36, .type = .FALSE },
        .{ .start = 41, .type = .NEWLINE },
    };
    try expect(source, &expected);
}

test "if elif else" {
    const source =
        \\if var1 == var2 # Evaluates to false
        \\  something_broke()
        \\elif var3 == var2
        \\  something_else_broke()
        \\else
        \\  everything_ok()
        \\endif
        \\
    ;
    const expected = [_]Token{
        .{ .start = 0, .type = .IF },
        .{ .start = 3, .type = .{ .identifier = .{ .len = 7 - 3 } } },
        .{ .start = 8, .type = .EQUAL_EQUAL },
        .{ .start = 11, .type = .{ .identifier = .{ .len = 15 - 11 } } },
        .{ .start = 36, .type = .NEWLINE },
        .{ .start = 39, .type = .{ .identifier = .{ .len = 54 - 39 } } },
        .{ .start = 54, .type = .LEFT_PAREN },
        .{ .start = 55, .type = .RIGHT_PAREN },
        .{ .start = 56, .type = .NEWLINE },
        .{ .start = 57, .type = .ELIF },
        .{ .start = 62, .type = .{ .identifier = .{ .len = 66 - 62 } } },
        .{ .start = 67, .type = .EQUAL_EQUAL },
        .{ .start = 70, .type = .{ .identifier = .{ .len = 74 - 70 } } },
        .{ .start = 74, .type = .NEWLINE },
        .{ .start = 77, .type = .{ .identifier = .{ .len = 97 - 77 } } },
        .{ .start = 97, .type = .LEFT_PAREN },
        .{ .start = 98, .type = .RIGHT_PAREN },
        .{ .start = 99, .type = .NEWLINE },
        .{ .start = 100, .type = .ELSE },
        .{ .start = 104, .type = .NEWLINE },
        .{ .start = 107, .type = .{ .identifier = .{ .len = 120 - 107 } } },
        .{ .start = 120, .type = .LEFT_PAREN },
        .{ .start = 121, .type = .RIGHT_PAREN },
        .{ .start = 122, .type = .NEWLINE },
        .{ .start = 123, .type = .ENDIF },
        .{ .start = 128, .type = .NEWLINE },
    };
    try expect(source, &expected);
}

test "foreach continue break endforeach" {
    const source =
        \\foreach i : items
        \\  if i == 'continue'
        \\    continue
        \\  elif i == 'break'
        \\    break
        \\  endif
        \\  result += i
        \\endforeach
        \\
    ;
    const expected = [_]Token{
        .{ .start = 0, .type = .FOREACH },
        .{ .start = 8, .type = .{ .identifier = .{ .len = 9 - 8 } } },
        .{ .start = 10, .type = .COLON },
        .{ .start = 12, .type = .{ .identifier = .{ .len = 17 - 12 } } },
        .{ .start = 17, .type = .NEWLINE },
        .{ .start = 20, .type = .IF },
        .{ .start = 23, .type = .{ .identifier = .{ .len = 24 - 23 } } },
        .{ .start = 25, .type = .EQUAL_EQUAL },
        .{ .start = 28, .type = .{ .string = .{ .start = 29, .len = 37 - 29 } } },
        .{ .start = 38, .type = .NEWLINE },
        .{ .start = 43, .type = .CONTINUE },
        .{ .start = 51, .type = .NEWLINE },
        .{ .start = 54, .type = .ELIF },
        .{ .start = 59, .type = .{ .identifier = .{ .len = 60 - 59 } } },
        .{ .start = 61, .type = .EQUAL_EQUAL },
        .{ .start = 64, .type = .{ .string = .{ .start = 65, .len = 70 - 65 } } },
        .{ .start = 71, .type = .NEWLINE },
        .{ .start = 76, .type = .BREAK },
        .{ .start = 81, .type = .NEWLINE },
        .{ .start = 84, .type = .ENDIF },
        .{ .start = 89, .type = .NEWLINE },
        .{ .start = 92, .type = .{ .identifier = .{ .len = 98 - 92 } } },
        .{ .start = 99, .type = .PLUS_EQUAL },
        .{ .start = 102, .type = .{ .identifier = .{ .len = 103 - 102 } } },
        .{ .start = 103, .type = .NEWLINE },
        .{ .start = 104, .type = .ENDFOREACH },
        .{ .start = 114, .type = .NEWLINE },
    };
    try expect(source, &expected);
}

test "Unterminated string" {
    const source =
        \\if a == 'This is
        \\an unterminated string
        \\endif
        \\
    ;
    try expectError(source, std.testing.allocator, error.UnterminatedString, 8);
}

// ==================== COMMON TESTS ====================

test "dictionnary literal" {
    const source = "{'foo': 42, 'bar': 'baz'}";
    const expected = [_]Token{
        .{ .start = 0, .type = .LEFT_BRACE },
        .{ .start = 1, .type = .{ .string = .{ .start = 2, .len = 3 } } },
        .{ .start = 6, .type = .COLON },
        .{ .start = 8, .type = .{ .integer = .{ .len = 2, .value = 42 } } },
        .{ .start = 10, .type = .COMMA },
        .{ .start = 12, .type = .{ .string = .{ .start = 13, .len = 3 } } },
        .{ .start = 17, .type = .COLON },
        .{ .start = 19, .type = .{ .string = .{ .start = 20, .len = 3 } } },
        .{ .start = 24, .type = .RIGHT_BRACE },
    };
    try expect(source, &expected);
}

test "positional arguments" {
    const source = "executable('progname', 'prog.c')";
    const tokens = [_]Token{
        .{ .start = 0, .type = .{ .identifier = .{ .len = 10 } } },
        .{ .start = 10, .type = .LEFT_PAREN },
        .{ .start = 11, .type = .{ .string = .{ .start = 12, .len = 20 - 12 } } },
        .{ .start = 21, .type = .COMMA },
        .{ .start = 23, .type = .{ .string = .{ .start = 24, .len = 30 - 24 } } },
        .{ .start = 31, .type = .RIGHT_PAREN },
    };
    try expect(source, &tokens);
}

test "keyword arguments" {
    const source =
        \\executable('progname',
        \\sources: 'prog.c',
        \\c_args: '-DFOO=1')
    ;
    const tokens = [_]Token{
        .{ .start = 0, .type = .{ .identifier = .{ .len = 10 } } },
        .{ .start = 10, .type = .LEFT_PAREN },
        .{ .start = 11, .type = .{ .string = .{ .start = 12, .len = 20 - 12 } } },
        .{ .start = 21, .type = .COMMA },
        .{ .start = 23, .type = .{ .identifier = .{ .len = 7 } } },
        .{ .start = 30, .type = .COLON },
        .{ .start = 32, .type = .{ .string = .{ .start = 33, .len = 39 - 33 } } },
        .{ .start = 40, .type = .COMMA },
        .{ .start = 42, .type = .{ .identifier = .{ .len = 6 } } },
        .{ .start = 48, .type = .COLON },
        .{ .start = 50, .type = .{ .string = .{ .start = 51, .len = 58 - 51 } } },
        .{ .start = 59, .type = .RIGHT_PAREN },
    };
    try expect(source, &tokens);
}

test "method call" {
    const source = "myobj.do_something('now')";
    const tokens = [_]Token{
        .{ .start = 0, .type = .{ .identifier = .{ .len = 5 } } },
        .{ .start = 5, .type = .DOT },
        .{ .start = 6, .type = .{ .identifier = .{ .len = 12 } } },
        .{ .start = 18, .type = .LEFT_PAREN },
        .{ .start = 19, .type = .{ .string = .{ .start = 20, .len = 23 - 20 } } },
        .{ .start = 24, .type = .RIGHT_PAREN },
    };
    try expect(source, &tokens);
}

test "assignment" {
    const source = "var1 = 'hello'";
    const tokens = [_]Token{
        .{ .start = 0, .type = .{ .identifier = .{ .len = 4 } } },
        .{ .start = 5, .type = .EQUAL },
        .{ .start = 7, .type = .{ .string = .{ .start = 8, .len = 13 - 8 } } },
    };
    try expect(source, &tokens);
}

test "if statement" {
    const source =
        \\var1 = 1
        \\var2 = 2
        \\if var1 == var2 # Evaluates to false
        \\  something_broke()
        \\elif var3 == var2
        \\  something_else_broke()
        \\else
        \\  everything_ok()
        \\endif
        \\
        \\opt = get_option('someoption')
        \\if opt != 'foo'
        \\  do_something()
        \\endif
    ;
    const tokens = [_]Token{
        .{ .start = 0, .type = .{ .identifier = .{ .len = 4 } } },
        .{ .start = 5, .type = .EQUAL },
        .{ .start = 7, .type = .{ .integer = .{ .len = 1, .value = 1 } } },
        .{ .start = 8, .type = .NEWLINE },
        .{ .start = 9, .type = .{ .identifier = .{ .len = 4 } } },
        .{ .start = 14, .type = .EQUAL },
        .{ .start = 16, .type = .{ .integer = .{ .len = 1, .value = 2 } } },
        .{ .start = 17, .type = .NEWLINE },
        .{ .start = 18, .type = .IF },
        .{ .start = 21, .type = .{ .identifier = .{ .len = 4 } } },
        .{ .start = 26, .type = .EQUAL_EQUAL },
        .{ .start = 29, .type = .{ .identifier = .{ .len = 4 } } },
        .{ .start = 54, .type = .NEWLINE },
        .{ .start = 57, .type = .{ .identifier = .{ .len = 15 } } },
        .{ .start = 72, .type = .LEFT_PAREN },
        .{ .start = 73, .type = .RIGHT_PAREN },
        .{ .start = 74, .type = .NEWLINE },
        .{ .start = 75, .type = .ELIF },
        .{ .start = 80, .type = .{ .identifier = .{ .len = 4 } } },
        .{ .start = 85, .type = .EQUAL_EQUAL },
        .{ .start = 88, .type = .{ .identifier = .{ .len = 4 } } },
        .{ .start = 92, .type = .NEWLINE },
        .{ .start = 95, .type = .{ .identifier = .{ .len = 20 } } },
        .{ .start = 115, .type = .LEFT_PAREN },
        .{ .start = 116, .type = .RIGHT_PAREN },
        .{ .start = 117, .type = .NEWLINE },
        .{ .start = 118, .type = .ELSE },
        .{ .start = 122, .type = .NEWLINE },
        .{ .start = 125, .type = .{ .identifier = .{ .len = 13 } } },
        .{ .start = 138, .type = .LEFT_PAREN },
        .{ .start = 139, .type = .RIGHT_PAREN },
        .{ .start = 140, .type = .NEWLINE },
        .{ .start = 141, .type = .ENDIF },
        .{ .start = 146, .type = .NEWLINE },
        .{ .start = 147, .type = .NEWLINE },
        .{ .start = 148, .type = .{ .identifier = .{ .len = 3 } } },
        .{ .start = 152, .type = .EQUAL },
        .{ .start = 154, .type = .{ .identifier = .{ .len = 10 } } },
        .{ .start = 164, .type = .LEFT_PAREN },
        .{ .start = 165, .type = .{ .string = .{ .start = 166, .len = 176 - 166 } } },
        .{ .start = 177, .type = .RIGHT_PAREN },
        .{ .start = 178, .type = .NEWLINE },
        .{ .start = 179, .type = .IF },
        .{ .start = 182, .type = .{ .identifier = .{ .len = 3 } } },
        .{ .start = 186, .type = .BANG_EQUAL },
        .{ .start = 189, .type = .{ .string = .{ .start = 190, .len = 193 - 190 } } },
        .{ .start = 194, .type = .NEWLINE },
        .{ .start = 197, .type = .{ .identifier = .{ .len = 12 } } },
        .{ .start = 209, .type = .LEFT_PAREN },
        .{ .start = 210, .type = .RIGHT_PAREN },
        .{ .start = 211, .type = .NEWLINE },
        .{ .start = 212, .type = .ENDIF },
    };
    try expect(source, &tokens);
}

test "Mutiline single quote" {
    const source =
        \\b = 'This is a
        \\single quote terminated
        \\string'
        \\test(1)
        \\
    ;
    const expected = [_]Token{
        .{ .start = 0, .type = .{ .identifier = .{ .len = 1 } } },
        .{ .start = 2, .type = .EQUAL },
        .{ .start = 4, .type = .{ .@"error" = error.NewlineInSimpleQuotes } },
        .{ .start = 46, .type = .NEWLINE },
        .{ .start = 47, .type = .{ .identifier = .{ .len = 4 } } },
        .{ .start = 51, .type = .LEFT_PAREN },
        .{ .start = 52, .type = .{ .integer = .{ .len = 1, .value = 1 } } },
        .{ .start = 53, .type = .RIGHT_PAREN },
        .{ .start = 54, .type = .NEWLINE },
    };
    try expect(source, &expected);
}
