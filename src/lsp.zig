const std = @import("std");
const Rpc = @import("lsp/Rpc.zig");
const Lsp = @import("lsp/Lsp.zig");
const State = @import("lsp/State.zig");

pub fn main() !void {
    // Setting up stdin, stdout and logger interfaces
    var stdin_buffer: [16384]u8 = undefined;
    var stdin = std.fs.File.stdin().reader(&stdin_buffer);
    const reader = &stdin.interface;

    var stdout_buffer: [4096]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buffer);
    const writer = &stdout.interface;

    var logger_buffer: [4096]u8 = undefined;
    var logfile = try std.fs.cwd().createFile("lsp.log", .{ .read = false, .truncate = true });
    defer logfile.close();
    var logger_writer = logfile.writer(&logger_buffer);
    const logger = &logger_writer.interface;

    // Setup the arena used to allocate for each request
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer std.debug.assert(gpa.deinit() == .ok);

    var state = State.init(gpa.allocator());
    defer state.deinit();

    // Read from stdin until an error is returned
    while (Rpc.read(reader, arena.allocator())) |msg| {
        try logger.print("Received a message of {} bytes:\n{s}\n", .{ msg.header.contentLength, msg.body.content });
        const message = try Lsp.parse(msg.body.content, arena.allocator());
        try logger.print("Decoded message: {}\n", .{message});
        switch (message.method) {
            .initialize => {
                const result = Lsp.InitializeResult{
                    .capabilities = .{
                        .textDocumentSync = @intFromEnum(Lsp.TextDocumentSyncKindEnum.Full),
                    },
                    .serverInfo = .{
                        .name = "educational-lsp",
                        .version = "0.0.0.0-beta1",
                    },
                };
                const response = message.respond(Lsp.InitializeResult, result);
                const content = try std.json.Stringify.valueAlloc(arena.allocator(), response, .{
                    .emit_null_optional_fields = false,
                });
                try Rpc.create(content).write(writer);
            },
            .initialized => {},
            .@"textDocument/didOpen" => |params| {
                try state.open(params.textDocument);
                try logger.print("Received text content: {s}\n", .{params.textDocument.text});
            },
            .@"textDocument/didChange" => |params| {
                try state.change(params);
                try logger.print("Text changed: {s} (v{})\n", .{ params.textDocument.uri, params.textDocument.version });
            },
        }
        try logger.flush();
        _ = arena.reset(.{ .retain_with_limit = std.heap.pageSize() });
    } else |err| switch (err) {
        error.EndOfStream => try logger.print("End of stream reached, closing...\n", .{}),
        else => return err,
    }
}
