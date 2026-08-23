//!
//! The os.zig module presents a little API to make an alias
//! for the current binary.
//!
const std = @import("std");
const core = @import("builtin");
const windows = @import("std").os.windows;

const string = @import("types.zig").string;
const Ctx = @import("types.zig").Ctx;
const ExecError = @import("types.zig").ExecError;
const HWND = @import("std").os.windows.HWND;

const HWND_BROADCAST = @as(HWND, @ptrFromInt(0xFFFF));
const WM_SETTINGCHANGE = 0x001A;
const SMTO_ABORTIFHUNG = 0x0002;
const ENVIRONMENT = "Environment";

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
pub fn setPath(ctx: *Ctx) !void {
    const alloc = ctx.alloc;
    const target = try std.process.executableDirPathAlloc(
        ctx.io,
        ctx.alloc,
    );
    defer alloc.free(target);

    const current_path = ctx.environ_map.get("PATH")
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

    try ctx.out.print(
        "Sucess. Restart a session to apply changes?\n",
        .{},
    );
}
pub fn resetPath(ctx: *Ctx) !void {
    const alloc = ctx.alloc;
    const target = try std.process.executableDirPathAlloc(
        ctx.io,
        ctx.alloc,
    );
    defer alloc.free(target);

    const current_path = ctx.environ_map.get("PATH") orelse {
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
    try ctx.out.print("Success. Restart a session.\n", .{});
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
