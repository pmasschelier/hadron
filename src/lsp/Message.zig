const std = @import("std");
const json = std.json;

const Method = union(enum) {
    initialize: InitializeParams,
    initialized,
    @"textDocument/didOpen": DidOpenTextDocumentParams,
};

const MethodName = std.meta.Tag(Method);

const PrimitiveMessage = struct {
    jsonrpc: []const u8,
    id: ?usize = null,
    method: ?MethodName = null,
    params: ?json.Value = null,
};

const Infos = struct {
    name: []const u8,
    version: ?[]const u8,
};

pub const TextDocumentSyncKind = enum(u2) {
    None = 0,
    Full = 1,
    Incremental = 2,
};

const ClientCapabilities = json.Value;
const ServerCapabilities = struct {
    textDocumentSync: ?u2 = null,
};

const TraceValue = enum { off, messages, verbose };

const WorkspaceFolder = struct {
    uri: []const u8,
    name: []const u8,
};

const InitializeParams = struct {
    processId: ?u64 = null,
    clientInfo: ?Infos = null,
    locale: ?[]const u8 = null,
    rootPath: ?[]const u8 = null,
    rootUri: ?[]const u8 = null,
    initializationOptions: ?json.Value = null,
    capabilities: ClientCapabilities,
    trace: ?TraceValue = null,
    workspaceFolders: ?[]const WorkspaceFolder = null,
};

pub const InitializeResult = struct {
    capabilities: ServerCapabilities,
    serverInfo: ?Infos = null,
};

const TextDocumentItem = struct {
    uri: []const u8,
    languageId: []const u8,
    version: i64,
    text: []const u8,
};

pub const DidOpenTextDocumentParams = struct {
    textDocument: TextDocumentItem,
};

fn ResponseError(comptime ErrorData: type) type {
    return struct {
        code: i64,
        message: []const u8,
        data: ?ErrorData = null,
    };
}

fn Response(comptime Result: type, comptime Error: type) type {
    return struct {
        id: ?usize,
        result: ?Result = null,
        @"error": ?ResponseError(Error) = null,
    };
}

pub const Request = struct {
    id: ?usize,
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
