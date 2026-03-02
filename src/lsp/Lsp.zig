const std = @import("std");
const Message = @import("Message.zig");
const Rpc = @import("Rpc.zig");
const Lsp = @This();

const State = enum {
    uninitialized,
    initialized,
};

state: State,
logger: *std.Io.Writer,

fn create(logger: *std.Io.Writer) Lsp {
    .{ .state = .uninitialized, .logger = logger };
}

fn handle(self: *Lsp, message: Rpc, gpa: std.mem.Allocator) Message.ParseError!?Rpc {
    const request = try Message.parse(message.body.content, gpa);
    try self.logger.print("Received a message with method: {}\n", .{request.method});
    switch (request.method) {
        .initialize => {
            const result = Message.InitializeResult{
                .capabilities = .{},
                .serverInfo = .{
                    .name = "educational-lsp",
                    .version = "0.0.0.0-beta1",
                },
            };
            const response = request.respond(Message.InitializeResult, result);
            const content = try std.json.Stringify.valueAlloc(gpa, response, .{ .emit_null_optional_fields = false });
            return Rpc.create(content);
        },
    }
}
