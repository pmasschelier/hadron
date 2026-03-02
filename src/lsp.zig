const std = @import("std");
const Rpc = @import("lsp/Rpc.zig");
const Message = @import("lsp/Message.zig");
const Lsp = @import("lsp/Lsp.zig");

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

    // Read from stdin until an error is returned
    while (Rpc.read(reader, arena.allocator())) |msg| {
        try logger.print("Received a message of {} bytes:\n{s}\n", .{ msg.header.contentLength, msg.body.content });
        const message = try Message.parse(msg.body.content, arena.allocator());
        try logger.print("Decoded message: {}\n", .{message});
        switch (message.method) {
            .initialize => {
                const result = Message.InitializeResult{
                    .capabilities = .{
                        .textDocumentSync = @intFromEnum(Message.TextDocumentSyncKind.Full),
                    },
                    .serverInfo = .{
                        .name = "educational-lsp",
                        .version = "0.0.0.0-beta1",
                    },
                };
                const response = message.respond(Message.InitializeResult, result);
                const content = try std.json.Stringify.valueAlloc(arena.allocator(), response, .{
                    .emit_null_optional_fields = false,
                });
                try Rpc.create(content).write(writer);
            },
            .initialized => {},
            .@"textDocument/didOpen" => |params| {
                try logger.print("Received text content: {s}\n", .{params.textDocument.text});
            },
        }
        try logger.flush();
        _ = arena.reset(.retain_capacity);
    } else |err| switch (err) {
        error.EndOfStream => try logger.print("End of stream reached, closing...\n", .{}),
        else => return err,
    }
}
