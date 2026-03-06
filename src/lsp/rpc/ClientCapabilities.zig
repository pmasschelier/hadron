const Completion = @import("Completion.zig");

const TextDocumentSyncClientCapabilities = struct {
    /// Whether text document synchronization supports dynamic registration.
    dynamicRegistration: ?bool,

    /// The client supports sending will save notifications.
    willSave: ?bool,

    /// The client supports sending a will save request and
    /// waits for a response providing text edits which will
    /// be applied to the document before it is saved.
    willSaveWaitUntil: ?bool,

    /// The client supports did save notifications.
    didSave: ?bool,
};

/// Text document specific client capabilities.
const TextDocumentClientCapabilities = struct {
    synchronization: ?TextDocumentSyncClientCapabilities,

    // Capabilities specific to the `textDocument/completion` request.
    // completion: ?Completion.ClientCapabilities,
};

/// Text document specific client capabilities.
textDocument: ?TextDocumentClientCapabilities,
