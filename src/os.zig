//!
//! The os.zig module presents a little API to make an alias
//! for the current binary.
//!
const std = @import("std");
const core = @import("builtin");
const windows = @import("std").os.windows;
const fs = std.fs;

const string = @import("types.zig").string;
const AppContext = @import("types.zig").AppContext;
const ExecError = @import("types.zig").ExecError;
const HWND = @import("std").os.windows.HWND;

///
/// Adds the directory that contains the running zinit binary (and therefore
/// its templates/) to the PATH of the current user.
/// 
/// Also prepares application domain (makes /templates sub-directory)
///
pub fn enableAssoc(ctx: *AppContext) !void {
    switch (core.os.tag) {
        .windows => try setPath(ctx),
        .linux => try setSymlink(ctx),
        else => return ExecError.OSNotSupported,
    }

    // install templates dir
    const app_domain = try std.process.executableDirPathAlloc(ctx.io, ctx.alloc);
    const templates = try std.fs.path.join(ctx.alloc, &.{ app_domain, "templates" });
    defer ctx.alloc.free(app_domain);
    defer ctx.alloc.free(templates);
    
    try std.Io.Dir.createDirAbsolute(ctx.io, templates, .default_dir);
}

///
/// Removes the directory that contains the running zinit binary from the
/// PATH of the current user.
///
pub fn disableAssoc(ctx: *AppContext) !void {
    switch (core.os.tag) {
        .windows => try resetPath(ctx),
        else => return ExecError.OSNotSupported,
    }
}

///
/// [Windows]
/// Updates a Win32 exvironment variable %PATH%
///
pub fn setPath(ctx: *AppContext) !void {
    const alloc = ctx.alloc;
    const target = try std.process.executableDirPathAlloc(
        ctx.io,
        ctx.alloc,
    );
    defer alloc.free(target);

    const current_path = ctx.environment.get("PATH")
        orelse return ExecError.BadMemoryManagement;
    defer alloc.free(current_path);

    const new_path = try std.fmt.allocPrint(
        alloc,
        "{s};{s}",
        .{ current_path, target },
    );
    defer alloc.free(new_path);

    // reg add HKCU\Environment /v PATH /t REG_EXPAND_SZ /d "new_path" /f
    const result = try std.process.run(
        alloc,
        ctx.io,
        .{
            .argv = &.{
                "reg",
                "add",
                "HKCU\\Environment",
                "/v",
                "PATH",
                "/t",
                "REG_EXPAND_SZ",
                "/d",
                new_path,
                "/f",
            },
        },
    );
    // reg query HKCU\Environment /v PATH
    if (result.term.exited != 0) {
        std.debug.print("DEBUG: {s}\n", .{result.stderr});
        return ExecError.RootRightsRequired;
    }

    try ctx.stdout.print(
        "Sucess. Restart a session to apply changes?\n",
        .{},
    );
}

///
/// [macOS/Linux]
/// Creates symbolic link to /usr/local/bin of given application.
/// 
pub fn setSymlink(ctx: *AppContext) !void {
    _ = ctx;
    
}

pub fn resetPath(ctx: *AppContext) !void {
    const alloc = ctx.alloc;
    const target = try std.process.executableDirPathAlloc(
        ctx.io,
        ctx.alloc,
    );
    defer alloc.free(target);

    const current_path = ctx.environment.get("PATH") orelse {
        return ExecError.BadMemoryManagement;
    };

    const cleaned = try removeFirstPattern(
        alloc,
        current_path,
        target,
    );
    defer alloc.free(cleaned);

    const result = try std.process.run(
        alloc,
        ctx.io,
        .{
            .argv = &.{
                "reg",
                "add",
                "HKCU\\Environment",
                "/v",
                "PATH",
                "/t",
                "REG_EXPAND_SZ",
                "/d",
                cleaned,
                "/f",
            },
        },
    );
    if (result.term.exited != 0) {
        std.debug.print("DEBUG: {s}\n", .{result.stderr});
        return ExecError.RootRightsRequired;
    }
    try ctx.stdout.print("Success. Restart a session to apply changes!\n", .{});
}

fn removeFirstPattern(
    allocator: std.mem.Allocator,
    data: string,
    pattern: string,
) ![]u8 {
    const pos = std.mem.indexOf(u8, data, pattern) orelse {
        return try allocator.dupe(u8, data);
    };
    const result = try allocator.alloc(
        u8,
        data.len - pattern.len,
    );

    @memcpy(result[0..pos], data[0..pos]);
    @memcpy(result[pos..], data[pos + pattern.len..]);

    return result;
}
