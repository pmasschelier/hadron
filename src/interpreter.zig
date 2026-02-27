const std = @import("std");
const AST = @import("parser/ast.zig");

const RuntimeError = error{
    NO_FUNCTION_DECLARATION,
    UNKNOWN_FUNCTION,
    UNKNOWN_KEY,
    OPERAND_MUST_BE_BOOLEAN,
    OPERAND_TYPE_NOT_SUPPORTED,
    UNDECLARED_VARIABLE,
    MISMATCHED_TYPES,
    EXPECTED_BOOLEAN,
    EXPECTED_STRING_AS_KEY,
    EXPECTED_INTEGER_AS_INDEX,
    EXPECTED_ITERABLE,
    EXPECTED_ONE_ITERATOR,
    EXPECTED_TWO_ITERATORS,
    INVALID_SUBSCRIPT_OPERAND,
    INTERNAL_ERROR_BOOLEAN_IS_NEITHER_TRUE_OR_FALSE,
    INTERNAL_ERROR_INTEGER_LITERAL_IS_NOT_AN_INTEGER_TOKEN,
    INTERNAL_ERROR_STRING_LITERAL_IS_NOT_A_STRING_TOKEN,
    DICT_KEY_SHOULD_BE_A_STRING,
    INDEX_OUT_OF_BOUNDS,
    UNEXPECTED_NUMBER_OF_ARGUMENTS,
    UNEXPECTED_ARGUMENT_TYPE,
    FUNCTION_CALL_RETURNED_AN_ERROR,
    TODO,
} || std.mem.Allocator.Error;

fn DeclsEnum(comptime T: type, kind: std.meta.Tag(std.builtin.Type)) type {
    // Collect method names
    comptime var fields: []const std.builtin.Type.EnumField = &.{};
    comptime var i: usize = 0;

    inline for (@typeInfo(T).@"struct".decls) |decl| {
        if (@typeInfo(@TypeOf(@field(T, decl.name))) == kind) {
            fields = fields ++ &[_]std.builtin.Type.EnumField{.{
                .name = decl.name,
                .value = i,
            }};
            i += 1;
        }
    }

    return @Type(.{
        .@"enum" = .{
            .tag_type = u32,
            .fields = fields,
            .decls = &.{},
            .is_exhaustive = true,
        },
    });
}

pub fn Runtime(comptime Environment: type) type {
    return struct {
        const Self = @This();
        const CustomTypes = DeclsEnum(Environment, .@"struct");

        fn MaybeTemp(comptime T: type) type {
            return struct {
                temp: bool = false,
                value: T,
            };
        }

        const Value = union(enum) {
            Void,
            integer: i64,
            string: MaybeTemp([]const u8),
            boolean: bool,
            array: MaybeTemp([]Value),
            dictionnary: MaybeTemp(std.StringHashMapUnmanaged(Value)),
            custom: *anyopaque,

            fn from(value: anytype, allocator: std.mem.Allocator) Value {
                const Type = @TypeOf(value);
                return switch (@typeInfo(Type)) {
                    .void => .Void,
                    .bool => .{ .boolean = value },
                    .int => |integer| if (integer.bits > 64 or integer.signedness == .unsigned) @compileError("Unsupported integer type " ++ @typeName(Type)) else .{ .integer = value },
                    .array => |array| switch (@typeInfo(array.child)) {
                        .int => |integer| if (integer.bits == 8 and integer.signedness == .unsigned)
                            Value{ .string = try allocator.dupe(u8, value) }
                        else
                            @compileError("Unsupported array of " ++ @typeName(array.child)),
                    },
                    else => @compileError("Unsupported type " ++ @typeName(Type)),
                };
            }

            fn to(self: Value, Result: type) ?Result {
                return switch (self) {
                    .Void => if (Result == void) void else null,
                    .integer => |integer| if (Result == i64) integer else null,
                    .string => |string| if (Result == []const u8) string.value else null,
                    .boolean => |boolean| if (Result == bool) boolean else null,
                    else => null,
                };
            }

            fn drop(self: *Value, allocator: std.mem.Allocator) void {
                switch (self.*) {
                    .string => |value| if (value.temp) self.deinit(allocator),
                    .array => |value| if (value.temp) self.deinit(allocator),
                    .dictionnary => |value| if (value.temp) self.deinit(allocator),
                    else => {},
                }
            }

            fn deinit(self: *Value, allocator: std.mem.Allocator) void {
                switch (self.*) {
                    .string => |str| allocator.free(str.value),
                    .array => |array| {
                        for (array.value) |*e| e.drop(allocator);
                        allocator.free(array.value);
                    },
                    .dictionnary => |*dict| {
                        var it = dict.value.iterator();
                        while (it.next()) |item|
                            item.value_ptr.drop(allocator);
                        dict.value.deinit(allocator);
                    },
                    else => {},
                }
            }
        };

        allocator: std.mem.Allocator,
        variables: std.StringHashMapUnmanaged(Value),
        source: []const u8,
        env: *Environment,

        pub fn init(allocator: std.mem.Allocator, source: []const u8, env: *Environment) Self {
            return .{
                .allocator = allocator,
                .variables = std.StringHashMapUnmanaged(Value).empty,
                .source = source,
                .env = env,
            };
        }

        pub fn deinit(self: *Self) void {
            var it = self.variables.iterator();
            while (it.next()) |e| {
                e.value_ptr.deinit(self.allocator);
            }
            self.variables.deinit(self.allocator);
        }

        // fn expect(expected: std.meta.Tag(Value), value: Value, msg: ?[]const u8) void {}

        // fn ValueStruct(comptime Type: type) type {
        //     const typeinfo = @typeInfo(Type).@"struct";
        //     const fields = typeinfo.fields;
        //     const value_fields: [fields.len]std.builtin.Type.StructFields = undefined;
        //     @memcpy(value_fields, fields);
        //     for (value_fields) |*field| {
        //         field.type = Value;
        //     }
        //     return @Type(.{ .@"struct" = .{
        //         .layout = typeinfo.layout,
        //         .backing_integer = typeinfo.backing_integer,
        //         .fields = value_fields,
        //         .decls = &.{},
        //         .is_tuple = typeinfo.is_tuple,
        //     } });
        // }

        fn run_argument_list(self: Self, args: AST.ArgumentList) RuntimeError![]Value {
            const values = try self.allocator.alloc(Value, args.positional_arguments.len);
            for (args.positional_arguments, values) |arg, *val| {
                val.* = try self.run_expression(arg);
            }
            return values;
        }

        fn run_function(self: Self, name: []const u8, args: AST.ArgumentList) RuntimeError!Value {
            const FunctionId = DeclsEnum(Environment, .@"fn");
            if (@typeInfo(FunctionId).@"enum".fields.len == 0) return error.NO_FUNCTION_DECLARATION;
            // Get the tag corresponding to the function named "name" in Environment
            // Note that for more than 100 function (zig 0.15.2) stringToEnum will compare name with each enum field name
            // otherwise it will use a StaticHashMap
            const id = std.meta.stringToEnum(FunctionId, name) orelse return error.UNKNOWN_FUNCTION;
            switch (id) {
                inline else => |tag| {
                    // Get the function and function type from the tag
                    const fn_ref = @field(Environment, @tagName(tag));
                    const FnType = @TypeOf(fn_ref);
                    const typeinfo = @typeInfo(FnType).@"fn";
                    const ArgType = std.meta.ArgsTuple(FnType);
                    const RetType = typeinfo.return_type.?;
                    var passed_args: ArgType = undefined;
                    // Check argument count
                    comptime var param_start = 0;
                    if (typeinfo.params.len != 0 and typeinfo.params[0].type == *Environment) {
                        passed_args[param_start] = self.env;
                        param_start += 1;
                    }
                    if (typeinfo.params.len != param_start + args.positional_arguments.len)
                        return error.UNEXPECTED_NUMBER_OF_ARGUMENTS;
                    const arg_values = try self.run_argument_list(args);
                    defer {
                        for (arg_values) |*value| value.drop(self.allocator);
                        self.allocator.free(arg_values);
                    }
                    inline for (typeinfo.params[param_start..], arg_values, param_start..) |param, *arg, i| {
                        passed_args[i] = arg.to(param.type.?) orelse return error.UNEXPECTED_ARGUMENT_TYPE;
                    }
                    const retval = @call(.auto, fn_ref, passed_args);
                    const value = switch (@typeInfo(RetType)) {
                        .error_union => retval catch return error.FUNCTION_CALL_RETURNED_AN_ERROR,
                        else => retval,
                    };
                    return Value.from(value, self.allocator);
                },
            }
        }

        fn run_literal(self: Self, literal: AST.Literal) RuntimeError!Value {
            return switch (literal) {
                .boolean => |token| switch (token.type) {
                    .TRUE => Value{ .boolean = true },
                    .FALSE => Value{ .boolean = false },
                    else => return error.INTERNAL_ERROR_BOOLEAN_IS_NEITHER_TRUE_OR_FALSE,
                },
                .integer => |token| switch (token.type) {
                    .integer => |integer| Value{ .integer = integer.value },
                    else => return error.INTERNAL_ERROR_INTEGER_LITERAL_IS_NOT_AN_INTEGER_TOKEN,
                },
                .string => |token| switch (token.type) {
                    .string => |string| copy: {
                        const clone = try self.allocator.dupe(u8, string);
                        break :copy Value{ .string = .{ .temp = true, .value = clone } };
                    },
                    else => return error.INTERNAL_ERROR_STRING_LITERAL_IS_NOT_A_STRING_TOKEN,
                },
                .array => |exprs| array: {
                    const results = try self.allocator.alloc(Value, exprs.len);
                    errdefer self.allocator.free(results);
                    for (exprs, results) |e, *r| {
                        r.* = try self.run_expression(e);
                    }
                    break :array Value{ .array = .{ .temp = true, .value = results } };
                },
                .dictionary => |dict| dict: {
                    var hashmap = std.StringHashMapUnmanaged(Value).empty;
                    errdefer hashmap.deinit(self.allocator);
                    for (dict) |item| {
                        const key = try self.run_expression(item[0]);
                        const value = try self.run_expression(item[1]);
                        switch (key) {
                            .string => |str| {
                                try hashmap.put(self.allocator, str.value, value);
                                if (str.temp) self.allocator.free(str.value);
                            },
                            else => return error.DICT_KEY_SHOULD_BE_A_STRING,
                        }
                    }
                    break :dict Value{
                        .dictionnary = .{
                            .temp = true,
                            .value = hashmap,
                        },
                    };
                },
            };
        }

        fn run_id(self: Self, id: AST.IdExpr) RuntimeError!Value {
            return self.variables.get(id.lexeme(self.source)) orelse error.UNDECLARED_VARIABLE;
        }

        fn run_assignment(self: *Self, assignment: AST.AssignmentStatement) RuntimeError!void {
            const name = assignment.lhs.lexeme(self.source);
            var value = try self.run_expression(assignment.rhs);
            switch (assignment.op) {
                .PLUS_EQUAL => {
                    const old = self.variables.get(name) orelse return error.UNDECLARED_VARIABLE;
                    if (std.meta.activeTag(old) != std.meta.activeTag(value))
                        return error.MISMATCHED_TYPES;
                    const new = switch (old) {
                        .integer => |integer| Value{ .integer = integer + value.integer },
                        .string => |string| concat: {
                            const concat = try std.mem.concat(self.allocator, u8, &.{ string.value, value.string.value });
                            value.drop(self.allocator);
                            self.allocator.free(string.value);
                            break :concat Value{ .string = .{ .value = concat, .temp = false } };
                        },
                        else => return error.TODO,
                    };
                    try self.variables.put(self.allocator, name, new);
                },
                .EQUAL => {
                    var previous = self.variables.get(name);
                    if (previous) |*prev|
                        prev.deinit(self.allocator);
                    switch (value) {
                        .string => |string| try self.variables.put(self.allocator, name, .{
                            .string = .{
                                .temp = false,
                                .value = string.value,
                            },
                        }),
                        .array => |array| try self.variables.put(self.allocator, name, .{
                            .array = .{
                                .temp = false,
                                .value = array.value,
                            },
                        }),
                        .dictionnary => |dict| try self.variables.put(self.allocator, name, .{
                            .dictionnary = .{
                                .temp = false,
                                .value = dict.value,
                            },
                        }),
                        else => try self.variables.put(self.allocator, name, value),
                    }
                },
            }
        }

        fn run_primary(self: Self, expression: AST.PrimaryExpr) RuntimeError!Value {
            return switch (expression) {
                .literal => |literal| self.run_literal(literal),
                .id_expr => |id| self.run_id(id),
                .expression => |e| self.run_expression(e.*),
            };
        }

        fn run_subscript(self: Self, expression: AST.SubscriptExpr) RuntimeError!Value {
            const e1 = try self.run_postfix(expression.postfix_expr.*);
            const e2 = try self.run_expression(expression.expression.*);
            return switch (e1) {
                .array => |array| switch (e2) {
                    .integer => |index| if (index >= 0 and index < array.value.len) array.value[@intCast(index)] else error.INDEX_OUT_OF_BOUNDS,
                    else => error.EXPECTED_INTEGER_AS_INDEX,
                },
                .dictionnary => |dict| switch (e2) {
                    .string => |key| if (dict.value.get(key.value)) |value| value else error.UNKNOWN_KEY,
                    else => error.EXPECTED_STRING_AS_KEY,
                },
                else => error.INVALID_SUBSCRIPT_OPERAND,
            };
        }

        fn run_postfix(self: Self, expression: AST.PostfixExpr) RuntimeError!Value {
            return switch (expression) {
                .primary_expr => |primary| self.run_primary(primary),
                .subscript_expr => |subscript| self.run_subscript(subscript),
                .function_expr => |call| self.run_function(call.id_expr.lexeme(self.source), call.argument_list),
                else => return error.TODO,
            };
        }

        fn run_unop(self: Self, expression: AST.UnaryExpr) RuntimeError!Value {
            const postfix = try self.run_postfix(expression.postfix_expr);
            return if (expression.unop) |unop|
                switch (unop) {
                    .MINUS => switch (postfix) {
                        .integer => |integer| Value{ .integer = -integer },
                        else => error.OPERAND_TYPE_NOT_SUPPORTED,
                    },
                    .NOT => switch (postfix) {
                        .boolean => |boolean| Value{ .boolean = !boolean },
                        else => error.OPERAND_TYPE_NOT_SUPPORTED,
                    },
                }
            else
                postfix;
        }

        fn run_multiplication(self: Self, expression: AST.MultiplicativeExpr) RuntimeError!Value {
            if (expression.unary_expr.len == 0) unreachable;
            var lhs_value = try self.run_unop(expression.unary_expr[0]);
            switch (lhs_value) {
                .integer => |*first| {
                    for (expression.unary_expr[1..], expression.ops) |e, op| {
                        const rhs_value = try self.run_unop(e);
                        switch (rhs_value) {
                            .integer => |value| switch (op) {
                                .STAR => first.* *= value,
                                .SLASH => first.* = @divTrunc(first.*, value),
                                .MODULO => first.* = @mod(first.*, value),
                            },
                            else => return error.MISMATCHED_TYPES,
                        }
                    }
                },
                else => if (expression.unary_expr.len != 1) return error.OPERAND_TYPE_NOT_SUPPORTED,
            }
            return lhs_value;
        }

        fn run_add_sub(self: Self, expression: AST.AdditiveExpression) RuntimeError!Value {
            if (expression.multiplicative_expr.len == 0) unreachable;
            var lhs_value = try self.run_multiplication(expression.multiplicative_expr[0]);
            if (expression.multiplicative_expr.len == 1) return lhs_value;
            return switch (lhs_value) {
                .integer => |*first| integer: {
                    for (expression.multiplicative_expr[1..], expression.ops) |e, op| {
                        const rhs_value = try self.run_multiplication(e);
                        switch (rhs_value) {
                            .integer => |integer| switch (op) {
                                .PLUS => first.* += integer,
                                .MINUS => first.* -= integer,
                            },
                            else => return error.MISMATCHED_TYPES,
                        }
                    }
                    break :integer lhs_value;
                },
                .string => |first| string: {
                    const slices = try self.allocator.alloc([]const u8, expression.multiplicative_expr.len);
                    defer self.allocator.free(slices);
                    const temps = try self.allocator.alloc(bool, expression.multiplicative_expr.len);
                    defer self.allocator.free(temps);
                    slices[0] = first.value;
                    temps[0] = first.temp;
                    for (expression.multiplicative_expr[1..], expression.ops, 1..) |e, op, i| {
                        if (op != .PLUS) return error.OPERAND_TYPE_NOT_SUPPORTED;
                        const rhs_value = try self.run_multiplication(e);
                        switch (rhs_value) {
                            .string => |string| {
                                slices[i] = string.value;
                                temps[i] = string.temp;
                            },
                            else => return error.MISMATCHED_TYPES,
                        }
                    }
                    const result = try std.mem.concat(self.allocator, u8, slices);
                    for (slices, temps) |s, t| if (t) self.allocator.free(s);
                    break :string Value{ .string = .{ .temp = true, .value = result } };
                },
                else => error.OPERAND_TYPE_NOT_SUPPORTED,
            };
        }

        fn run_comparison(self: Self, expression: AST.ComparisonExpr) RuntimeError!Value {
            const lhs_value = try self.run_add_sub(expression.lhs);
            if (expression.rhs) |rhs| {
                const rhs_value = try self.run_add_sub(rhs.rhs);
                if (std.meta.activeTag(lhs_value) != std.meta.activeTag(rhs_value))
                    return error.MISMATCHED_TYPES;
                const value: bool = switch (lhs_value) {
                    .integer => |integer| switch (rhs.op) {
                        .GREATER => integer > rhs_value.integer,
                        .GREATER_EQUAL => integer >= rhs_value.integer,
                        .LESS => integer < rhs_value.integer,
                        .LESS_EQUAL => integer <= rhs_value.integer,
                        .EQUAL_EQUAL => integer == rhs_value.integer,
                        .NOT_EQUAL => integer != rhs_value.integer,
                    },
                    .string => |string| strcmp: {
                        const order = std.mem.order(u8, string.value, rhs_value.string.value);
                        if (string.temp) self.allocator.free(string.value);
                        if (rhs_value.string.temp) self.allocator.free(rhs_value.string.value);
                        break :strcmp switch (rhs.op) {
                            .GREATER => order == .gt,
                            .GREATER_EQUAL => order != .lt,
                            .LESS => order == .lt,
                            .LESS_EQUAL => order != .gt,
                            .EQUAL_EQUAL => order == .eq,
                            .NOT_EQUAL => order != .eq,
                        };
                    },
                    else => return error.OPERAND_TYPE_NOT_SUPPORTED,
                };
                return Value{ .boolean = value };
            } else return lhs_value;
        }

        fn run_logical_and(self: Self, expression: AST.LogicalAndExpr) RuntimeError!Value {
            if (expression.len == 0) {
                unreachable;
            } else if (expression.len == 1) {
                return self.run_comparison(expression[0]);
            }
            const value: bool = for (expression) |e| {
                const result = try self.run_comparison(e);
                switch (result) {
                    .boolean => |value| if (!value) break false,
                    else => return error.OPERAND_MUST_BE_BOOLEAN,
                }
            } else true;
            return Value{ .boolean = value };
        }

        fn run_logical_or(self: Self, expression: AST.LogicalOrExpr) RuntimeError!Value {
            if (expression.len == 0) {
                unreachable;
            } else if (expression.len == 1) {
                return self.run_logical_and(expression[0]);
            }
            const value: bool = for (expression) |e| {
                const result = try self.run_logical_and(e);
                switch (result) {
                    .boolean => |value| if (value) break true,
                    else => return error.OPERAND_MUST_BE_BOOLEAN,
                }
            } else false;
            return Value{ .boolean = value };
        }

        fn run_expression(self: Self, expression: AST.Expression) RuntimeError!Value {
            return self.run_logical_or(expression.logical_or_expr);
        }

        fn run_selection(self: *Self, statement: AST.SelectionStatement) RuntimeError!void {
            for (statement.conditions) |condition| {
                const result = try self.run_expression(condition.condition);
                if (result != .boolean) return error.EXPECTED_BOOLEAN;
                if (result.boolean) return self.run(condition.statements);
            }
            return self.run(statement.@"else");
        }

        fn run_iteration(self: *Self, iteration: AST.IterationStatement) RuntimeError!void {
            const iterable = self.variables.get(iteration.iterable.lexeme(self.source)) orelse return error.UNDECLARED_VARIABLE;
            switch (iterable) {
                .array => |array| {
                    if (iteration.iterators.len != 1) return error.EXPECTED_ONE_ITERATOR;
                    const iterator = iteration.iterators[0].lexeme(self.source);
                    for (array.value) |value| {
                        try self.variables.put(self.allocator, iterator, value);
                        try self.run(iteration.statements);
                    }
                },
                .dictionnary => |dict| {
                    if (iteration.iterators.len != 2) return error.EXPECTED_TWO_ITERATORS;
                    const key = iteration.iterators[0].lexeme(self.source);
                    const value = iteration.iterators[1].lexeme(self.source);
                    var iterator = dict.value.iterator();
                    while (iterator.next()) |*entry| {
                        try self.variables.put(self.allocator, key, Value{ .string = .{ .value = entry.key_ptr.*, .temp = false } });
                        try self.variables.put(self.allocator, value, Value{ .string = .{ .value = entry.value_ptr.string.value, .temp = false } });
                        try self.run(iteration.statements);
                    }
                },
                else => return error.EXPECTED_ITERABLE,
            }
        }

        fn run(self: *Self, ast: []AST.Statement) RuntimeError!void {
            for (ast) |statement| {
                try switch (statement) {
                    .assignment_stmt => |assignment| self.run_assignment(assignment),
                    .expression_stmt => |expression| {
                        var value = try self.run_expression(expression);
                        value.drop(self.allocator);
                    },
                    .selection_stmt => |selection| self.run_selection(selection),
                    .iteration_stmt => |iteration| self.run_iteration(iteration),
                    else => error.TODO,
                };
            }
        }
    };
}

const Scanner = @import("parser/scanner.zig");
const Parser = @import("parser/parser.zig");

const EmptyEnv = struct {};

// fn compile(Env: type, env: *Env, source: []const u8, allocator: std.mem.Allocator) !Runtime(Env) {
//
// }

fn eval_expression(Env: type, env: *Env, source: []const u8, allocator: std.mem.Allocator) !Runtime(Env).Value {
    const token = try Scanner.scan(source, allocator);
    defer allocator.free(token);
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var parser = try Parser.init(token, &arena);
    const ast = try parser.parse();
    try std.testing.expectEqual(1, ast.len);
    try std.testing.expect(ast[0] == .expression_stmt);
    var runtime = Runtime(Env).init(allocator, source, env);
    defer runtime.deinit();
    return runtime.run_expression(ast[0].expression_stmt);
}

fn eval_statements(Env: type, env: *Env, source: []const u8, allocator: std.mem.Allocator) !Runtime(Env) {
    var scanner = try Scanner.create(source);
    var token = try scanner.scan(allocator);
    defer token.deinit(allocator);
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var parser = try Parser.init(token.items, &arena);
    const ast = try parser.parse();
    var runtime = Runtime(Env).init(allocator, source, env);
    try runtime.run(ast);
    return runtime;
}

test "Arithmetic" {
    const source = "1 + 3 * 5 - 2";
    var env = EmptyEnv{};
    var value = try eval_expression(EmptyEnv, &env, source, std.testing.allocator);
    defer value.deinit(std.testing.allocator);
    try std.testing.expect(value == .integer);
    try std.testing.expectEqual(14, value.integer);
}

test "Concatenation" {
    const source =
        \\'abc' + '''
        \\1
        \\2
        \\''' + 'bca'
    ;
    const expected =
        \\abc
        \\1
        \\2
        \\bca
    ;
    var env = EmptyEnv{};
    var value = try eval_expression(EmptyEnv, &env, source, std.testing.allocator);
    defer value.deinit(std.testing.allocator);
    try std.testing.expect(value == .string);
    try std.testing.expectEqual(true, value.string.temp);
    try std.testing.expectEqualStrings(expected, value.string.value);
}

test "assignments" {
    const source =
        \\a = 56
        \\b = 'zig'
        \\a += 4
        \\a = a / 2
        \\b += 'zag'
    ;
    var env = EmptyEnv{};
    var runtime = try eval_statements(EmptyEnv, &env, source, std.testing.allocator);
    defer runtime.deinit();
    const a = runtime.variables.get("a") orelse return error.TEST_FAILED;
    try std.testing.expect(a == .integer);
    try std.testing.expectEqual(30, a.integer);
    const b = runtime.variables.get("b") orelse return error.TEST_FAILED;
    try std.testing.expect(b == .string);
    try std.testing.expectEqualStrings("zigzag", b.string.value);
}

const Printer = struct {
    pub fn print(str: []const u8) void {
        std.debug.print("{s}\n", .{str});
    }
};

test "Print" {
    const source = "print('Test')";
    var env = Printer{};
    _ = try eval_expression(Printer, &env, source, std.testing.allocator);
}

const Logger = struct {
    stderr: std.Io.Writer,
    stdout: std.io.Writer,
    pub fn @"error"(self: *Logger, code: i64, message: []const u8) std.Io.Writer.Error!void {
        try self.stderr.print("ERROR ({}): {s}\n", .{ code, message });
    }
    pub fn info(self: *Logger, message: []const u8) std.Io.Writer.Error!void {
        try self.stdout.print("INFO: {s}\n", .{message});
    }
};

test "Logger" {
    const source = "error(404, 'Not found')";
    const stderr = "ERROR (404): Not found\n";
    var stdout_buffer: [1024]u8 = undefined;
    var stderr_buffer: [1024]u8 = undefined;
    var logger = Logger{
        .stdout = std.Io.Writer.fixed(&stdout_buffer),
        .stderr = std.Io.Writer.fixed(&stderr_buffer),
    };
    _ = try eval_expression(Logger, &logger, source, std.testing.allocator);
    try std.testing.expectEqualStrings(stderr, stderr_buffer[0..stderr.len]);
}

test "condition" {
    const source =
        \\a = 5
        \\b = 'blop'
        \\if a < 5
        \\  error(1, 'a is too small')
        \\elif a > 10
        \\  error(2, 'a is too big')
        \\else
        \\  info('a is great')
        \\endif
        \\if b < 'zig'
        \\  error(3, 'b is greater than zig')
        \\endif
    ;
    const stdout = "INFO: a is great\n";
    const stderr = "ERROR (3): b is greater than zig\n";
    var stdout_buffer: [1024]u8 = undefined;
    var stderr_buffer: [1024]u8 = undefined;
    var logger = Logger{
        .stdout = std.Io.Writer.fixed(&stdout_buffer),
        .stderr = std.Io.Writer.fixed(&stderr_buffer),
    };
    var runtime = try eval_statements(Logger, &logger, source, std.testing.allocator);
    defer runtime.deinit();
    try std.testing.expectEqualStrings(stdout, stdout_buffer[0..stdout.len]);
    try std.testing.expectEqualStrings(stderr, stderr_buffer[0..stderr.len]);
}

test "for loop array" {
    const source =
        \\arr = [2, 3, 5, 7, 13, 17, 19]
        \\sum = 0
        \\foreach int: arr
        \\  sum += int
        \\endforeach
    ;
    var env = EmptyEnv{};
    var runtime = try eval_statements(EmptyEnv, &env, source, std.testing.allocator);
    defer runtime.deinit();
    const sum = runtime.variables.get("sum") orelse return error.TEST_FAILED;
    try std.testing.expect(sum == .integer);
    try std.testing.expectEqual(66, sum.integer);
}

test "break and continue" {
    const source = 
    \\items = ['a', 'continue', 'b', 'break', 'c']
    \\result = []
    \\foreach i : items
    \\  if i == 'continue'
    \\    continue
    \\  elif i == 'break'
    \\    break
    \\  endif
    \\  result += i
    \\endforeach
    \\# result is ['a', 'b']
    ;
    var env = EmptyEnv {};
    var runtime = try eval_statements(EmptyEnv, &env, source, std.testing.allocator);
    defer runtime.deinit();
    const result = runtime.variables.get("result") orelse return error.TEST_FAILED;
    try std.testing.expect(result == .array);
}
