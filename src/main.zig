const std = @import("std");
const print = std.debug.print;

const zotify = @import("zotify");
const OAuth = zotify.OAuth;

pub fn main() !void {
    // Create a general purpose allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();

    var oauth = try OAuth.initEnv(gpa.allocator(), .pkce, .{ .cache_path = "zotify/token.json" });
    defer oauth.deinit();

    try oauth.refresh();
}
