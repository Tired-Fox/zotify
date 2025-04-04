const std = @import("std");
const common = @import("common.zig");

const reqwest = @import("../request.zig");
const SpotifyClient = @import("../api.zig").SpotifyClient;
const unwrap = @import("../api.zig").unwrap;
const Result = common.Result;
const Paginated = common.Paginated;
const AdditionalType = common.AdditionalType;
const Followers = common.Followers;
const Item = common.Item;

const ExternalUrls = @import("common.zig").ExternalUrls;
const Image = @import("common.zig").Image;
const Owner = @import("common.zig").Owner;

pub const PlaylistApi = struct {
    /// Get a playlist owned by a spotify user.
    ///
    /// Caller is responsible for freeing allocated memory
    pub fn playlist(self: *SpotifyClient, allocator: std.mem.Allocator, playlist_id: []const u8, market: ?[]const u8, additional_types: ?AdditionalType) !Result(Playlist) {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        const base = try std.fmt.allocPrint(arena.allocator(), "https://api.spotify.com/v1/playlists/{s}", .{ playlist_id });
        var request = try reqwest.Request.get(arena.allocator(), base, &.{});
        try request.bearerAuth(self.oauth.token.?.access);

        if (market) |m| try request.param("market", m);
        if (additional_types) |a| try request.param("additional_types", a);

        var response = try request.send(arena.allocator());
        try unwrap(arena.allocator(), &response, null);

        const body = try response.body(arena.allocator());
        return try .fromJsonLeaky(allocator, body);
    }

    /// Change the owned playlist's information
    pub fn modifyPlaylist(self: *SpotifyClient, playlist_id: []const u8, details: Details) !void {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        const base = try std.fmt.allocPrint(arena.allocator(), "https://api.spotify.com/v1/playlists/{s}", .{ playlist_id });
        var request = try reqwest.Request.put(arena.allocator(), base, &.{});
        try request.bearerAuth(self.oauth.token.?.access);

        try request.json(details);

        var response = try request.send(arena.allocator());
        try unwrap(arena.allocator(), &response, null);
    }

    /// Get full details of the items of a playlist owned by a Spotify user.
    pub fn playlistItems(
        self: *SpotifyClient,
        allocator: std.mem.Allocator,
        playlist_id: []const u8,
        market: ?[]const u8,
        limit: ?u8,
        offset: ?usize,
        additional_types: ?AdditionalType
    ) !Result(Paginated(PlaylistTrack)) {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        const base = try std.fmt.allocPrint(arena.allocator(), "https://api.spotify.com/v1/playlists/{s}/tracks", .{ playlist_id });
        var request = try reqwest.Request.get(arena.allocator(), base, &.{});
        try request.bearerAuth(self.oauth.token.?.access);

        if (market) |v| try request.param("market", v);
        if (limit) |v| try request.param("limit", v);
        if (offset) |v| try request.param("offset", v);
        if (additional_types) |v| try request.param("additional_types", v);

        var response = try request.send(arena.allocator());
        try unwrap(arena.allocator(), &response, null);

        const body = try response.body(arena.allocator());
        return try .fromJsonLeaky(allocator, body);
    }

    /// Get full details of the items of a playlist owned by a Spotify user.
    pub fn updatePlaylistItems(
        self: *SpotifyClient,
        allocator: std.mem.Allocator,
        playlist_id: []const u8,
        options: UpdateItemsOptions,
    ) !Result([]const u8) {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        const base = try std.fmt.allocPrint(arena.allocator(), "https://api.spotify.com/v1/playlists/{s}/tracks", .{ playlist_id });
        var request = try reqwest.Request.put(arena.allocator(), base, &.{});
        try request.bearerAuth(self.oauth.token.?.access);

        try request.json(options);

        var response = try request.send(arena.allocator());
        try unwrap(arena.allocator(), &response, null);

        const body = try response.body(arena.allocator());
        return try .fromWrappedJsonLeaky(.snapshot_id, allocator, body);
    }

    /// Get full details of the items of a playlist owned by a Spotify user.
    pub fn addItemsToPlaylist(
        self: *SpotifyClient,
        allocator: std.mem.Allocator,
        playlist_id: []const u8,
        uris: []const common.Uri,
        position: usize,
    ) !Result([]const u8) {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        const base = try std.fmt.allocPrint(arena.allocator(), "https://api.spotify.com/v1/playlists/{s}/tracks", .{ playlist_id });
        var request = try reqwest.Request.post(arena.allocator(), base, &.{});
        try request.bearerAuth(self.oauth.token.?.access);

        try request.json(.{
            .uris = uris,
            .position = position
        });

        var response = try request.send(arena.allocator());
        try unwrap(arena.allocator(), &response, null);

        const body = try response.body(arena.allocator());
        return try .fromWrappedJsonLeaky(.snapshot_id, allocator, body);
    }

    /// Get a user's playlists.
    ///
    /// If the user id is not provided then it is assumed to be the current user.
    ///
    /// Caller is responsible for freeing allocated memory
    pub fn userPlaylists(self: *SpotifyClient, allocator: std.mem.Allocator, user_id: ?[]const u8, limit: ?u8, offset: ?usize) !Result(Paginated(SimplifiedPlaylist)) {
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
        try unwrap(arena.allocator(), &response, null);

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

pub const PlaylistTrack = struct {
    added_at: []const u8,
    added_by: Owner,
    is_local: bool,
    track: Item,
};

pub const Playlist = struct {
    collaborative: bool,
    description: []const u8,
    external_urls: ExternalUrls,
    followers: Followers,
    href: []const u8,
    id: []const u8,
    images: ?[]Image = null,
    name: []const u8,
    owner: Owner,
    public: bool,
    snapshot_id: []const u8,
    tracks: Paginated(PlaylistTrack),
    uri: []const u8,
};

pub const Details = struct {
    name: ?[]const u8 = null,
    public: ?bool = null,
    collaborative: ?bool = null,
    description: ?[]const u8 = null,

    pub fn jsonStringify(self: *const @This(), writer: anytype) !void {
        try writer.beginObject();
            if (self.name) |value| {
                try writer.objectField("name"); try writer.write(value);
            }
            if (self.public) |value| {
                try writer.objectField("public"); try writer.write(value);
            }
            if (self.collaborative) |value| {
                try writer.objectField("collaborative"); try writer.write(value);
            }
            if (self.name) |value| {
                try writer.objectField("name"); try writer.write(value);
            }
        try writer.endObject();
    }
};

pub const UpdateItemsOptions = struct {
    uris: ?[][]const u8,
    range_start: ?usize,
    insert_before: ?usize,
    range_length: ?usize,
    snapshot_id: ?[]const u8,

    pub fn jsonStringify(self: *const @This(), writer: anytype) !void {
        try writer.beginObject();
        inline for (@typeInfo(@This()).@"struct".fields) |field| {
            if (@field(self, field.name)) |value| {
                try writer.objectField(field.name);
                try writer.write(value);
            }
        }
        try writer.endObject();
    }
};
