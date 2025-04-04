const std = @import("std");
const print = std.debug.print;

const zotify = @import("zotify");
const OAuth = zotify.OAuth;
const SpotifyClient = zotify.SpotifyClient;

const CONTENT: []const u8 = @embedFile("redirect.html");

pub fn main() !void {
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

    const result = try client.addItemsToPlaylist(allocator, "6623xVunk1Ncm6nARsjfbU", &.{ .track("6G5txxoH2XisBaMRO6bX2z"), .episode("3cj0tkEQT6BoncBPiluAaW") }, 0);
    result.deinit();

    // https://open.spotify.com/playlist/37i9dQZF1EIhJY1EuDgoyf?si=tm-wMX9ZSVmxCFrCPYS35w
    // var items = try client.userPlaylists(allocator, null, 50, 0);
    // defer items.deinit();
    //
    // for (items.value.items, 0..) |item, i| {
    //     std.debug.print("{d}. {s} {s}\n", .{i, item.id, item.name});
    // }
    //
    // while (items.value.offset + items.value.limit < items.value.total) {
    //     const limit = items.value.limit;
    //     const offset = items.value.offset + limit;
    //     items.deinit();
    //
    //     items = try client.userPlaylists(allocator, null, limit, offset);
    //     for (items.value.items, items.value.offset..) |item, i| {
    //         std.debug.print("{d}. {s} {s}\n", .{i, item.id, item.name});
    //     }
    // }
    // try std.json.stringify(items.value, .{ .whitespace = .indent_2 }, std.io.getStdOut().writer());
}
