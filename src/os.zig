//!
//! The os.zig module presents a little API to make an alias
//! for the current binary.
//!
//! "Call zinit from anywhere in the terminal" simply means: make the folder
//! that holds zinit.exe (and its templates/) reachable through `PATH`.
//!
//! We never touch system folders (/usr/bin, System32, Program Files) and never
//! require administrator rights: everything stays inside the current user's own
//! environment (the `Path` value of `HKCU\Environment` on Windows).
//!
const std = @import("std");
const core = @import("builtin");

const string = @import("types.zig").string;
const Ctx = @import("types.zig").Ctx;
const ExecError = @import("types.zig").ExecError;

///
/// Adds the directory that contains the running zinit binary (and therefore
/// its templates/) to the PATH of the current user.
///
pub fn enableAssoc(ctx: *Ctx) !void {
    switch (core.os.tag) {
        .windows => try setPath(ctx),
        else => return ExecError.OSNotSupported,
    }
}

///
/// Removes the directory that contains the running zinit binary from the
/// PATH of the current user.
///
pub fn disableAssoc(ctx: *Ctx) !void {
    switch (core.os.tag) {
        .windows => try resetPath(ctx),
        else => return ExecError.OSNotSupported,
    }
}

/// 
/// [Windows]
/// Updates a Win32 exvironment variable %PATH% 
/// 
pub fn setPath (ctx: *Ctx) !void {
    const path: string = ctx.environ_map.get("Path") orelse {
        return ExecError.ProcessWasFailed;
    };

    try ctx.out.print("{s}\n\n", .{path});

    const target: string = try std.process.executablePathAlloc(ctx.io, ctx.alloc);
    const updated_path: string = try std.fmt.allocPrint(ctx.alloc, ";{s};{s}", .{path, target});

    const proc = try std.process.run(
        ctx.alloc, ctx.io, .{
            .argv = &.{
                "setx", "PATH", updated_path, "/M"
            },
        }
    );
    
    if (proc.term.exited != 0) {
        try ctx.out.print("Environment is not updated.\n", .{});
        return ExecError.ProcessWasFailed;
    }
    
    try ctx.out.print("Environment is updated!\n", .{});
    try ctx.out.print("Please restart a terminal session to apply changes.\n", .{});
}

pub fn resetPath(ctx: *Ctx) !void {
    const target: string = try std.process.executableDirPathAlloc(ctx.io, ctx.alloc);
    try ctx.out.print("{s}\n", .{target});
    
    const path = ctx.environ_map.get("Path") orelse return ExecError.ProcessWasFailed;

    const setx = try std.process.run(ctx.alloc, ctx.io, .{
        .argv = &.{
            "setx", "Path", path, "/M"
        }
    });

    if (setx.term.exited != 0) {
        try ctx.out.print("Environment is not updated.\n", .{});
        return ExecError.ProcessWasFailed;
    }
    try ctx.out.print("Environment is updated.\n", .{});
}

fn removeFirstPattern(allocator: std.mem.Allocator, data: string, pattern: string) ![]u8 {
    const pos = std.mem.indexOf(u8, data, pattern) orelse {
        return try allocator.dupe(u8, data);
    };
    const result = try allocator.alloc(u8, data.len - pattern.len);
    
    @memcpy(result[0..pos], data[0..pos]);
    @memcpy(result[pos..], data[pos+pattern.len..]);

    return result;
}