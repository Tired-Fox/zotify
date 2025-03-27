# Zotify

A zig based spotify api

# Installation

```
zig fetch --save git+https://github.com/Tired-Fox/zotify#{commit,branch,tag}
```

```zig
// build.zig

pub fn build(b: *std.build) void {
  const zotify = b.dependency("zotify", .{}).module("zotify")

  const exe_mod = b.createmodule(.{
      .root_source_file = b.path("src/main.zig"),
      .target = target,
      .optimize = optimize,
  });

  exe_mode.addimport("zotify", zotify);
}
```

> Youtube Music API:
> Reference: https://github.com/sigma67/ytmusicapi
