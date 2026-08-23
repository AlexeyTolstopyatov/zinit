//!
//! Types file includes everywhere in the project.
//! Contains redefinitions and custom error/command types
//! for the zinit.
//!
const std = @import("std");

pub const string = []const u8;
///
/// Base arguments parser errors.
/// Uses in src/api.zig
///
pub const ParseError = error{ 
    BadName, 
    BadLocation, 
    BadCommand 
};
pub const ExecError = error{
    OSNotSupported,
    RootRightsRequired,
    BadMemoryManagement,
    ProcessWasFailed,
};
///
/// Threaded through every command handler so they don't each take a handful
/// of loose parameters. `main` builds one of these and hands it to `run`.
///
pub const AppContext = struct {
    /// The result of `std.process.Init.io` from `main`.
    io: std.Io,
    /// Arena allocator, valid for the whole process; no `deinit` needed.
    alloc: std.mem.Allocator,
    /// Where the tool writes its output.
    stdout: *std.Io.Writer,
    environment: *std.process.Environ.Map,
};
