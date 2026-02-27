const Token = @import("token.zig");
const AST = @import("ast.zig");
const std = @import("std");

const ParserError = error{
    EXPECTED_EOL,
    EXPECTED_ID,
    EXPECTED_COLON,
    EXPECTED_DOT,
    EXPECTED_IF,
    EXPECTED_FOREACH,
    EXPECTED_ENDIF,
    EXPECTED_COMMA_SEPARATED_LIST,
    EXPECTED_EXPRESSION,
    EXPECTED_POSTFIX_EXPRESSION,
    EXPECTED_OPENING_BRACKET,
    EXPECTED_CLOSING_BRACKET,
    EXPECTED_OPENING_BRACE,
    EXPECTED_CLOSING_BRACE,
    EXPECTED_OPENING_PAREN,
    EXPECTED_CLOSING_PAREN,
    UNEXPECTED_OPENING_PAREN,
    EXPECTED_ARRAY_LITERAL,
    EXPECTED_DICTIONARY_LITERAL,
    ASSIGNMENT_LHS_SHOULD_BE_AN_ID,
    UNEXPECTED_EOF,
    ErrorToken,
};

const ParsingError = ParserError || std.mem.Allocator.Error;

const ParserLog = struct {
    token: ?*const Token,
    err: ParserError,
};

tokens: []const Token,
start: usize = 0,
current: usize = 0,
allocator: std.mem.Allocator,
logs: std.ArrayList(ParserLog),

const Parser = @This();

pub fn init(tokens: []const Token, arena: *std.heap.ArenaAllocator) std.mem.Allocator.Error!Parser {
    return .{
        .tokens = tokens,
        .logs = std.ArrayList(ParserLog).empty,
        .allocator = arena.allocator(),
    };
}

pub fn deinit(self: *Parser) void {
    self.logs.deinit(self.allocator);
}

fn notify(self: *Parser, err: ParserError) void {
    const next = try self.logs.addOne(self.allocator);
    next.* = .{
        .err = err,
        .token = self.peek(),
    };
}

fn end(self: Parser) bool {
    return self.current >= self.tokens.len;
}

fn peek(self: *Parser) ?*const Token {
    return if (self.end()) null else &self.tokens[self.current];
}

fn peek_next(self: *Parser) ?*const Token {
    return if (self.current + 1 >= self.tokens.len) null else &self.tokens[self.current + 1];
}

fn match(self: *Parser, token: Token.Tag) bool {
    const current = self.peek() orelse return false;
    if (current.type == token) {
        _ = self.advance();
        return true;
    }
    return false;
}

fn skip_newlines(self: *Parser) void {
    while (!self.end() and self.tokens[self.current].type == .NEWLINE) {
        _ = self.advance();
    }
}

fn match_or(self: *Parser, matches: []const Token.Type) ?Token {
    const current = self.peek() orelse return null;
    return for (matches) |m| {
        if (current.type == m) {
            break self.advance();
        }
    } else null;
}

fn toss(self: *Parser, n: usize) void {
    self.current += n;
}

fn advance(self: *Parser) ?*const Token {
    const token = self.peek() orelse return null;
    self.toss(1);
    return token;
}

// Matches a list node of type node separated by the keyword sep
fn match_list(self: *Parser, node: type, sep: Token.Tag, item: fn (self: *Parser) ParsingError!node) ParsingError![]node {
    var list = std.ArrayList(node).empty;
    const first = try list.addOne(self.allocator);
    first.* = try item(self);
    while (self.match(sep)) {
        const next = try list.addOne(self.allocator);
        next.* = try item(self);
    }
    // Returns a copy of its backing storage after clearing the array
    return list.toOwnedSlice(self.allocator);
}

fn match_list_if(self: *Parser, comptime Node: type, comptime Operator: type, comptime item: fn (self: *Parser) ParsingError!Node, comptime operator: fn (token: Token) ?Operator) ParsingError!struct { []Node, []Operator } {
    var list = std.ArrayList(Node).empty;
    var list_op = std.ArrayList(Operator).empty;
    const first = try list.addOne(self.allocator);
    first.* = try item(self);
    while (self.peek()) |token| {
        // Continue while the operator is matched
        const op = operator(token.*) orelse break;
        self.toss(1);
        const next_op = try list_op.addOne(self.allocator);
        next_op.* = op;
        const next = try list.addOne(self.allocator);
        next.* = try item(self);
    }
    // Returns a copy of its backing storage after clearing the array
    return .{
        try list.toOwnedSlice(self.allocator),
        try list_op.toOwnedSlice(self.allocator),
    };
}

// Matches a list node of type node separated by tokens of type sep
fn match_list_by_type(self: *Parser, node: type, operator: type, sep: Token.Tag, item: fn (self: *Parser) ParsingError!node) ParsingError!struct { []node, []operator } {
    const list = std.ArrayList(node).empty;
    const list_op = std.ArrayList(operator).empty;
    const first = try list.addOne(self.allocator);
    first.* = try item(self);
    while (self.peek()) |token| {
        if (token.type != sep) break;
        const next_op = try list_op.addOne(self.allocator);
        next_op = self.advance();
        const next = try list.addOne(self.allocator);
        next.* = try item(self);
    }
    // Returns a copy of its backing storage after clearing the array
    return .{ list.toOwnedSlice(self.allocator), list_op.toOwnedSlice(self.allocator) };
}

fn key_value_item(self: *Parser) ParsingError!AST.KeyValueItem {
    const lhs = try self.expression();
    if (!self.match(.COLON))
        return error.EXPECTED_COMMA_SEPARATED_LIST;
    const rhs = try self.expression();
    return .{ lhs, rhs };
}

fn array_literal(self: *Parser) ParsingError!AST.ArrayLiteral {
    if (!self.match(.LEFT_BRACKET)) return error.EXPECTED_ARRAY_LITERAL;
    const list = try self.match_list(AST.Expression, .COMMA, expression);
    return if (self.match(.RIGHT_BRACKET)) list else error.EXPECTED_CLOSING_BRACKET;
}

fn dictionary_literal(self: *Parser) ParsingError!AST.DictionaryLiteral {
    if (!self.match(.LEFT_BRACE)) return error.EXPECTED_DICTIONARY_LITERAL;
    const items = try self.match_list(AST.KeyValueItem, .COMMA, key_value_item);
    if (!self.match(.RIGHT_BRACE)) return error.EXPECTED_CLOSING_BRACE;
    return items;
}

fn literal(self: *Parser) ParsingError!?AST.Literal {
    const token = self.peek() orelse return null;
    return switch (token.type) {
        .integer => .{ .integer = self.advance().? },
        .string => .{ .string = self.advance().? },
        .TRUE, .FALSE => .{ .boolean = self.advance().? },
        .LEFT_BRACKET => .{ .array = try self.array_literal() },
        .LEFT_BRACE => .{ .dictionary = try self.dictionary_literal() },
        .@"error" => return error.ErrorToken,
        else => null,
    };
}

fn id(self: *Parser) ?AST.IdExpr {
    const token = self.peek() orelse return null;
    return switch (token.type) {
        .identifier => self.advance(),
        else => null,
    };
}

/// primary_expression: literal | ("(" expression ")") | id_expression
fn primary_expression(self: *Parser) ParsingError!?AST.PrimaryExpr {
    if (try self.literal()) |_literal|
        return .{ .literal = _literal };
    if (self.match(.LEFT_PAREN)) {
        const expr = try self.allocator.create(AST.Expression);
        expr.* = try self.expression();
        return if (self.match(.RIGHT_PAREN)) .{ .expression = expr } else error.EXPECTED_CLOSING_PAREN;
    }
    if (self.id()) |_id|
        return .{ .id_expr = _id };
    return null;
}

fn subscript_expression(self: *Parser, base: AST.PostfixExpr) ParsingError!AST.SubscriptExpr {
    if (!self.match(.LEFT_BRACKET)) return error.EXPECTED_OPENING_BRACKET;
    const postfix = try self.allocator.create(AST.PostfixExpr);
    postfix.* = base;
    const expr = try self.allocator.create(AST.Expression);
    expr.* = try self.expression();
    if (!self.match(.RIGHT_BRACKET)) return error.EXPECTED_CLOSING_BRACKET;
    return AST.SubscriptExpr{
        .postfix_expr = postfix,
        .expression = expr,
    };
}

/// keyword_item: id_expression ":" expression
fn keyword_item(self: *Parser) ParsingError!AST.KeywordItem {
    const id_expr = self.id() orelse return error.EXPECTED_ID;
    if (!self.match(.COLON)) return error.EXPECTED_COLON;
    const expr = try self.allocator.create(AST.Expression);
    expr.* = try self.expression();
    return AST.KeywordItem{ .id = id_expr, .expression = expr };
}

/// argument_list: positional_arguments ["," keyword_arguments] | keyword_arguments
fn argument_list(self: *Parser) ParsingError!AST.ArgumentList {
    var positional_args = std.ArrayList(AST.Expression).empty;
    var keyword_args: []AST.KeywordItem = &.{};
    while (self.peek()) |token| {
        if (token.type == .RIGHT_PAREN) break;
        // Because of these lines the parser is LL(2)
        const next = self.peek_next() orelse return error.UNEXPECTED_EOF;
        // If the argument starts with an identifier and a colon we begin to parse keyword arguments
        if (token.type == .identifier and next.type == .COLON) {
            keyword_args = try self.match_list(AST.KeywordItem, .COMMA, keyword_item);
            break;
        }
        // Otherwise we parse a positional argument
        const arg = try positional_args.addOne(self.allocator);
        arg.* = try self.expression();
        // If the next character is not a comma it is the end of the argument list
        if (!self.match(.COMMA))
            break;
    } else return error.UNEXPECTED_EOF;
    return AST.ArgumentList{
        .positional_arguments = try positional_args.toOwnedSlice(self.allocator),
        .keyword_arguments = keyword_args,
    };
}

/// function_expression: id_expression "(" [argument_list] ")"
fn function_expression(self: *Parser, base: AST.IdExpr) ParsingError!AST.FunctionExpr {
    if (!self.match(.LEFT_PAREN)) return error.EXPECTED_OPENING_PAREN;
    const args = try self.argument_list();
    if (!self.match(.RIGHT_PAREN)) return error.EXPECTED_CLOSING_PAREN;
    return AST.FunctionExpr{
        .id_expr = base,
        .argument_list = args,
    };
}

/// method_expression: postfix_expression "." function_expression
fn method_expression(self: *Parser, base: AST.PostfixExpr) ParsingError!AST.MethodExpr {
    if (!self.match(.DOT)) return error.EXPECTED_DOT;
    const method_name = self.id() orelse return error.EXPECTED_ID;
    const function = try self.function_expression(method_name);
    const postfix = try self.allocator.create(AST.PostfixExpr);
    postfix.* = base;
    return AST.MethodExpr{ .postfix_expr = postfix, .function_expr = function };
}

/// postfix_expression: primary_expression | subscript_expression | function_expression | method_expression
fn postfix_expression(self: *Parser) ParsingError!AST.PostfixExpr {
    const primary = try self.primary_expression() orelse return error.EXPECTED_POSTFIX_EXPRESSION;
    var postfix = AST.PostfixExpr{ .primary_expr = primary };
    // If the postfix expression is followed by brackets it is wrapped in a subscript expression
    while (self.peek()) |token| {
        const outer: AST.PostfixExpr = switch (token.type) {
            .LEFT_PAREN => switch (primary) {
                .id_expr => |id_expr| .{ .function_expr = try self.function_expression(id_expr) },
                else => return error.UNEXPECTED_OPENING_PAREN,
            },
            .LEFT_BRACKET => .{ .subscript_expr = try self.subscript_expression(postfix) },
            .DOT => .{ .method_expr = try self.method_expression(postfix) },
            else => return postfix,
        };
        postfix = outer;
    }
    return postfix;
}

fn unary_expression(self: *Parser) ParsingError!AST.UnaryExpr {
    const token = self.peek() orelse return error.UNEXPECTED_EOF;
    const op = AST.UnaryOperator.from(token.*);
    if (op) |_| _ = self.advance();
    const postfix_expr = try self.postfix_expression();
    return .{
        .postfix_expr = postfix_expr,
        .unop = op,
    };
}

fn multiplicative_expression(self: *Parser) ParsingError!AST.MultiplicativeExpr {
    const nodes, const ops = try self.match_list_if(AST.UnaryExpr, AST.MultiplicativeOperator, unary_expression, AST.MultiplicativeOperator.from);
    return AST.MultiplicativeExpr{ .unary_expr = nodes, .ops = ops };
}

fn additive_expression(self: *Parser) ParsingError!AST.AdditiveExpression {
    const nodes, const ops = try self.match_list_if(AST.MultiplicativeExpr, AST.AdditiveOperator, multiplicative_expression, AST.AdditiveOperator.from);
    return AST.AdditiveExpression{ .multiplicative_expr = nodes, .ops = ops };
}

fn comparison_expression(self: *Parser) ParsingError!AST.ComparisonExpr {
    const lhs = try self.additive_expression();
    if (self.peek()) |token| {
        if (AST.ComparisonOperator.from(token.*)) |op| {
            _ = self.advance();
            const rhs = try self.additive_expression();
            return AST.ComparisonExpr{
                .lhs = lhs,
                .rhs = .{
                    .op = op,
                    .rhs = rhs,
                },
            };
        }
    }
    return AST.ComparisonExpr{ .lhs = lhs, .rhs = null };
}

fn logical_and_expression(self: *Parser) ParsingError!AST.LogicalAndExpr {
    return self.match_list(AST.ComparisonExpr, .AND, comparison_expression);
}

fn logical_or_expression(self: *Parser) ParsingError!AST.LogicalOrExpr {
    return self.match_list(AST.LogicalAndExpr, .OR, logical_and_expression);
}

fn expression(self: *Parser) ParsingError!AST.Expression {
    return .{ .logical_or_expr = try self.logical_or_expression() };
}

fn selection_item(self: *Parser) ParsingError!AST.SelectionItem {
    const condition = try self.expression();
    var statements = std.ArrayList(AST.Statement).empty;
    if (!self.match(.NEWLINE)) return error.EXPECTED_EOL;
    while (self.peek()) |token| {
        switch (token.type) {
            .ELIF, .ELSE, .ENDIF => break,
            else => {
                const stmt = try statements.addOne(self.allocator);
                stmt.* = try self.statement();
            },
        }
    } else return error.EXPECTED_ENDIF;
    return AST.SelectionItem{
        .condition = condition,
        .statements = try statements.toOwnedSlice(self.allocator),
    };
}

fn selection_statement(self: *Parser) ParsingError!AST.SelectionStatement {
    if (!self.match(.IF)) return error.EXPECTED_IF;
    var cases = std.ArrayList(AST.SelectionItem).empty;
    var else_case = std.ArrayList(AST.Statement).empty;
    while (true) {
        const case = try cases.addOne(self.allocator);
        case.* = try self.selection_item();
        switch (self.advance().?.type) {
            .ELIF => continue,
            .ENDIF => break,
            .ELSE => {
                if (!self.match(.NEWLINE))
                    return error.EXPECTED_EOL;
                while (!self.match(.ENDIF)) {
                    const stmt = try else_case.addOne(self.allocator);
                    stmt.* = try self.statement();
                }
                break;
            },
            else => unreachable,
        }
    }
    return AST.SelectionStatement{
        .conditions = try cases.toOwnedSlice(self.allocator),
        .@"else" = try else_case.toOwnedSlice(self.allocator),
    };
}

fn iteration_statement(self: *Parser) ParsingError!AST.IterationStatement {
    if (!self.match(.FOREACH)) return error.EXPECTED_FOREACH;
    const first_it = self.id() orelse return error.EXPECTED_ID;
    const second_it = if (self.match(.COMMA)) self.id() orelse return error.EXPECTED_ID else null;
    var iterators: []AST.IdExpr = undefined;
    if (second_it) |second| {
        iterators = try self.allocator.alloc(AST.IdExpr, 2);
        iterators[0] = first_it;
        iterators[1] = second;
    } else {
        iterators = try self.allocator.alloc(AST.IdExpr, 1);
        iterators[0] = first_it;
    }
    if (!self.match(.COLON)) return error.EXPECTED_COLON;
    const iterable: AST.IdExpr = self.id() orelse return error.EXPECTED_ID;
    if (!self.match(.NEWLINE)) return error.EXPECTED_EOL;
    var statements = std.ArrayList(AST.Statement).empty;
    while (!self.match(.ENDFOREACH)) {
        const stmt = try statements.addOne(self.allocator);
        stmt.* = try self.statement();
    }
    return AST.IterationStatement{
        .iterators = iterators,
        .iterable = iterable,
        .statements = try statements.toOwnedSlice(self.allocator),
    };
}

fn statement(self: *Parser) ParsingError!AST.Statement {
    while (self.match(.NEWLINE)) {}
    const first = self.peek() orelse return error.UNEXPECTED_EOF;
    var stmt: AST.Statement = undefined;
    switch (first.type) {
        .IF => stmt = .{ .selection_stmt = try self.selection_statement() },
        .CONTINUE => stmt = .CONTINUE,
        .BREAK => stmt = .BREAK,
        .FOREACH => stmt = .{ .iteration_stmt = try self.iteration_statement() },
        else => assignment: {
            const lhs = try self.expression();
            stmt = .{ .expression_stmt = lhs };
            if (self.peek()) |token| {
                if (token.type == .NEWLINE) break :assignment;
                const op = AST.AssignmentOperator.from(token.*) orelse return error.EXPECTED_EOL;
                if (lhs.logical_or_expr.len != 1 or lhs.logical_or_expr[0].len != 1 or lhs.logical_or_expr[0][0].rhs != null or lhs.logical_or_expr[0][0].lhs.multiplicative_expr.len != 1 or lhs.logical_or_expr[0][0].lhs.multiplicative_expr[0].unary_expr.len != 1 or lhs.logical_or_expr[0][0].lhs.multiplicative_expr[0].unary_expr[0].postfix_expr != .primary_expr or lhs.logical_or_expr[0][0].lhs.multiplicative_expr[0].unary_expr[0].postfix_expr.primary_expr != .id_expr) {
                    return error.ASSIGNMENT_LHS_SHOULD_BE_AN_ID;
                } else {
                    const identifier = lhs.logical_or_expr[0][0].lhs.multiplicative_expr[0].unary_expr[0].postfix_expr.primary_expr.id_expr;
                    _ = self.advance();
                    const rhs = try self.expression();
                    stmt = .{ .assignment_stmt = .{
                        .lhs = identifier,
                        .op = op,
                        .rhs = rhs,
                    } };
                }
            }
        },
    }
    return if (self.end() or self.match(.NEWLINE)) stmt else error.EXPECTED_EOL;
}

pub fn parse(self: *Parser) std.mem.Allocator.Error![]AST.Statement {
    var stmt_list = std.ArrayList(AST.Statement).empty;
    errdefer stmt_list.deinit(self.allocator);
    while (!self.end()) {
        if (self.statement()) |s| {
            const stmt = try stmt_list.addOne(self.allocator);
            stmt.* = s;
        } else |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                const log = try self.logs.addOne(self.allocator);
                log.* = .{ .err = @errorCast(err), .token = self.peek() };
                while (self.advance()) |token|
                    if (token.type == .NEWLINE) break;
            },
        }
    }

    return stmt_list.toOwnedSlice(self.allocator);
}

pub fn write_logs(self: Parser, source: []const u8) std.Io.Writer.Error!void {
    var stderr_buf: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writerStreaming(&stderr_buf);
    const stderr = &stderr_writer.interface;
    for (self.logs.items) |l| {
        try format_log(l, stderr, source);
    }
}

pub fn format_log(log: ParserLog, writer: *std.Io.Writer, source: []const u8) std.Io.Writer.Error!void {
    const message = switch (log.err) {
        error.EXPECTED_POSTFIX_EXPRESSION => "Expected postfix expression",
        else => unreachable,
    };
    if (log.token) |token| {
        const location = token.location(source);
        try writer.print("ERROR on line {} at column {}: {s}\n", .{ location.row, location.col, message });
    } else {
        try writer.print("ERROR: {s}\n", .{message});
    }
}

const Scanner = @import("scanner.zig");

test "parser.match" {
    const tokens = [_]Token{
        .{ .start = 0, .type = .GREATER_EQUAL },
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = try Parser.init(&tokens, &arena);
    defer parser.deinit();
    try std.testing.expect(!parser.end());
    try std.testing.expectEqualDeep(&tokens[0], parser.peek());
    if (!parser.match(.GREATER_EQUAL)) return error.TEST_FAILED;
}

// ==================== COMMON TESTS ====================

test "dictionary literal" {
    const source = "{'foo': 42, 'bar': 'baz'}";
    const tokens = try Scanner.scan(source, std.testing.allocator);
    defer std.testing.allocator.free(tokens);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = try Parser.init(tokens, &arena);
    defer parser.deinit();
    const result = try parser.literal() orelse return error.TEST_FAILED;
    try std.testing.expect(result == .dictionary);
    try std.testing.expect(result.dictionary.len == 2);
    try std.testing.expect(result.dictionary[0][0] == .logical_or_expr);
    const r1: *AST.ComparisonExpr = &result.dictionary[0][0].logical_or_expr[0][0];
    try std.testing.expectEqual(null, r1.rhs);
    try std.testing.expectEqual(1, r1.lhs.multiplicative_expr.len);
    try std.testing.expectEqual(0, r1.lhs.ops.len);
    try std.testing.expectEqual(1, r1.lhs.multiplicative_expr[0].unary_expr.len);
    try std.testing.expectEqual(0, r1.lhs.multiplicative_expr[0].ops.len);
    try std.testing.expectEqual(null, r1.lhs.multiplicative_expr[0].unary_expr[0].unop);
    try std.testing.expect(r1.lhs.multiplicative_expr[0].unary_expr[0].postfix_expr == .primary_expr);
    try std.testing.expect(r1.lhs.multiplicative_expr[0].unary_expr[0].postfix_expr.primary_expr == .literal);
    try std.testing.expect(r1.lhs.multiplicative_expr[0].unary_expr[0].postfix_expr.primary_expr.literal == .string);
    try std.testing.expect(result.dictionary[0][1] == .logical_or_expr);
    try std.testing.expect(result.dictionary[1][0] == .logical_or_expr);
    try std.testing.expect(result.dictionary[1][1] == .logical_or_expr);
}

test "positional arguments" {
    const source = "executable('progname', 'prog.c')";
    const tokens = try Scanner.scan(source, std.testing.allocator);
    defer std.testing.allocator.free(tokens);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = try Parser.init(tokens, &arena);
    defer parser.deinit();
    const result = try parser.postfix_expression();
    try std.testing.expect(result == .function_expr);
}

test "keyword arguments" {
    const source =
        \\executable('progname',
        \\sources: 'prog.c',
        \\c_args: '-DFOO=1')
    ;
    const tokens = try Scanner.scan(source, std.testing.allocator);
    defer std.testing.allocator.free(tokens);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = try Parser.init(tokens, &arena);
    defer parser.deinit();
    const result = try parser.postfix_expression();
    try std.testing.expect(result == .function_expr);
    try std.testing.expectEqualStrings("executable", result.function_expr.id_expr.lexeme(source));
    try std.testing.expectEqual(1, result.function_expr.argument_list.positional_arguments.len);
    try std.testing.expectEqual(2, result.function_expr.argument_list.keyword_arguments.len);
    try std.testing.expectEqualStrings("sources", result.function_expr.argument_list.keyword_arguments[0].id.lexeme(source));
    try std.testing.expectEqualStrings("c_args", result.function_expr.argument_list.keyword_arguments[1].id.lexeme(source));
}

test "method call" {
    const source = "myobj.do_something('now')";
    const tokens = try Scanner.scan(source, std.testing.allocator);
    defer std.testing.allocator.free(tokens);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = try Parser.init(tokens, &arena);
    defer parser.deinit();
    const result = try parser.postfix_expression();
    try std.testing.expect(result == .method_expr);
    try std.testing.expect(result.method_expr.postfix_expr.* == .primary_expr);
    try std.testing.expect(result.method_expr.postfix_expr.primary_expr == .id_expr);
    try std.testing.expectEqualStrings("myobj", result.method_expr.postfix_expr.primary_expr.id_expr.lexeme(source));
    try std.testing.expectEqualStrings("do_something", result.method_expr.function_expr.id_expr.lexeme(source));
    try std.testing.expectEqual(1, result.method_expr.function_expr.argument_list.positional_arguments.len);
}

test "assignment" {
    const source = "var1 = 'hello'";
    const tokens = try Scanner.scan(source, std.testing.allocator);
    defer std.testing.allocator.free(tokens);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = try Parser.init(tokens, &arena);
    defer parser.deinit();
    const result = try parser.statement();
    try std.testing.expect(result == .assignment_stmt);
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
    const tokens = try Scanner.scan(source, std.testing.allocator);
    defer std.testing.allocator.free(tokens);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = try Parser.init(tokens, &arena);
    defer parser.deinit();
    const result = try parser.parse();
    try parser.write_logs(source);
    try std.testing.expectEqual(5, result.len);
}

test "Mutiline single quote" {
    const source =
        \\b = 'This is a
        \\single quote terminated
        \\string'
        \\test(1)
        \\
    ;
    const tokens = try Scanner.scan(source, std.testing.allocator);
    defer std.testing.allocator.free(tokens);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = try Parser.init(tokens, &arena);
    defer parser.deinit();
    const result = try parser.parse();
    try std.testing.expectEqual(1, result.len);
    try std.testing.expect(result[0] == .expression_stmt);
    try std.testing.expectEqual(1, parser.logs.items.len);
    try std.testing.expectEqual(error.ErrorToken, parser.logs.items[0].err);
    try std.testing.expect(parser.logs.items[0].token != null);
    try std.testing.expect(parser.logs.items[0].token.?.type == .@"error");
    try std.testing.expect(parser.logs.items[0].token.?.type.@"error" == error.NewlineInSimpleQuotes);
}
