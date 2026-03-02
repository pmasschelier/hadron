const std = @import("std");

const Rpc = @This();

fn peekSequenceExclusive(r: *std.Io.Reader, sequence: []const u8) std.io.Reader.DelimiterError![]u8 {
    {
        const contents = r.buffer[0..r.end];
        const seek = r.seek;
        if (std.mem.indexOfPos(u8, contents, seek, sequence)) |end| {
            @branchHint(.likely);
            return contents[seek..end];
        }
    }
    while (true) {
        const content_len = r.end - r.seek;
        if (r.buffer.len - content_len == 0) break;
        try r.fillMore();
        const seek = r.seek;
        const contents = r.buffer[0..r.end];
        if (std.mem.indexOfPos(u8, contents, seek + content_len, sequence)) |end| {
            return contents[seek..end];
        }
    }
    // It might or might not be end of stream. There is no more buffer space
    // left to disambiguate. If `StreamTooLong` was added to `RebaseError` then
    // this logic could be replaced by removing the exit condition from the
    // above while loop. That error code would represent when `buffer` capacity
    // is too small for an operation, replacing the current use of asserts.
    var failing_writer = std.Io.Writer.failing;
    while (r.vtable.stream(r, &failing_writer, .limited(1))) |n| {
        std.debug.assert(n == 0);
    } else |err| switch (err) {
        error.WriteFailed => return error.StreamTooLong,
        error.ReadFailed => |e| return e,
        error.EndOfStream => |e| return e,
    }
}

pub fn takeSequenceExclusive(r: *std.Io.Reader, sequence: []const u8) std.Io.Reader.DelimiterError![]u8 {
    const result = try peekSequenceExclusive(r, sequence);
    r.toss(result.len);
    return result;
}

const Header = struct {
    contentLength: usize,
    contentType: ?[]const u8,
    const Error = error{
        LineIsNotHeaderField,
        InvalidContentLength,
        LineAsNoValue,
        ContentLengthMissing,
    };

    const Field = enum {
        CONTENT_LENGTH,
        CONTENT_TYPE,
    };

    const field_map = std.StaticStringMap(Field).initComptime(.{
        .{ "Content-Length", .CONTENT_LENGTH },
        .{ "Content-Type", .CONTENT_TYPE },
    });

    const ParseError = Header.Error || std.io.Reader.DelimiterError || std.mem.Allocator.Error;

    const DefaultContentType = "application/vscode-jsonrpc; charset=utf-8";

    fn parse(reader: *std.Io.Reader, gpa: std.mem.Allocator) ParseError!Header {
        var content_length: ?usize = null;
        var content_type: ?[]const u8 = null;
        while (true) {
            const line = takeSequenceExclusive(reader, "\r\n") catch |err| return err;
            if (line.len == 0) break;
            const sep = std.mem.indexOfScalar(u8, line, ':') orelse return error.LineIsNotHeaderField;
            const field = field_map.get(line[0..sep]) orelse continue;
            if (sep + 2 >= line.len) return error.LineAsNoValue;
            switch (field) {
                .CONTENT_LENGTH => {
                    content_length = std.fmt.parseInt(usize, line[sep + 2 ..], 10) catch return error.InvalidContentLength;
                },
                .CONTENT_TYPE => {
                    content_type = try gpa.dupe(u8, line[sep + 2 ..]);
                },
            }
            reader.toss(2);
        }
        reader.toss(2);
        return if (content_length) |length|
            .{ .contentLength = length, .contentType = content_type }
        else
            error.ContentLengthMissing;
    }

    pub fn deinit(self: Header, gpa: std.mem.Allocator) void {
        if (self.contentType) |contentType|
            gpa.free(contentType);
    }
};

const Body = struct {
    content: []const u8,

    const ParseError = std.Io.Reader.Error || std.mem.Allocator.Error;
    fn parse(reader: *std.Io.Reader, gpa: std.mem.Allocator, header: Header) ParseError!Body {
        const content = try reader.take(header.contentLength);
        return .{ .content = try gpa.dupe(u8, content) };
    }

    fn deinit(self: Body, gpa: std.mem.Allocator) void {
        gpa.free(self.content);
    }
};

header: Header,
body: Body,

const Error = Body.ParseError || Header.ParseError;

pub fn create(content: []const u8) Rpc {
    return .{
        .header = .{
            .contentLength = content.len,
            .contentType = Header.DefaultContentType,
        },
        .body = .{ .content = content },
    };
}

pub fn read(reader: *std.Io.Reader, gpa: std.mem.Allocator) Error!Rpc {
    const header = try Header.parse(reader, gpa);
    const body = try Body.parse(reader, gpa, header);
    return .{ .header = header, .body = body };
}

pub fn write(self: Rpc, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("Content-Length: {}\r\n\r\n", .{self.header.contentLength});
    const written = try writer.write(self.body.content);
    try writer.flush();
    std.debug.assert(written == self.header.contentLength);
}

pub fn deinit(self: Rpc, gpa: std.mem.Allocator) void {
    self.header.deinit(gpa);
    self.body.deinit(gpa);
}
