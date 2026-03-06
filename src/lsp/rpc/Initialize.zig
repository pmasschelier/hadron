const std = @import("std");
const ClientCapabilities = @import("ClientCapabilities.zig");
const ServerCapabilities = @import("ServerCapabilities.zig");

const Infos = struct {
    name: []const u8,
    version: ?[]const u8,
};

const TraceValue = enum { off, messages, verbose };

const WorkspaceFolder = struct {
    uri: []const u8,
    name: []const u8,
};

pub const Params = struct {
    /// The process Id of the parent process that started the server. Is null if
    /// the process has not been started by another process. If the parent
    /// process is not alive then the server should exit (see exit notification)
    /// its process.
    processId: ?i32 = null,

    /// Information about the client
    ///
    /// @since 3.15.0
    clientInfo: ?Infos = null,

    /// The locale the client is currently showing the user interface
    /// in. This must not necessarily be the locale of the operating
    /// system.
    ///
    /// Uses IETF language tags as the value's syntax
    /// (See https://en.wikipedia.org/wiki/IETF_language_tag)
    ///
    /// @since 3.16.0
    locale: ?[]const u8 = null,

    /// The rootPath of the workspace. Is null
    /// if no folder is open.
    ///
    /// @deprecated in favour of `rootUri`.
    rootPath: ?[]const u8 = null,

    /// The rootUri of the workspace. Is null if no
    /// folder is open. If both `rootPath` and `rootUri` are set
    /// `rootUri` wins.
    ///
    /// @deprecated in favour of `workspaceFolders`
    rootUri: ?[]const u8 = null,

    /// User provided initialization options.
    initializationOptions: ?std.json.Value = null,

    /// The capabilities provided by the client (editor or tool)
    capabilities: ClientCapabilities,

    /// The initial trace setting. If omitted trace is disabled ('off').
    trace: ?TraceValue = null,

    /// The workspace folders configured in the client when the server starts.
    /// This property is only available if the client supports workspace folders.
    /// It can be `null` if the client supports workspace folders but none are
    /// configured.
    ///
    /// @since 3.6.0
    workspaceFolders: ?[]WorkspaceFolder = null,
};

pub const Result = struct {
    /// The capabilities the language server provides.
    capabilities: ServerCapabilities,

    /// Information about the server.
    ///
    /// @since 3.15.0
    serverInfo: ?Infos = null,
};
