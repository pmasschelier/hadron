const std = @import("std");
const Base = @import("Base.zig");

const Position = @import("../../Position.zig");

/// Completion item tags are extra annotations that tweak the rendering of a
/// completion item.
///
/// @since 3.15.0
const CompletionItemTag = u1;
const CompletionItemTagEnum = enum {
    /// Render a completion as obsolete, usually using a strike-out.
    Deprecated,
};

const InsertTextMode = u1;
const InsertTextModeEnum = enum(InsertTextMode) {
    /// The insertion or replace strings is taken as it is. If the
    /// value is multi line the lines below the cursor will be
    /// inserted using the indentation defined in the string value.
    /// The client will not apply any kind of adjustments to the
    /// string.
    asIs = 1,

    /// The editor adjusts leading whitespace of new lines so that
    /// they match the indentation up to the cursor of the line for
    /// which the item is accepted.
    ///
    /// Consider a line like this: <2tabs><cursor><3tabs>foo. Accepting a
    /// multi line completion item is indented using 2 tabs and all
    adjustIndentation = 2,
};

const CompletionItemKind = u5;

/// The kind of a completion entry.
const CompletionItemKindEnum = enum(u5) {
    Text = 1,
    Method = 2,
    Function = 3,
    Constructor = 4,
    Field = 5,
    Variable = 6,
    Class = 7,
    Interface = 8,
    Module = 9,
    Property = 10,
    Unit = 11,
    Value = 12,
    Enum = 13,
    Keyword = 14,
    Snippet = 15,
    Color = 16,
    File = 17,
    Reference = 18,
    Folder = 19,
    EnumMember = 20,
    Constant = 21,
    Struct = 22,
    Event = 23,
    Operator = 24,
    TypeParameter = 25,
};

pub const ClientCapabilities = struct {
    /// Whether completion supports dynamic registration.
    dynamicRegistration: ?bool = null,

    /// The client supports the following `CompletionItem` specific
    /// capabilities.
    completionItem: ?struct {
        /// Client supports snippets as insert text.
        ///
        /// A snippet can define tab stops and placeholders with `$1`, `$2`
        /// and `${3:foo}`. `$0` defines the final tab stop, it defaults to
        /// the end of the snippet. Placeholders with equal identifiers are
        /// linked, that is typing in one will update others too.
        snippetSupport: ?bool,

        /// Client supports commit characters on a completion item.
        commitCharactersSupport: ?bool,

        /// Client supports the follow content formats for the documentation
        /// property. The order describes the preferred format of the client.
        documentationFormat: ?[]Base.MarkupKind,

        /// Client supports the deprecated property on a completion item.
        deprecatedSupport: ?bool,

        /// Client supports the preselect property on a completion item.
        preselectSupport: ?bool,

        /// Client supports the tag property on a completion item. Clients
        /// supporting tags have to handle unknown tags gracefully. Clients
        /// especially need to preserve unknown tags when sending a completion
        /// item back to the server in a resolve call.
        ///
        /// @since 3.15.0
        tagSupport: ?struct {
            /// The tags supported by the client.
            valueSet: []CompletionItemTag,
        },

        /// Client supports insert replace edit to control different behavior if
        /// a completion item is inserted in the text or should replace text.
        ///
        /// @since 3.16.0
        insertReplaceSupport: ?bool,

        /// Indicates which properties a client can resolve lazily on a
        /// completion item. Before version 3.16.0 only the predefined properties
        /// `documentation` and `detail` could be resolved lazily.
        ///
        /// @since 3.16.0
        resolveSupport: ?struct {
            /// The properties that a client can resolve lazily.
            properties: []const u8,
        },

        /// The client supports the `insertTextMode` property on
        /// a completion item to override the whitespace handling mode
        /// as defined by the client (see `insertTextMode`).
        ///
        /// @since 3.16.0
        insertTextModeSupport: ?struct {
            valueSet: []InsertTextMode,
        },

        /// The client has support for completion item label
        /// details (see also `CompletionItemLabelDetails`).
        ///
        /// @since 3.17.0
        labelDetailsSupport: ?bool,
    },

    completionItemKind: ?struct {
        /// The completion item kind values the client supports. When this
        /// property exists the client also guarantees that it will
        /// handle values outside its set gracefully and falls back
        /// to a default value when unknown.
        ///
        /// If this property is not present the client only supports
        /// the completion items kinds from `Text` to `Reference` as defined in
        /// the initial version of the protocol.
        valueSet: ?[]CompletionItemKind,
    },

    /// The client supports to send additional context information for a
    /// `textDocument/completion` request.
    contextSupport: ?bool,

    /// The client's default when the completion item doesn't provide a
    /// `insertTextMode` property.
    ///
    /// @since 3.17.0
    insertTextMode: ?InsertTextMode,

    /// The client supports the following `CompletionList` specific
    /// capabilities.
    ///
    /// @since 3.17.0
    completionList: ?struct {
        /// The client supports the following itemDefaults on
        /// a completion list.
        ///
        /// The value lists the supported property names of the
        /// `CompletionList.itemDefaults` object. If omitted
        /// no properties are supported.
        ///
        /// @since 3.17.0
        itemDefaults: ?[]const u8,
    },
};

/// Completion options
pub const Options = struct {
    /// The additional characters, beyond the defaults provided by the client (typically
    /// [a-zA-Z]), that should automatically trigger a completion request. For example
    /// `.` in JavaScript represents the beginning of an object property or method and is
    /// thus a good candidate for triggering a completion request.
    ///
    /// Most tools trigger a completion request automatically without explicitly
    /// requesting it using a keyboard shortcut (e.g. Ctrl+Space). Typically they
    /// do so when the user starts to type an identifier. For example if the user
    /// types `c` in a JavaScript file code complete will automatically pop up
    /// present `console` besides others as a completion item. Characters that
    /// make up identifiers don't need to be listed here.
    triggerCharacters: ?[]const u8 = null,

    /// The list of all possible characters that commit a completion. This field
    /// can be used if clients don't support individual commit characters per
    /// completion item. See client capability
    /// `completion.completionItem.commitCharactersSupport`.
    ///
    /// If a server provides both `allCommitCharacters` and commit characters on
    /// an individual completion item the ones on the completion item win.
    ///
    /// @since 3.2.0
    allCommitCharacters: ?[]const u8 = null,

    /// The server provides support to resolve additional
    /// information for a completion item.
    resolveProvider: ?bool = null,

    /// The server supports the following `CompletionItem` specific
    /// capabilities.
    ///
    /// @since 3.17.0
    completionItem: ?struct {
        /// The server has support for completion item label
        /// details (see also `CompletionItemLabelDetails`) when receiving
        /// a completion item in a resolve call.
        ///
        /// @since 3.17.0
        labelDetailsSupport: ?bool = null,
    } = null,
};

pub const Params = struct {
    /// The completion context. This is only available if the client specifies
    /// to send this using the client capability
    /// `completion.contextSupport === true`
    context: ?CompletionContext,

    // NOTE: From TextDocumentPositionParams

    /// The text document.
    textDocument: Base.TextDocumentIdentifier,

    /// The position inside the text document.
    position: Position,
};

pub const CompletionTriggerKind = u2;
pub const CompletionTriggerKindEnum = enum(CompletionTriggerKind) {
    Invoked = 1,
    TriggerCharacter = 2,
    TriggerForIncompleteCompletions = 3,
};

/// Contains additional information about the context in which a completion
/// request is triggered.
const CompletionContext = struct {
    /// How the completion was triggered.
    triggerKind: CompletionTriggerKind,

    /// The trigger character (a single character) that has trigger code
    /// complete. Is undefined if
    /// `triggerKind !== CompletionTriggerKind.TriggerCharacter`
    triggerCharacter: ?[]const u8 = null,
};

/// Defines whether the insert text in a completion item should be interpreted as
/// plain text or a snippet.
const InsertTextFormat = u1;

const InsertTextFormatEnum = enum(InsertTextFormat) {
    /// The primary text to be inserted is treated as a plain string.
    PlainText = 1,

    /// The primary text to be inserted is treated as a snippet.
    ///
    /// A snippet can define tab stops and placeholders with `$1`, `$2`
    /// and `${3:foo}`. `$0` defines the final tab stop, it defaults to
    /// the end of the snippet. Placeholders with equal identifiers are linked,
    /// that is typing in one will update others too.
    Snippet = 2,
};

pub const Result = CompletionList;

/// Represents a collection of [completion items](#CompletionItem) to be
/// presented in the editor.
const CompletionList = struct {
    /// This list is not complete. Further typing should result in recomputing
    /// this list.
    ///
    /// Recomputed lists have all their items replaced (not appended) in the
    /// incomplete completion sessions.
    isIncomplete: bool,

    /// In many cases the items of an actual completion result share the same
    /// value for properties like `commitCharacters` or the range of a text
    /// edit. A completion list can therefore define item defaults which will
    /// be used if a completion item itself doesn't specify the value.
    ///
    /// If a completion list specifies a default value and a completion item
    /// also specifies a corresponding value the one from the item is used.
    ///
    /// Servers are only allowed to return default values if the client
    /// signals support for this via the `completionList.itemDefaults`
    /// capability.
    ///
    /// @since 3.17.0
    itemDefaults: ?struct {
        /// A default commit character set.
        ///
        /// @since 3.17.0
        commitCharacters: ?[]const u8,

        // TODO: Implement sum types
        // A default edit range
        //
        // @since 3.17.0
        // editRange?: Range | {
        //      insert: Range;
        //      replace: Range;
        // };

        /// A default insert text format
        ///
        /// @since 3.17.0
        insertTextFormat: ?InsertTextFormat,

        /// A default insert text mode
        ///
        /// @since 3.17.0
        insertTextMode: ?InsertTextMode,

        /// A default data value.
        ///
        /// @since 3.17.0
        data: ?std.json.Value,
    },

    /// The completion items.
    items: []CompletionItem,
};

/// Additional details for a completion item label.
///
/// @since 3.17.0
const CompletionItemLabelDetails = struct {
    /// An optional string which is rendered less prominently directly after
    /// {@link CompletionItem.label label}, without any spacing. Should be
    /// used for function signatures or type annotations.
    detail: ?[]const u8 = null,

    /// An optional string which is rendered less prominently after
    /// {@link CompletionItemLabelDetails.detail}. Should be used for fully qualified
    /// names or file path.
    description: ?[]const u8 = null,
};

const CompletionItem = struct {
    /// The label of this completion item.
    ///
    /// The label property is also by default the text that
    /// is inserted when selecting this completion.
    ///
    /// If label details are provided the label itself should
    /// be an unqualified name of the completion item.
    label: []const u8,

    /// Additional details for the label
    ///
    /// @since 3.17.0
    labelDetails: ?CompletionItemLabelDetails,

    /// The kind of this completion item. Based of the kind
    /// an icon is chosen by the editor. The standardized set
    /// of available values is defined in `CompletionItemKind`.
    kind: ?CompletionItemKind,

    /// Tags for this completion item.
    ///
    /// @since 3.15.0
    tags: ?[]CompletionItemTag,

    /// A human-readable string with additional information
    /// about this item, like type or symbol information.
    detail: ?[]const u8,

    /// A human-readable string that represents a doc-comment.
    documentation: ?Base.MarkupContent,

    /// Indicates if this item is deprecated.
    ///
    /// @deprecated Use `tags` instead if supported.
    deprecated: ?bool,

    /// Select this item when showing.
    ///
    /// *Note* that only one completion item can be selected and that the
    /// tool / client decides which item that is. The rule is that the *first*
    /// item of those that match best is selected.
    preselect: ?bool,

    /// A string that should be used when comparing this item
    /// with other items. When omitted the label is used
    /// as the sort text for this item.
    sortText: ?[]const u8,

    /// A string that should be used when filtering a set of
    /// completion items. When omitted the label is used as the
    /// filter text for this item.
    filterText: ?[]const u8,

    /// A string that should be inserted into a document when selecting
    /// this completion. When omitted the label is used as the insert text
    /// for this item.
    ///
    /// The `insertText` is subject to interpretation by the client side.
    /// Some tools might not take the string literally. For example
    /// VS Code when code complete is requested in this example
    /// `con<cursor position>` and a completion item with an `insertText` of
    /// `console` is provided it will only insert `sole`. Therefore it is
    /// recommended to use `textEdit` instead since it avoids additional client
    /// side interpretation.
    insertText: ?[]const u8,

    /// The format of the insert text. The format applies to both the
    /// `insertText` property and the `newText` property of a provided
    /// `textEdit`. If omitted defaults to `InsertTextFormat.PlainText`.
    ///
    /// Please note that the insertTextFormat doesn't apply to
    /// `additionalTextEdits`.
    insertTextFormat: ?InsertTextFormat,

    /// How whitespace and indentation is handled during completion
    /// item insertion. If not provided the client's default value depends on
    /// the `textDocument.completion.insertTextMode` client capability.
    ///
    /// @since 3.16.0
    /// @since 3.17.0 - support for `textDocument.completion.insertTextMode`
    insertTextMode: ?InsertTextMode,

    /// An edit which is applied to a document when selecting this completion.
    /// When an edit is provided the value of `insertText` is ignored.
    ///
    /// *Note:* The range of the edit must be a single line range and it must
    /// contain the position at which completion has been requested.
    ///
    /// Most editors support two different operations when accepting a completion
    /// item. One is to insert a completion text and the other is to replace an
    /// existing text with a completion text. Since this can usually not be
    /// predetermined by a server it can report both ranges. Clients need to
    /// signal support for `InsertReplaceEdit`s via the
    /// `textDocument.completion.completionItem.insertReplaceSupport` client
    /// capability property.
    ///
    /// *Note 1:* The text edit's range as well as both ranges from an insert
    /// replace edit must be a [single line] and they must contain the position
    /// at which completion has been requested.
    /// *Note 2:* If an `InsertReplaceEdit` is returned the edit's insert range
    /// must be a prefix of the edit's replace range, that means it must be
    /// contained and starting at the same position.
    ///
    /// @since 3.16.0 additional type `InsertReplaceEdit`
    // /TODO: Implement sum types
    // textEdit: ?TextEdit | InsertReplaceEdit,

    /// The edit text used if the completion item is part of a CompletionList and
    /// CompletionList defines an item default for the text edit range.
    ///
    /// Clients will only honor this property if they opt into completion list
    /// item defaults using the capability `completionList.itemDefaults`.
    ///
    /// If not provided and a list's default range is provided the label
    /// property is used as a text.
    ///
    /// @since 3.17.0
    textEditText: ?[]const u8,

    /// An optional array of additional text edits that are applied when
    /// selecting this completion. Edits must not overlap (including the same
    /// insert position) with the main edit nor with themselves.
    ///
    /// Additional text edits should be used to change text unrelated to the
    /// current cursor position (for example adding an import statement at the
    /// top of the file if the completion item will insert an unqualified type).
    additionalTextEdits: ?[]Base.TextEdit,

    /// An optional set of characters that when pressed while this completion is
    /// active will accept it first and then type that character. *Note* that all
    /// commit characters should have `length=1` and that superfluous characters
    /// will be ignored.
    commitCharacters: ?[]const u8,

    /// An optional command that is executed *after* inserting this completion.
    /// *Note* that additional modifications to the current document should be
    /// described with the additionalTextEdits-property.
    command: ?Base.Command,

    /// A data entry field that is preserved on a completion item between
    /// a completion and a completion resolve request.
    data: ?std.json.Value,
};
