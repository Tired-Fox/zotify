const std = @import("std");
const print = std.debug.print;

const zotify = @import("zotify");
const OAuth = zotify.OAuth;

const CONTENT: []const u8 = @embedFile("redirect.html");

pub fn main() !void {
    // Create a general purpose allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();

    var oauth = try OAuth.initEnv(gpa.allocator(), .pkce, .{
        .cache_path = "zotify/token.json",
        .redirect_content = CONTENT,
        .scopes = .{
            .user_read_playback_state = true,
            .user_modify_playback_state = true,
        }
    });
    defer oauth.deinit();

    try oauth.refresh();
}
