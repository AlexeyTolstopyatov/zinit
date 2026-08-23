# `zinit`

`zinit` is a little command for making zig project templates and usage of 
This is a a short for `mkdir <name>; zig init` which works pretty simple.

No more huge default template by the `zig init`. Configure your zig project to templates
which you will certainly use.

### Quick start with `Release`

Download binary and run it with super user rights.

```ps1
# Run it on UNIX-like operating systems
sh-3.2# zinit assoc set
# Or powershell if you run it on Windows 
PS D:\...#> sudo ./zinit assoc set
```

`zinit` makes a system alias for itself and create a special directory for
a templates. 

> [!TIP]
> If you're using Windows you must logout or do anything what sends the 
> Win32 `WM_SETTINGCHANGE` signal and updates your environment.

### Quick start with sources

1. Download/Fork repository 
2. Change directory to the zinit source root
3. Build it

```ps1
PS D:\..#> zig build; sudo ./zig-out/bin/zinit assoc set
```

4. Run it.

### Template rules

Template structure is a simple directory `(d---/---)` with nested files.
Files in the directory checks only if extension of them are equals .zig/.zon.
Markdown/asciidoc files and other information will be ignored.
C source bindings in the project will be ignored.

```
Directory layout:
/mini-pkg
    /src
        main.zig
        root.zig
    build.zig
    builf.zig.zon
```

Also the `main.zig` layout looks like

```zig
const std = @import("std");
const @"?" = @import("root.zig");

pub fn main(init: std.process.init) !void {
    const argv = &init.minimal.args.toSlice();
    // Don't even think about it, write it all yourself!
}

test "use your mind" {
    // Write tests yourself too.
}
```

Zig files contains `@"?"` strings. The `project_name` will be placed in the file
instead of incoming question string.

The `.zon` files magic word is a question character (a.k.a. `?`).
It will be replaced by `project_name` too.

build.zig.zon layout:

```zig
.{
    .name = .?,
    .paths = .{
        "build.zig",
        "build.zig.zon",
            "src",
        // For example...
        //"LICENSE",
        //"README.md",
    },
}
```

# License

Licensed under MIT.