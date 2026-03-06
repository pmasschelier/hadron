const Base = @import("Base.zig");

/// An event describing a change to a text document. If only a text is provided
/// it is considered to be the full content of the document.
pub const TextDocumentContentChangeEvent = struct {
    /// The range of the document that changed.
    /// Note: If not provided the whole document
    /// is sent
    range: ?Base.Range = null,

    /// The optional length of the range that got replaced.
    ///
    /// @deprecated use range instead.
    rangeLength: ?usize = null,

    /// The new text for the provided range.
    text: []const u8,
};

pub const Params = struct {
    /// The document that did change. The version number points
    /// to the version after all provided content changes have
    /// been applied.
    textDocument: Base.VersionedTextDocumentIdentifier,

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
