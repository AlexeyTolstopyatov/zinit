//!
//! CoffeeLake (C) 2026-*
//!
//! [zinit] is a little command for making zig project templates and usage of them
//! This is a a short for "mkdir <name>; zig init": works pretty simple.
//!
//! Usage:
//! $zinit <name> <template name> <!>
//!         The template name must be right for all file systems including Microsoft Windows
//!         naming issues (operation aborts for DOS devices, threads)
//!         Success: Create subdirectory or extract template container in the current directory
//!
//!         $zinit hello win32-console
//!             -> Makes new %cwd%/hello subdirectory
//!             -> Extracts "win32-console" template directory
//!             -> Iterates over all files replaces @"?" (special strings) to "hello"
//!
//!         $zinit hello win32-console !
//!         $zinit hello win32-console --here
//!             -> Extracts "win32-console" template directory
//!             -> Iterates over all files replaces @"?" (special strings) to "hello"
//!
//! $zinit list
//!         Show list of all templates in the templates directory
//!         Templates directory: [%app%/templates] set by default
//!
//! $zinit path <path>
//!         If path is missing -> print templates storage -> exit(0)
//!         For else set path (throw message if path is invalid) -> exit(0)
//!
//! $zinit help
//!         Print header comment of main.zig -> exit(0)
//!
//! $zinit assoc [set|reset]
//!         Set an alias of given zinit binary -> exit(0)
//!         Drop an alias of given zinit binary -> exit(0)
//!
const std = @import("std");

const api = @import("api.zig");
const Ctx = @import("types.zig").Ctx;

pub fn main(init: std.process.Init) !void {
    const words = try init.minimal.args.toSlice(
        init.arena.allocator(),
    );
    const arguments = words[1..];

    var stdbuf: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &stdbuf);

    var ctx: Ctx = .{ .io = init.io, .alloc = init.arena.allocator(), .out = &stdout.interface, .environ_map = init.environ_map };

    const argument = api.parseArgv(arguments) catch |err| {
        std.debug.print("zinit: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };

    api.run(argument, &ctx) catch |err| {
        std.debug.print("zinit: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };

    try stdout.flush();
}
