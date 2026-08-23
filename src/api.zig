//!
//! Command handling: turns the raw command line into a typed [Argument]
//! and handles to the action each verb requests.
//!

const this = @This();
const std = @import("std");
const os = @import("os.zig");
const fs = @import("fs.zig");

const string = @import("types.zig").string;
const ParseError = @import("types.zig").ParseError;
const AppContext = @import("types.zig").AppContext;
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
    Associate,
};

pub const Argument = union(Command) {
    ///
    /// $zinit <name> <template> [!|--here]
    ///
    Init: struct { name: string, template: string, here: bool },
    ///
    /// $zinit path [<path>]; `null` means "print the current location".
    ///
    Location: ?string,
    ///
    /// $zinit list
    ///
    List: void,
    ///
    /// $zinit help
    ///
    Help: void,
    ///
    /// $zinit assoc [set|reset]
    ///
    Associate: bool,
};

///
/// Reserved DOS device names.
///
const dos_aliases = [_][]const u8{
    "con",
    "aux",
    "nul",
    "prn",
    "com",
    "lpt",
};

/// Bytes that may never appear inside a path element on Windows.
const bad_chars = [_]u8{
    0x00, //  NUL
    0x0D, //  CR
    0x22, // "
    0x2A, // *
    0x2F, // /
    0x3A, // :
    0x3C, // <
    0x3E, // >
    0x3F, // ?
    0x5C, // \
    0x7C, // |
};

///
/// Returns the part of a name that matters for the DOS-device check:
/// everything up to the first dot, trimmed of trailing dots and spaces
/// (so "COM1.txt" and "CON .txt" are treated as "COM1" and "CON").
///
/// Applies to folders/files
///
fn trimExtension(name: string) string {
    var end = (std.mem.indexOfScalar(u8, name, '.')
        orelse name.len);
    while (
        end > 0
            and (name[end - 1] == '.' or name[end - 1] == ' ')
    ) {
        end -= 1;
    }
    return name[0..end];
}

///
/// True when a project name collides with a DOS device name.
///
pub fn isDosDevice(name: string) bool {
    const stem = trimExtension(name);
    for (dos_aliases) |alias| {
        if (stem.len < alias.len) continue;
        if (!std.ascii.eqlIgnoreCase(stem[0..alias.len], alias))
            continue;
        const rest = stem[alias.len..];
        return rest.len == 0
            or (rest.len == 1 and std.ascii.isDigit(rest[0]));
    }
    return false;
}

///
/// Validates a project name against the file-system rules.
///
pub fn validateName(name: string) ParseError!void {
    if (name.len == 0) return error.BadName;
    if (isDosDevice(name)) return error.BadName;
    // A name with a reserved byte or '?', '*', ':' etc. has no chance of
    // becoming a valid directory (and would break our '?' substitution).
    for (bad_chars) |byte| {
        if (std.mem.indexOfScalar(u8, name, byte) != null)
            return error.BadName;
    }
}

///
/// Parses the command line (verb and everything after it, program name
/// already stripped) into an `Argument`. One token is enough to disambiguate:
/// the reserved verbs dispatch to their own tag, every other first token is
/// the implicit project name of an `Init`.
///
pub fn parseArgv(argv: []const string) ParseError!Argument {
    if (argv.len == 0) return error.BadCommand;

    const verb = argv[0];

    if (std.mem.eql(u8, verb, "list")) {
        return .{ .List = {} };
    }
    if (std.mem.eql(u8, verb, "help")) {
        return .{ .Help = {} };
    }
    if (std.mem.eql(u8, verb, "path")) {
        return .{
            .Location = if (argv.len >= 2) argv[1] else null,
        };
    }
    if (std.mem.eql(u8, "assoc", verb)) {
        if (std.mem.eql(u8, "set", argv[1])) {
            return .{ .Associate = true };
        } else if (std.mem.eql(u8, "reset", argv[1])) {
            return .{ .Associate = false };
        } else {
            return ParseError.BadCommand;
        }
    }
    // $zinit <name> <template> [!|--here]
    if (argv.len < 2) return error.BadCommand;

    const here = argv.len >= 3
        and (std.mem.eql(u8, argv[2], "!")
            or std.mem.eql(u8, argv[2], "--here"));

    try validateName(argv[0]);

    return .{
        .Init = .{
            .name = argv[0],
            .template = argv[1],
            .here = here,
        },
    };
}

///
/// Executes whatever the tagged union describes. Because [Argument] is a
/// tagged union over [Command], the compiler forces us to handle every verb.
/// Runtime failures use the wider `anyerror` set (I/O, allocator, ...) while
/// `parseArgv` keeps reporting only `ParseError`.
///
pub fn run(args: Argument, ctx: *AppContext) !void {
    switch (args) {
        .Init => |init| {
            try validateName(init.name);
            try validateName(init.template);
            try fs.makeProject(
                ctx,
                init.name,
                init.template,
                init.here,
            );
        },
        .Location => |maybe_path| {
            if (maybe_path) |path| {
                // TODO: persist `path` as the new templates location (config.zig).
                try ctx.stdout.print(
                    "Templates location set to {s} (not persisted yet)\n",
                    .{path},
                );
            } else {
                const dir = try fs.defaultTemplatesDir(ctx);
                try ctx.stdout.print("{s}\n", .{dir});
            }
        },
        .List => {
            try printTemplates(ctx);
        },
        .Help => {
            printHelp(ctx);
        },
        .Associate => |set| {
            try ctx.stdout.print("Associate: set={}\n", .{set});
            if (set) {
                try os.enableAssoc(ctx);
            } else {
                try os.disableAssoc(ctx);
            }
        },
    }
}

fn printHelp(ctx: *AppContext) void {
    // `@"?"` in the text below is the marker zinit substitutes.
    ctx.stdout.print(
        \\ zinit - make Zig projects from templates
        \\
        \\ $zinit <name> <template> [--here|!]
        \\     Creates ./<name> and copies the template's contents into it,
        \\     replacing `@"?"` with <name> inside every .zig file.
        \\
        \\     $zinit hello win32-console
        \\         -> makes ./hello from the win32-console template
        \\
        \\     $zinit hello win32-console !
        \\     $zinit hello win32-console --here
        \\         -> same, but into the current directory.
        \\
        \\ $zinit list
        \\     Lists the templates in the templates directory.
        \\
        \\ $zinit path
        \\     Print where templates are stored.
        \\
        \\ $zinit help
        \\     Print this message.
        \\
        \\ $zinit assoc [set|reset] (required superuser rights)
        \\     set   -> Install an alias for zinit.
        \\     reset -> Remove an alias.
        \\     
        \\     (Windows)
        \\     Calls process of [setx] with arguments to change current user
        \\     %PATH%. If last error not equal zero -> prints debug information
        \\     in the [stderr] stream. Sends message "Environment is not updated!"
        \\      
        \\     (macOS/Linux)
        \\     Creates/Removes a symbolic link       
        \\     
        ,
        .{},
    )
        catch unreachable;
}

fn printTemplates(ctx: *AppContext) !void {
    const dir = try fs.defaultTemplatesDir(ctx);

    var tdir = std.Io.Dir.cwd()
        .openDir(ctx.io, dir, .{ .iterate = true })
        catch |err| switch (err) {
            error.FileNotFound => {
                try ctx.stdout.print(
                    "No templates directory ({s}).\n",
                    .{dir},
                );
                return;
            },
            else => return err,
        };
    defer tdir.close(ctx.io);

    var walker = try tdir.walk(ctx.alloc);
    defer walker.deinit();

    try ctx.stdout.print("Templates in {s}:\n", .{dir});
    var count: usize = 0;
    while (try walker.next(ctx.io)) |entry| {
        // Templates live one level deep; deeper folders belong to a template.
        if (entry.kind == .directory and entry.depth() == 1) {
            try ctx.stdout.print("  {s}\n", .{entry.basename});
            count += 1;
        }
    }
    if (count == 0) try ctx.stdout.print("  (none)\n", .{});
}
