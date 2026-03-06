const Completion = @import("Completion.zig");
const Base = @import("Base.zig");

/// Defines how the host (editor) should sync document changes to the language
/// server.
pub const TextDocumentSyncKind = u2;

pub const TextDocumentSyncKindEnum = enum(TextDocumentSyncKind) {
    /// Documents should not be synced at all.
    None = 0,

    /// Documents are synced by always sending the full content
    /// of the document.
    Full = 1,

    /// Documents are synced by sending the full content on open.
    /// After that only incremental updates to the document are
    /// sent.
    Incremental = 2,
};

/// General text document registration options.
pub const TextDocumentChangeRegistrationOptions = struct {
    /// A document selector to identify the scope of the registration. If set to
    /// null the document selector provided on the client side will be used.
    documentSelector: ?[]Base.DocumentFilter = null,

    /// How documents are synced to the server. See TextDocumentSyncKind.Full
    /// and TextDocumentSyncKind.Incremental.
    syncKind: TextDocumentSyncKind,
};

/// Defines how text documents are synced. Is either a detailed structure
/// defining each notification or for backwards compatibility the
/// TextDocumentSyncKind number. If omitted it defaults to
/// `TextDocumentSyncKind.None`.
textDocumentSync: ?TextDocumentSyncKind = null,

/// The server provides completion support.
completionProvider: ?Completion.Options = null,
