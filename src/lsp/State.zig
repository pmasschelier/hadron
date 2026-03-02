const std = @import("std");
const Lsp = @import("Lsp.zig");
const State = @This();

documents: std.StringHashMapUnmanaged([]const u8),
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) State {
    return .{
        .documents = .empty,
        .allocator = allocator,
    };
}

pub fn deinit(self: *State) void {
    self.documents.deinit(self.allocator);
}

pub fn open(self: *State, document: Lsp.TextDocumentItem) std.mem.Allocator.Error!void {
    try self.documents.put(self.allocator, document.uri, document.text);
}

pub fn change(self: *State, params: Lsp.DidChangeTextDocumentParams) std.mem.Allocator.Error!void {
    _ = self;
    _ = params;
}
