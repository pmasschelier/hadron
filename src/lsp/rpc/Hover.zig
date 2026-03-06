const Base = @import("base.zig");

pub const Params = struct {
    /// The text document.
    textDocument: Base.TextDocumentIdentifier,

    /// The position inside the text document.
    position: Base.Position,
};
