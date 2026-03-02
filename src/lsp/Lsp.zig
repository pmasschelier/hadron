const std = @import("std");
const json = std.json;
const Position = @import("../Position.zig");

const Method = union(enum) {
    initialize: InitializeParams,
    initialized,
    @"textDocument/didOpen": DidOpenTextDocumentParams,
    @"textDocument/didChange": DidChangeTextDocumentParams,
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

pub const TextDocumentSyncKind = u2;

pub const TextDocumentSyncKindEnum = enum(TextDocumentSyncKind) {
    None = 0,
    Full = 1,
    Incremental = 2,
};

const ClientCapabilities = json.Value;
const ServerCapabilities = struct {
    textDocumentSync: ?TextDocumentSyncKind = null,
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

pub const TextDocumentItem = struct {
    uri: []const u8,
    languageId: []const u8,
    version: i64,
    text: []const u8,
};

pub const DidOpenTextDocumentParams = struct {
    textDocument: TextDocumentItem,
};

pub const DocumentFilter = struct {
    /// A language id, like `typescript`.
    language: ?[]const u8 = null,

    /// A Uri scheme, like `file` or `untitled`.
    scheme: ?[]const u8 = null,

    /// A glob pattern, like `*.{ts,js}`.
    ///
    /// Glob patterns can have the following syntax:
    /// - `*` to match zero or more characters in a path segment
    /// - `?` to match on one character in a path segment
    /// - `**` to match any number of path segments, including none
    /// - `{}` to group sub patterns into an OR expression. (e.g. `**​/*.{ts,js}`
    ///   matches all TypeScript and JavaScript files)
    /// - `[]` to declare a range of characters to match in a path segment
    ///   (e.g., `example.[0-9]` to match on `example.0`, `example.1`, …)
    /// - `[!...]` to negate a range of characters to match in a path segment
    ///   (e.g., `example.[!0-9]` to match on `example.a`, `example.b`, but
    ///   not `example.0`)
    pattern: ?[]const u8,
};

/// General text document registration options.
pub const TextDocumentChangeRegistrationOptions = struct {
    /// A document selector to identify the scope of the registration. If set to
    /// null the document selector provided on the client side will be used.
    documentSelector: ?[]DocumentFilter = null,

    /// How documents are synced to the server. See TextDocumentSyncKind.Full
    /// and TextDocumentSyncKind.Incremental.
    syncKind: TextDocumentSyncKind,
};

pub const TextDocumentIdentifier = struct {
    /// The text document's URI.
    uri: []const u8,
};

pub const VersionedTextDocumentIdentifier = struct {
    /// The text document's URI.
    uri: []const u8,

    /// The version number of this document.
    ///
    /// The version number of a document will increase after each change,
    /// including undo/redo. The number doesn't need to be consecutive.
    version: i64,
};

pub const TextDocumentPositionParams = struct {
    /// The text document.
    textDocument: TextDocumentIdentifier,

    /// The position inside the text document.
    position: Position,
};

pub const HoverParams = struct {
    /// The text document.
    textDocument: TextDocumentIdentifier,

    /// The position inside the text document.
    position: Position,
};

pub const Range = struct {
    /// The range's start position.
    start: Position,

    /// The range's end position.
    end: Position,
};

/// An event describing a change to a text document. If only a text is provided
/// it is considered to be the full content of the document.
pub const TextDocumentContentChangeEvent = struct {
    /// The range of the document that changed.
    /// Note: If not provided the whole document
    /// is sent
    range: ?Range = null,

    /// The optional length of the range that got replaced.
    ///
    /// @deprecated use range instead.
    rangeLength: ?usize = null,

    /// The new text for the provided range.
    text: []const u8,
};

pub const DidChangeTextDocumentParams = struct {
    /// The document that did change. The version number points
    /// to the version after all provided content changes have
    /// been applied.
    textDocument: VersionedTextDocumentIdentifier,

    /// The actual content changes. The content changes describe single state
    /// changes to the document. So if there are two content changes c1 (at
    /// array index 0) and c2 (at array index 1) for a document in state S then
    /// c1 moves the document from S to S' and c2 from S' to S''. So c1 is
    /// computed on the state S and c2 is computed on the state S'.
    ///
    /// To mirror the content of a document using change events use the following
    /// approach:
    /// - start with the same initial content
    /// - apply the 'textDocument/didChange' notifications in the order you
    ///   receive them.
    /// - apply the `TextDocumentContentChangeEvent`s in a single notification
    ///   in the order you receive them.
    contentChanges: []TextDocumentContentChangeEvent,
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
