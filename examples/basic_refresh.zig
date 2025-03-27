const std = @import("std");
const print = std.debug.print;

const zotify = @import("zotify");
const OAuth = zotify.OAuth;
const SpotifyClient = zotify.SpotifyClient;

const CONTENT: []const u8 = @embedFile("redirect.html");

pub fn main() !void {
    // Create a general purpose allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = SpotifyClient {
        .allocator = allocator,
        .oauth = try OAuth.initEnv(allocator, .pkce, .{
            .cache_path = "zotify/token.json",
            .redirect_content = CONTENT,
            .scopes = .{
                .user_read_playback_state = true,
                .user_modify_playback_state = true,
            }
        })
    };
    defer client.deinit();

    try client.addItemToQueue(.{ .type = .track, .uri = "6EdnztPkhHINbu8Y9NgIIR" }, null);
}
