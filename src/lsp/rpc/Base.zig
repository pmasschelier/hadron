const std = @import("std");
const Value = std.json.Value;

pub const Position = struct {
    /// Line position in a document (zero-based).
    line: u32,

    /// Character offset on a line in a document (zero-based). The meaning of this
    /// offset is determined by the negotiated `PositionEncodingKind`.
    ///
    /// If the character value is greater than the line length it defaults back
    /// to the line length.
    character: u32,
};

pub const Range = struct {
    /// The range's start position.
    start: Position,

    /// The range's end position.
    end: Position,
};

pub const TextDocumentItem = struct {
    uri: []const u8,
    languageId: []const u8,
    version: i64,
    text: []const u8,
};

pub const TextDocumentIdentifier = struct {
    /// The text document's URI.
    uri: []const u8,
};

pub const VersionedTextDocumentIdentifier = struct {
    /// The text document's URI.
    uri: []const u8,

    /// The version number of this document.
    ///
    /// The version number of a document will increase after each change,
    /// including undo/redo. The number doesn't need to be consecutive.
    version: i64,
};

const TextDocumentPositionParams = struct {
    /// The text document.
    textDocument: TextDocumentIdentifier,

    /// The position inside the text document.
    position: Position,
};

pub const DocumentFilter = struct {
    /// A language id, like `typescript`.
    language: ?[]const u8 = null,

    /// A Uri scheme, like `file` or `untitled`.
    scheme: ?[]const u8 = null,

    /// A glob pattern, like `*.{ts,js}`.
    ///
    /// Glob patterns can have the following syntax:
    /// - `*` to match zero or more characters in a path segment
    /// - `?` to match on one character in a path segment
    /// - `**` to match any number of path segments, including none
    /// - `{}` to group sub patterns into an OR expression. (e.g. `**​/*.{ts,js}`
    ///   matches all TypeScript and JavaScript files)
    /// - `[]` to declare a range of characters to match in a path segment
    ///   (e.g., `example.[0-9]` to match on `example.0`, `example.1`, …)
    /// - `[!...]` to negate a range of characters to match in a path segment
    ///   (e.g., `example.[!0-9]` to match on `example.a`, `example.b`, but
    ///   not `example.0`)
    pattern: ?[]const u8,
};

pub const TextEdit = struct {
    /// The range of the text document to be manipulated. To insert
    /// text into a document create a range where start === end.
    range: Range,

    /// The []const u8 to be inserted. For delete operations use an
    /// empty []const u8.
    newText: []const u8,
};

const Command = struct {
    /// Title of the command, like `save`.
    title: []const u8,
    /// The identifier of the actual command handler.
    command: []const u8,
    /// Arguments that the command handler should be
    /// invoked with.
    arguments: ?[]Value,
};

/// Additional information that describes document changes.
///
/// @since 3.16.0
const ChangeAnnotation = struct {
    /// A human-readable []const u8 describing the actual change. The string
    /// is rendered prominent in the user interface.
    label: []const u8,

    /// A flag which indicates that user confirmation is needed
    /// before applying the change.
    needsConfirmation: ?bool,

    /// A human-readable []const u8 which is rendered less prominent in
    /// the user interface.
    description: ?[]const u8,
};

pub const MarkupKind = enum { plaintext, markdown };

/// A `MarkupContent` literal represents a string value which content is
/// interpreted base on its kind flag. Currently the protocol supports
/// `plaintext` and `markdown` as markup kinds.
///
/// If the kind is `markdown` then the value can contain fenced code blocks like
/// in GitHub issues.
///
/// Here is an example how such a string can be constructed using
/// JavaScript / TypeScript:
/// ```typescript
/// let markdown: MarkdownContent = {
///     kind: MarkupKind.Markdown,
///     value: [
///         '# Header',
///         'Some text',
///         '```typescript',
///         'someCode();',
///         '```'
///     ].join('\n')
/// };
/// ```
///
/// *Please Note* that clients might sanitize the return markdown. A client could
/// decide to remove HTML from the markdown to avoid script execution.
pub const MarkupContent = struct {
    /// The type of the Markup
    kind: MarkupKind,

    /// The content itself
    value: []const u8,
};
