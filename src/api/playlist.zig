const std = @import("std");
const common = @import("common.zig");

const reqwest = @import("../request.zig");
const SpotifyClient = @import("../api.zig").SpotifyClient;
const unwrap = @import("../api.zig").unwrap;
const Result = common.Result;
const Paginated = common.Paginated;

const ExternalUrls = @import("common.zig").ExternalUrls;
const Image = @import("common.zig").Image;
const Owner = @import("common.zig").Owner;

pub const PlaylistApi = struct {
    /// Get a user's playlists.
    ///
    /// If the user id is not provided then it is assumed to be the current user.
    ///
    /// Caller is responsible for freeing allocated memory
    pub fn playlists(self: *@This(), allocator: std.mem.Allocator, user_id: ?[]const u8, limit: ?u8, offset: ?usize) !Result(Paginated(SimplifiedPlaylist)) {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        const base = if (user_id) |u|
            try std.fmt.allocPrint(arena.allocator(), "https://api.spotify.com/v1/users/{s}/playlists", .{ u })
        else
            "https://api.spotify.com/v1/me/playlists";

        var request = try reqwest.Request.get(arena.allocator(), base, &.{});
        try request.bearerAuth(self.oauth.token.?.access);
        if (limit) |u| try request.param("limit", u);
        if (offset) |u| try request.param("offset", u);

        var response = try request.send(arena.allocator());
        try unwrap(arena.allocator(), &response);

        const body = try response.body(arena.allocator());
        return try .fromJsonLeaky(allocator, body);
    }
};

pub const Tracks = struct {
    total: usize,
    href: []const u8,
};

pub const SimplifiedPlaylist = struct {
    collaborative: bool,
    public: bool,
    description: []const u8,
    href: []const u8,
    id: []const u8,
    name: []const u8,
    snapshot_id: []const u8,
    uri: []const u8,
    external_urls: ExternalUrls,
    owner: Owner,
    tracks: Tracks,
    images: ?[]Image = null,
};
