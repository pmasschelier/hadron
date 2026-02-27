const std = @import("std");

col: usize,
row: usize,

const Location = @This();

fn newline(loc: Location) Location {
    return .{
        .col = 0,
        .row = loc.row + 1,
    };
}

fn compute(source: []const u8, position: usize) Location {
    const clamped = @min(source.len - 1, position);
    var line_start: usize = 0;
    var line_end: usize = std.mem.indexOfPos(u8, source, 0, "\n") orelse source.len;
    var line_no: usize = 1;
    while (clamped > line_end) {
        line_no += 1;
        line_start = line_end + 1;
        line_end = std.mem.indexOfPos(u8, source, line_start, "\n") orelse break;
    }
    return Location{
        .col = position - line_start,
        .row = line_no,
    };
}
