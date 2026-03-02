/// This structure is defined by the lsp protocol but is not
/// in the lsp file because it used in other modules
const std = @import("std");

/// Line position in a document (zero-based).
line: usize,
/// Character offset on a line in a document (zero-based). The meaning of this
/// offset is determined by the negotiated `PositionEncodingKind`.
///
/// If the character value is greater than the line length it defaults back
/// to the line length.
character: usize,

const Position = @This();

/// Return the position of the next line start
fn newline(loc: Position) Position {
    return .{
        .col = 0,
        .row = loc.row + 1,
    };
}

/// Compute the position of a the source[index] character
/// by scaning the whole source, this may be a costly operation
/// for large files
fn compute(source: []const u8, index: usize) Position {
    const clamped = @min(source.len - 1, index);
    var line_start: usize = 0;
    var line_end: usize = std.mem.indexOfPos(u8, source, 0, "\n") orelse source.len;
    var line_no: usize = 1;
    while (clamped > line_end) {
        line_no += 1;
        line_start = line_end + 1;
        line_end = std.mem.indexOfPos(u8, source, line_start, "\n") orelse break;
    }
    return Position{
        .col = index - line_start,
        .row = line_no,
    };
}
