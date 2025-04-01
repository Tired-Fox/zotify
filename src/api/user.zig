const std = @import("std");
const common = @import("common.zig");
const reqwest = @import("../request.zig");

const SpotifyClient = @import("../api.zig").SpotifyClient;
const unwrap = @import("../api.zig").unwrap;
const Result = common.Result;
const Paginated = common.Paginated;
const Cursor = common.Cursor;

const Artist = @import("artist.zig").Artist;
const TimeRange = common.TimeRange;
const ExternalUrls = common.ExternalUrls;
const Followers = common.Followers;
const Image = common.Image;

pub const UserApi = struct {
    /// Get the current user's playback state
    ///
    /// Caller is responsible for freeing allocated memory
    pub fn profile(self: *SpotifyClient, allocator: std.mem.Allocator, user_id: ?[]const u8) !Result(Profile) {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        const base = if (user_id) |u|
            try std.fmt.allocPrint(allocator, "https://api.spotify.com/v1/users/{s}", .{ u })
        else
            "https://api.spotify.com/v1/me";

        var request = try reqwest.Request.get(arena.allocator(), base, &.{});
        try request.bearerAuth(self.oauth.token.?.access);

        var response = try request.send(arena.allocator());
        try unwrap(arena.allocator(), &response);

        const body = try response.body(arena.allocator());
        return try .fromJsonLeaky(allocator, body);
    }

    /// Get the current user's top items
    ///
    /// This will either get the top `artists` or top `tracks`.
    ///
    /// Caller is responsible for freeing allocated memory
    pub fn topItems(self: *SpotifyClient, comptime T: TopItemType, allocator: std.mem.Allocator, time_range: ?TimeRange, limit: ?u8, offset: ?usize) !Result(TopItems(T)) {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var request = try reqwest.Request.get(
            arena.allocator(),
            std.fmt.comptimePrint("https://api.spotify.com/v1/me/top/{s}", .{ @tagName(T) }),
            &.{}
        );
        try request.bearerAuth(self.oauth.token.?.access);

        if (time_range) |tr| try request.param("time_range", @tagName(tr));
        if (limit) |l| try request.param("limit", l);
        if (offset) |o| try request.param("offset", o);

        var response = try request.send(arena.allocator());
        try unwrap(arena.allocator(), &response);

        const body = try response.body(arena.allocator());
        return try .fromJsonLeaky(allocator, body);
    }

    /// Add the current user as a follower of a playlist
    pub fn followPlaylist(self: *SpotifyClient, playlist_id: []const u8, public: ?bool) !void {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        const base = try std.fmt.allocPrint(arena.allocator(), "https://api.spotify.com/v1/playlists/{s}/followers", .{ playlist_id });
        var request = try reqwest.Request.put(
            arena.allocator(),
            base,
            &.{}
        );
        try request.bearerAuth(self.oauth.token.?.access);

        try request.json(.{
            .public = public orelse true
        });

        var response = try request.send(arena.allocator());
        try unwrap(arena.allocator(), &response);
    }

    /// Remove the current user as a follower of a playlist
    pub fn unfollowPlaylist(self: *SpotifyClient, playlist_id: []const u8) !void {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        const base = try std.fmt.allocPrint(arena.allocator(), "https://api.spotify.com/v1/playlists/{s}/followers", .{ playlist_id });
        var request = try reqwest.Request.delete(
            arena.allocator(),
            base,
            &.{}
        );
        try request.bearerAuth(self.oauth.token.?.access);

        var response = try request.send(arena.allocator());
        try unwrap(arena.allocator(), &response);
    }

    /// Get the current user's followed artists
    pub fn following(self: *SpotifyClient, allocator: std.mem.Allocator, after: ?[]const u8, limit: ?u8) !Result(Cursor(Artist)) {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var request = try reqwest.Request.get(
            arena.allocator(),
            "https://api.spotify.com/v1/me/following",
            &.{}
        );
        try request.bearerAuth(self.oauth.token.?.access);

        try request.param("type", "artist");
        if (after) |a| try request.param("after", a);
        if (limit) |l| try request.param("limit", l);

        var response = try request.send(arena.allocator());
        try unwrap(arena.allocator(), &response);

        const body = try response.body(arena.allocator());
        return try .fromWrappedJsonLeaky(.artists, allocator, body);
    }

    /// Add the current user as a follower of one or more artists or spotify users
    pub fn follow(self: *SpotifyClient, T: enum { artist, user }, ids: []const []const u8) !void {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var request = try reqwest.Request.put(
            arena.allocator(),
            "https://api.spotify.com/v1/me/following",
            &.{}
        );
        try request.bearerAuth(self.oauth.token.?.access);
        try request.param("type", @tagName(T));

        try request.json(.{
            .ids = ids
        });

        var response = try request.send(arena.allocator());
        try unwrap(arena.allocator(), &response);
    }

    /// Remove the current user as a follower of one or more artists or spotify users
    pub fn unfollow(self: *SpotifyClient, T: enum { artist, user }, ids: []const []const u8) !void {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var request = try reqwest.Request.delete(
            arena.allocator(),
            "https://api.spotify.com/v1/me/following",
            &.{}
        );
        try request.bearerAuth(self.oauth.token.?.access);
        try request.param("type", @tagName(T));
        try request.param("ids", ids);

        var response = try request.send(arena.allocator());
        try unwrap(arena.allocator(), &response);
    }

    /// Check if the current user is following one or move artists or spotify users
    pub fn checkFollow(self: *SpotifyClient, allocator: std.mem.Allocator, T: enum { artist, user }, ids: []const []const u8) !Result([]const bool) {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var request = try reqwest.Request.get(
            arena.allocator(),
            "https://api.spotify.com/v1/me/following/contains",
            &.{}
        );
        try request.bearerAuth(self.oauth.token.?.access);
        try request.param("type", @tagName(T));
        try request.param("ids", ids);

        var response = try request.send(arena.allocator());
        try unwrap(arena.allocator(), &response);

        const body = try response.body(arena.allocator());
        return try .fromJsonLeaky(allocator, body);
    }

    /// Check if the current user is following one or move artists or spotify users
    pub fn checkFollowPlaylist(self: *SpotifyClient, playlist_id: []const u8) !bool {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        const base = try std.fmt.allocPrint(arena.allocator(), "https://api.spotify.com/v1/playlists/{s}/followers/contains", .{ playlist_id });
        var request = try reqwest.Request.get(
            arena.allocator(),
            base,
            &.{}
        );
        try request.bearerAuth(self.oauth.token.?.access);

        var response = try request.send(arena.allocator());
        try unwrap(arena.allocator(), &response);

        const body = try response.body(arena.allocator());
        const result = try std.json.parseFromSliceLeaky([]bool, arena.allocator(), body, .{ .ignore_unknown_fields = true });
        return result[0];
    }
};

pub const ExplicitContent = struct {
    filter_enabled: bool,
    filter_locked: bool,
};

pub const Profile = struct {
    display_name: ?[]const u8 = null,
    external_urls: ExternalUrls,
    followers: ?Followers = null,
    href: []const u8,
    id: []const u8,
    images: []Image,
    uri: []const u8,

    ///  scope: user-read-private
    country: ?[]const u8 = null,
    ///  scope: user-read-private
    explicit_content: ?ExplicitContent = null,
    ///  scope: user-read-private
    product: []const u8,

    /// scope: user-read-email
    email: ?[]const u8 = null,
};

pub const TopItemType = enum {
    artists,
    tracks,
};

pub fn TopItems(T: TopItemType) type {
    return Paginated(switch (T) {
        .artists => @import("artist.zig").Artist,
        .tracks => @import("track.zig").Track,
    });
}
