const Token = @import("token.zig");

// const IntegerLiteral = u64;
//
// const StringLiteral = Token.StringToken;
//
// const BooleanLiteral = enum { TRUE, FALSE };

pub const IntegerLiteral = *const Token;

pub const StringLiteral = *const Token;

pub const BooleanLiteral = *const Token;

pub const ArrayLiteral = []Expression;

pub const DictionaryLiteral = []KeyValueItem;

pub const IdExpr = *const Token;

pub const Literal = union(enum) {
    integer: IntegerLiteral,
    string: StringLiteral,
    boolean: BooleanLiteral,
    array: ArrayLiteral,
    dictionary: DictionaryLiteral,
};

pub const PrimaryExpr = union(enum) {
    literal: Literal,
    expression: *Expression,
    id_expr: IdExpr,
};

pub const SubscriptExpr = struct {
    postfix_expr: *PostfixExpr,
    expression: *Expression,
};

pub const KeywordItem = struct {
    id: IdExpr,
    expression: *Expression,
};

pub const ArgumentList = struct {
    positional_arguments: []Expression,
    keyword_arguments: []KeywordItem,
};

pub const FunctionExpr = struct {
    id_expr: IdExpr,
    argument_list: ArgumentList,
};

pub const MethodExpr = struct {
    postfix_expr: *PostfixExpr,
    function_expr: FunctionExpr,
};

pub const PostfixExpr = union(enum) {
    primary_expr: PrimaryExpr,
    subscript_expr: SubscriptExpr,
    function_expr: FunctionExpr,
    method_expr: MethodExpr,
};

pub const UnaryOperator = enum {
    MINUS,
    NOT,
    pub fn from(token: Token) ?UnaryOperator {
        return switch (token.type) {
            .MINUS => .MINUS,
            .NOT => .NOT,
            else => null,
        };
    }
};

pub const UnaryExpr = struct {
    postfix_expr: PostfixExpr,
    unop: ?UnaryOperator,
};

pub const MultiplicativeOperator = enum {
    SLASH,
    MODULO,
    STAR,
    pub fn from(token: Token) ?MultiplicativeOperator {
        return switch (token.type) {
            .SLASH => .SLASH,
            .MODULO => .MODULO,
            .STAR => .STAR,
            else => null,
        };
    }
};

pub const MultiplicativeExpr = struct {
    unary_expr: []UnaryExpr,
    ops: []MultiplicativeOperator,
};

pub const AdditiveOperator = enum {
    MINUS,
    PLUS,
    pub fn from(token: Token) ?AdditiveOperator {
        return switch (token.type) {
            .MINUS => .MINUS,
            .PLUS => .PLUS,
            else => null,
        };
    }
};

pub const AdditiveExpression = struct {
    multiplicative_expr: []MultiplicativeExpr,
    ops: []AdditiveOperator,
};

pub const ComparisonOperator = enum {
    GREATER,
    GREATER_EQUAL,
    LESS,
    LESS_EQUAL,
    NOT_EQUAL,
    EQUAL_EQUAL,
    pub fn from(token: Token) ?ComparisonOperator {
        return switch (token.type) {
            .GREATER => .GREATER,
            .GREATER_EQUAL => .GREATER_EQUAL,
            .LESS => .LESS,
            .LESS_EQUAL => .LESS_EQUAL,
            .BANG_EQUAL => .NOT_EQUAL,
            .EQUAL_EQUAL => .EQUAL_EQUAL,
            else => null,
        };
    }
};

pub const ComparisonExpr = struct {
    lhs: AdditiveExpression,
    rhs: ?struct {
        op: ComparisonOperator,
        rhs: AdditiveExpression,
    },
};

pub const LogicalAndExpr = []ComparisonExpr;

pub const LogicalOrExpr = []LogicalAndExpr;

// pub const EqualityExpr = union(enum) {
//     relational_expr: RelationalExpr,
//     equality_expr: struct {
//         lhs: *EqualityExpr,
//         rhs: RelationalExpr,
//     },
// };
//
// pub const LogicalAndExpr = union(enum) {
//     equality_expr: EqualityExpr,
//     logical_and_expr: struct {
//         lhs: *LogicalAndExpr,
//         rhs: EqualityExpr,
//     },
// };
//
// pub const LogicalOrExpr = union(enum) {
//     logical_and_expr: LogicalAndExpr,
//     logical_or_expr: struct {
//         lhs: *LogicalOrExpr,
//         rhs: LogicalAndExpr,
//     },
// };

pub const Expression = union(enum) {
    logical_or_expr: LogicalOrExpr,
};

pub const KeyValueItem = [2]Expression;

pub const AssignmentOperator = enum {
    EQUAL,
    PLUS_EQUAL,
    pub fn from(token: Token) ?AssignmentOperator {
        return switch (token.type) {
            .EQUAL => .EQUAL,
            .PLUS_EQUAL => .PLUS_EQUAL,
            else => null,
        };
    }
};

pub const AssignmentStatement = struct {
    lhs: IdExpr,
    op: AssignmentOperator,
    rhs: Expression,
};

pub const SelectionItem = struct {
    condition: Expression,
    statements: []Statement,
};

pub const SelectionStatement = struct {
    conditions: []SelectionItem,
    @"else": []Statement,
};

pub const IterationStatement = struct {
    iterators: []IdExpr,
    iterable: IdExpr,
    statements: []Statement,
};

pub const Statement = union(enum) {
    expression_stmt: Expression,
    assignment_stmt: AssignmentStatement,
    selection_stmt: SelectionStatement,
    iteration_stmt: IterationStatement,
    CONTINUE,
    BREAK,
};
