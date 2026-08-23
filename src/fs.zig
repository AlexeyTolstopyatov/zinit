//!
//! CoffeeLake (C) 2026-*
//!
//! Filesystem module is used to resolve the templates location and expanding
//! a template directory into a project.
//!
//! Template structure is a simple directory (d---/---) with nested files.
//! Files in the directory checks only if extension of them are equals .zig/.zon.
//! Markdown/asciidoc files and other information will be ignored.
//! C source bindings in the project will be ignored.
//!
//! Directory layout:
//! /mini-pkg
//!     /src
//!         main.zig
//!         root.zig
//!     build.zig
//!     builf.zig.zon
//!
//! main.zig layout:
//!
//! ```zig
//! const std = @import("std");
//! const @"?" = @import("root.zig");
//!
//! pub fn main(init: std.process.init) !void {
//!     const argv = &init.minimal.args.toSlice();
//!     // Don't even think about it, write it all yourself!
//! }
//!
//! test "use your mind" {
//!     // Write tests yourself too.
//! }
//! ```
//!
//! Zig files contains [@"?"] strings. The [project_name] will be placed in the file
//! instead of incoming question string.
//!
//! The Zig Object Notation (??) files magic word is [.?].
//! It will be replaced by [project_name] too.
//!
//! build.zig.zon layout:
//! ```zon
//! .{
//!     .name = .?,
//!     .paths = .{
//!         "build.zig",
//!         "build.zig.zon",
//!         "src",
//!         // For example...
//!         //"LICENSE",
//!         //"README.md",
//!    },
//! }
//! ```
//!
//! [zinit] doesn't work with any kind of archives. (@v0.16.)
//!

const std = @import("std");

const string = @import("types.zig").string;
const Ctx = @import("types.zig").Ctx;

///
/// Sub-directory (inside the executable's directory) that holds the templates:
/// `%app%/templates` from the help text.
///
pub const templates_dir_name: string = "templates";

/// The one special string replaced inside `.zig` files with the project name.
pub const ZIG_QUESTION: string = "@\"?\"";
pub const ZON_QUESTION: string = ".?";

/// Default templates location: `<dir of the executable>/templates`.
pub fn defaultTemplatesDir(ctx: *Ctx) ![]u8 {
    const exe_dir = try std.process.executableDirPathAlloc(
        ctx.io,
        ctx.alloc,
    );
    return std.fs.path.join(
        ctx.alloc,
        &.{ exe_dir, templates_dir_name },
    );
}

///
/// Replaces every `template_marker` in `content` with `name`.
/// Returns the original slice unchanged when there is nothing to replace!
///
fn replaceQuestion(
    content: string,
    name: string,
    alloc: std.mem.Allocator,
    question: string,
) !string {
    if (std.mem.indexOf(u8, content, question) == null)
        return content;

    var buf: std.ArrayList(u8) = .empty;
    var start: usize = 0;
    while (
        std.mem.indexOfPos(u8, content, start, ZIG_QUESTION)
    ) |at| {
        try buf.appendSlice(alloc, content[start..at]);
        try buf.appendSlice(alloc, name);
        start = at + ZIG_QUESTION.len;
    }
    try buf.appendSlice(alloc, content[start..]);
    return buf.items;
}

/// Copies a single `.zig` file from the template into the destination,
/// substituting markers in its contents.
fn copyFile(
    ctx: *Ctx,
    src_dir: std.Io.Dir,
    src_path: string,
    dst_dir: std.Io.Dir,
    name: string,
    question: string,
) !void {
    const zig_bytes: string = try src_dir.readFileAlloc(
        ctx.io,
        src_path,
        ctx.alloc,
        .unlimited,
    );
    const proceed_bytes: string = try replaceQuestion(
        zig_bytes,
        name,
        ctx.alloc,
        question,
    );

    var file = try dst_dir.createFile(
        ctx.io,
        src_path,
        .{ .truncate = true },
    );
    defer file.close(ctx.io);

    // The file was just created (truncated), so writing starts at offset 0.
    try file.writePositionalAll(ctx.io, proceed_bytes, 0);
}

///
/// Turns a template into a project.
/// Depending on a [here] flag the project directory will be moved
/// into current working directory (=true) or firstly the project directory
/// will be made then template containment will be copied into. (=false)
///
/// Inside every copied `.zig` file the marker `@"?"` is replaced with `name`.
///
pub fn makeProject(
    ctx: *Ctx,
    name: string,
    template: string,
    here: bool,
) !void {
    const templates_path = try std.fs.path.join(
        ctx.alloc,
        &.{ try defaultTemplatesDir(ctx), template },
    );

    var tdir = try std.Io.Dir.cwd()
        .openDir(ctx.io, templates_path, .{ .iterate = true });
    defer tdir.close(ctx.io);

    var dst_dir: std.Io.Dir = undefined;
    var owns_dst = false;
    if (here) {
        dst_dir = std.Io.Dir.cwd();
    } else {
        try std.Io.Dir.cwd().createDirPath(ctx.io, name);
        dst_dir = try std.Io.Dir.cwd()
            .openDir(
                ctx.io,
                name,
                .{ .access_sub_paths = true },
            );
        owns_dst = true;
    }
    defer if (owns_dst) dst_dir.close(ctx.io);

    var walker = try tdir.walk(ctx.alloc);
    defer walker.deinit();

    var files: usize = 0;
    while (try walker.next(ctx.io)) |entry| {
        switch (entry.kind) {
            .directory => try dst_dir.createDirPath(
                ctx.io,
                entry.path,
            ),
            .file => {
                if (std.mem.endsWith(u8, entry.path, ".zig")) {
                    try copyFile(
                        ctx,
                        tdir,
                        entry.path,
                        dst_dir,
                        name,
                        ZIG_QUESTION,
                    );
                } else if (
                    std.mem.endsWith(u8, entry.path, ".zon")
                ) {
                    try copyFile(
                        ctx,
                        tdir,
                        entry.path,
                        dst_dir,
                        name,
                        ZON_QUESTION,
                    );
                } else {
                    try std.Io.Dir.copyFile(
                        tdir,
                        entry.path,
                        dst_dir,
                        entry.path,
                        ctx.io,
                        .{ .make_path = true, .replace = true },
                    );
                }
                files += 1;
            },
            else => {}, // symlinks and other special entries are skipped
        }
    }

    if (here) {
        try ctx.out.print(
            "Created '{s}' in the current directory ({d} files)\n",
            .{ name, files },
        );
    } else {
        try ctx.out.print(
            "Created './{s}' ({d} files)\n",
            .{ name, files },
        );
    }
}
