const std = @import("std");
const Lsp = @import("Lsp.zig");

const Document = struct {
    text: []const u8,
};

pub fn LanguageServer(comptime Environment: type) type {
    _ = Environment;
    return struct {
        const Self = @This();

        const State = enum {
            Uninitialized,
            Initialized,
        };

        documents: std.StringHashMapUnmanaged([]const u8) = .empty,
        allocator: std.mem.Allocator,
        state: State = .Uninitialized,
        client: ?Lsp.ClientCapabilities = null,

        pub fn create(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
            };
        }

        pub fn init(self: *Self, params: Lsp.Initialize.Params) Lsp.Initialize.Result {
            self.state = .Initialized;
            self.client = params.capabilities;
            return .{
                .capabilities = .{
                    .textDocumentSync = @intFromEnum(Lsp.TextDocumentSyncKindEnum.Incremental),
                    .completionProvider = .{},
                },
                .serverInfo = .{
                    .name = "educational-lsp",
                    .version = "0.0.0.0-beta1",
                },
            };
        }

        pub fn deinit(self: *Self) void {
            self.state = .Uninitialized;
            self.documents.deinit(self.allocator);
        }

        pub fn open(self: *Self, document: Lsp.Base.TextDocumentItem) std.mem.Allocator.Error!void {
            try self.documents.put(self.allocator, document.uri, document.text);
        }

        pub fn change(self: *Self, params: Lsp.DidChangeTextDocument.Params) std.mem.Allocator.Error!void {
            _ = self;
            _ = params;
        }

        pub fn complete(self: Self, params: Lsp.Completion.Params) Lsp.Completion.Result {
            params.textDocument
        }
    };
}
