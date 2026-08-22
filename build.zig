const std = @import("std");

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    // Standard target options allow the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(
        .{ .preferred_optimize_mode = .Debug },
    );
    // It's also possible to define more custom flags to toggle optional features
    // of this build script using `b.option()`. All defined flags (including
    // target and optimize options) will be listed when running `zig build --help`
    // in this directory.

    // This creates a module, which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Zig modules are the preferred way of making Zig code available to consumers.
    // addModule defines a module that we intend to make available for importing
    // to our consumers. We must give it a name because a Zig package can expose
    // multiple modules and consumers will need to be able to specify which
    // module they want to access.
    const mod = b.addModule(
        "zinit",
        .{
            // The root source file is the "entry point" of this module. Users of
            // this module will only be able to access public declarations contained
            // in this file, which means that if you have declarations that you
            // intend to expose to consumers that were defined in other files part
            // of this module, you will have to make sure to re-export them from
            // the root file.
            .root_source_file = b.path("src/main.zig"),
            // Later on we'll use this module as the root module of a test executable
            // which requires us to specify a target.
            .target = target,
            .optimize = optimize,
        },
    );

    // Here we define an executable. An executable needs to have a root module
    // which needs to expose a `main` function. While we could add a main function
    // to the module defined above, it's sometimes preferable to split business
    // logic and the CLI into two separate modules.
    //
    // If your goal is to create a Zig library for others to use, consider if
    // it might benefit from also exposing a CLI tool. A parser library for a
    // data serialization format could also bundle a CLI syntax checker, for example.
    //
    // If instead your goal is to create an executable, consider if users might
    // be interested in also being able to embed the core functionality of your
    // program in their own executable in order to avoid the overhead involved in
    // subprocessing your CLI tool.
    //
    // If neither case applies to you, feel free to delete the declaration you
    // don't need and to put everything under a single module.
    const exe = b.addExecutable(
        .{ .name = "zinit", .root_module = mod },
    );

    // This declares intent for the executable to be installed into the
    // install prefix when running `zig build` (i.e. when executing the default
    // step). By default the install prefix is `zig-out/` but can be overridden
    // by passing `--prefix` or `-p`.
    b.installArtifact(exe);
}

///
/// Uses to crosscompile binary without debug information (?ReleaseFast)
/// and correct filled metadata
///
/// TODO: replace version struct to the defined version in the .zon manifest
///
fn buildRelease(b: *std.Build) void {
    // Prepare Windows x86-64 output target (object generation).
    const coff_target = b.resolveTargetQuery(
        .{
            .abi = .msvc,
            .ofmt = .coff,
            .os_tag = .windows,
            .cpu_arch = .x86_64,
        },
    );
    // Prepare Linux x86-64 output target. (If you want -> make it for your CPU architecture)
    const elf_target = b.resolveTargetQuery(
        .{
            .abi = .itanium,
            .ofmt = .elf,
            .os_tag = .linux,
            .cpu_model = .native,
        },
    );
    // Make ARM object instead of Intel.
    const macho_target = b.resolveTargetQuery(
        .{
            .ofmt = .macho,
            .os_tag = .macos,
            .cpu_arch = .aarch64,
        },
    );

    const coff_mod = b.addModule(
        "zinit",
        .{
            // The root source file is the "entry point" of this module. Users of
            // this module will only be able to access public declarations contained
            // in this file, which means that if you have declarations that you
            // intend to expose to consumers that were defined in other files part
            // of this module, you will have to make sure to re-export them from
            // the root file.
            .root_source_file = b.path("src/main.zig"),
            // Later on we'll use this module as the root module of a test executable
            // which requires us to specify a target.
            .target = coff_target,
            .link_libc = false,
            .link_libcpp = false,
        },
    );
    const elf_mod = b.addModule(
        "zinit",
        .{
            .root_source_file = b.path("src/main.zig"),
            .target = elf_target,
            .optimize = b.standardOptimizeOption(
                .{ .preferred_optimize_mode = .ReleaseFast },
            ),
            .link_libc = false,
            .link_libcpp = false,
        },
    );

    const macho_mod = b.addModule(
        "zinit",
        .{
            .root_source_file = b.path("src/main.zig"),
            .target = macho_target,
            .optimize = b.standardOptimizeOption(
                .{ .preferred_optimize_mode = .ReleaseFast },
            ),
            .link_libc = false,
            .link_libcpp = false,
        },
    );

    const pe64 = b.addExecutable(
        .{
            .name = "zinit",
            .root_module = coff_mod,
            .linkage = .dynamic,
            .version = .{ .major = 0, .minor = 16 },
        },
    );

    const elf64 = b.addExecutable(
        .{
            .name = "zinit",
            .root_module = elf_mod,
            .linkage = .dynamic,
            .version = .{ .major = 0, .minor = 16 },
        },
    );

    const macho = b.addExecutable(
        .{
            .name = "zinit",
            .root_module = macho_mod,
            .linkage = .dynamic,
            .version = .{ .major = 0, .minor = 16 },
        },
    );
    // Produce toxit waste
    b.installArtifact(pe64);
    b.installArtifact(elf64);
    b.installArtifact(macho);
}

fn assocWindows(
    b: *std.Build,
    command: enum { enabled, disabled },
) void {
    // Associate compiled win32 binary with "zinit"
    switch (command) {
        .enabled => {
            // Better to use batch commands instead of Powershell
            // But anyway I can set alias to the output file
            // b.run(&{ "Set-Alias" });
        },
        .disabled => {},
    }
    _ = b;
}

fn assocLinux(
    b: *std.Build,
    command: enum { enabled, disabled },
) void {
    // .enabled -> Move compiled binary to /usr/bin catalog
    _ = b;
    _ = command;

    // .disabled -> Remove compiled binary from /usr/bin catalog.
}
