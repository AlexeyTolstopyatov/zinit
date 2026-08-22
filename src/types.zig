//! 
//! Types file includes everywhere in the project.
//! Contains redefinitions and custom error/command types
//! for the zinit.
//!
const std = @import("std");

pub const string = []const u8;
///
/// Identifies the verb the user typed. Used both as the command string and
/// as the tag type of `api.Argument`.
///
pub const Command = enum {
    ///
    /// $ zinit <name> <template> [!|--here] - make a new project.
    ///
    Init,
    ///
    /// $ zinit path [<path>] - print or set the templates location.
    ///
    Location,
    ///
    /// $ zinit list - list the available templates.
    ///
    List,
    ///
    /// $ zinit help - print the header comment
    ///
    Help,
    /// 
    /// $zinit assoc [set|reset]
    /// 
    Associate
};
///
/// Base arguments parser errors.
/// Uses in src/api.zig
///
pub const ParseError = error{ BadName, BadLocation, BadCommand };
pub const ExecError = error{ 
    OSNotSupported,
    RootRightsRequired,
    BadMemoryManagement,
    ProcessWasFailed
};
///
/// Threaded through every command handler so they don't each take a handful
/// of loose parameters. `main` builds one of these and hands it to `run`.
///
pub const Ctx = struct {
    /// The result of `std.process.Init.io` from `main`.
    io: std.Io,
    /// Arena allocator, valid for the whole process; no `deinit` needed.
    alloc: std.mem.Allocator,
    /// Where the tool writes its output.
    out: *std.Io.Writer,
    environ_map: *std.process.Environ.Map,
};

