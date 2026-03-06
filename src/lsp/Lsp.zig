const std = @import("std");
const json = std.json;
pub const Base = @import("rpc/Base.zig");
pub const ClientCapabilities = @import("rpc/ClientCapabilities.zig");
pub const ServerCapabilities = @import("rpc/ServerCapabilities.zig");
pub const Initialize = @import("rpc/Initialize.zig");
pub const Completion = @import("rpc/Completion.zig");
pub const DidOpenTextDocument = @import("rpc/DidOpenTextDocument.zig");
pub const DidChangeTextDocument = @import("rpc/DidChangeTextDocument.zig");
pub const TextDocumentSyncKindEnum = ServerCapabilities.TextDocumentSyncKindEnum;

const Method = union(enum) {
    initialize: Initialize.Params,
    initialized,
    exit,
    shutdown,
    @"textDocument/didOpen": DidOpenTextDocument.Params,
    @"textDocument/didChange": DidChangeTextDocument.Params,
    @"textDocument/completion": Completion.Params,
};

const MethodName = std.meta.Tag(Method);

const PrimitiveMessage = struct {
    jsonrpc: []const u8,
    id: ?i32 = null,
    method: ?MethodName = null,
    params: ?json.Value = null,
};

fn ResponseError(comptime ErrorData: type) type {
    return struct {
        code: i32,
        message: []const u8,
        data: ?ErrorData = null,
    };
}

fn Response(comptime Result: type, comptime Error: type) type {
    return struct {
        id: ?i32,
        result: ?Result = null,
        @"error": ?ResponseError(Error) = null,
    };
}

pub const Request = struct {
    id: ?i32,
    method: Method,

    pub fn respond(self: Request, comptime Result: type, result: Result) Response(Result, struct {}) {
        return .{
            .id = self.id,
            .result = result,
        };
    }

    pub fn fail(self: Request, comptime Error: type, @"error": ResponseError) Response(struct {}, Error) {
        return .{
            .id = self.id,
            .@"error" = @"error",
        };
    }
};

pub const ParseError = error{ MissingMethodField, MissingParamsField } || json.ParseError(json.Scanner);
pub fn parse(request: []const u8, gpa: std.mem.Allocator) ParseError!Request {
    const options = json.ParseOptions{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
        .parse_numbers = true,
    };
    const primitive = try json.parseFromSliceLeaky(PrimitiveMessage, gpa, request, options);
    const method_name = primitive.method orelse return error.MissingMethodField;
    const method = switch (method_name) {
        inline else => |name| method: {
            const FieldType = std.meta.TagPayloadByName(Method, @tagName(name));
            break :method @unionInit(Method, @tagName(name), switch (@typeInfo(FieldType)) {
                .void => {},
                else => if (primitive.params) |params|
                    try json.parseFromValueLeaky(FieldType, gpa, params, options)
                else
                    return error.MissingParamsField,
            });
        },
    };
    return Request{
        .id = primitive.id,
        .method = method,
    };
}
