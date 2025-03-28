const std = @import("std");
const oauth = @import("oauth.zig");

const reqwest = @import("request.zig");

const Result = @import("api/common.zig").Result;
const Cursor = @import("api/common.zig").Cursor;
const Paginated = @import("api/common.zig").Paginated;
const Uri = @import("api/common.zig").Uri;

pub const player = @import("api/player.zig");
pub const playlist = @import("api/playlist.zig");
pub const user = @import("api/user.zig");

fn unwrap(allocator: std.mem.Allocator, response: *reqwest.Response) !void {
    switch (response.status()) {
        .ok, .no_content => return,
        .unauthorized => return error.BadOrExpiredToken,
        .too_many_requests => return error.RateLimit,
        .forbidden => return error.BadOAuthRequest,
        .not_found => return error.NoActiveDevice,
        else => {
            const body = try response.body(allocator);
            defer allocator.free(body);

            std.log.err("{s}", .{ body });
            return error.Unknown;
        },
    }
}

pub const SpotifyClient = struct {
    allocator: std.mem.Allocator,

    oauth: oauth.OAuth,
    options: Options = .{},

    pub const Options = struct {
        /// Determine if the authorization token should be automatically refreshed
        /// before executing API calls.
        ///
        /// It is recommended to leave this set to true unless you have a specific
        /// use case that required custom logic around refreshing the authorization
        /// token.
        auto_refresh: bool = true,
    };

    pub fn deinit(self: *@This()) void {
        self.oauth.deinit();
    }

    // ================[ USER ]================

    /// Get the current user's playback state
    ///
    /// Caller is responsible for freeing memory allocated
    pub fn profile(self: *@This(), allocator: std.mem.Allocator, user_id: ?[]const u8) !Result(user.Profile) {
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

    // ================[ PLAYER ]================

    /// Get the current user's playback state
    ///
    /// Caller is responsible for freeing memory allocated
    pub fn playbackState(self: *@This(), allocator: std.mem.Allocator, options: player.Options) !?Result(player.PlayerState) {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var request = try reqwest.Request.get(arena.allocator(), "https://api.spotify.com/v1/me/player", &.{});
        try request.bearerAuth(self.oauth.token.?.access);
        if (options.market) |market| try request.param("market", market);
        if (options.additional_types) |additional_types| try request.param("additional_types", additional_types);

        var response = try request.send(arena.allocator());
        try unwrap(arena.allocator(), &response);

        if (response.status() == .ok) {
            const body = try response.body(arena.allocator());
            return try .fromJsonLeaky(allocator, body);
        }
        return null;
    }

    /// Get the currently playing track for the current user
    ///
    /// Caller is responsible for freeing memory allocated
    pub fn currentlyPlaying(self: *@This(), allocator: std.mem.Allocator, options: player.Options) !Result(player.PlayerState) {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var request = try reqwest.Request.get(arena.allocator(), "https://api.spotify.com/v1/me/player/currently-playing", &.{});
        try request.bearerAuth(self.oauth.token.?.access);
        if (options.market) |market| try request.param("market", market);
        if (options.additional_types) |additional_types| try request.param("additional_types", additional_types);

        var response = try request.send(arena.allocator());
        try unwrap(arena.allocator(), &response);

        const body = try response.body(arena.allocator());
        return try .fromJsonLeaky(allocator, body);
    }

    /// Get the current user's playback state
    ///
    /// Caller is responsible for freeing memory allocated
    pub fn devices(self: *@This(), allocator: std.mem.Allocator) !Result([]player.Device) {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var request = try reqwest.Request.get(arena.allocator(), "https://api.spotify.com/v1/me/player/devices", &.{});
        try request.bearerAuth(self.oauth.token.?.access);

        var response = try request.send(arena.allocator());
        try unwrap(arena.allocator(), &response);

        const body = try response.body(arena.allocator());
        return try .fromWrappedJsonLeaky(.devices, allocator, body);
    }

    /// Transfer the playback to a specific `device`
    ///
    /// **play**:
    ///     - `true`: ensure that playback happens on the device
    ///     - `false`: keep the current playback state
    pub fn transferPlayback(self: *@This(), device_id: []const u8, start: bool) !void {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var request = try reqwest.Request.put(arena.allocator(), "https://api.spotify.com/v1/me/player", &.{});
        try request.bearerAuth(self.oauth.token.?.access);
        try request.json(.{
            .device_ids = [1][]const u8 { device_id },
            .play = start,
        });

        var response = try request.send(arena.allocator());
        try unwrap(arena.allocator(), &response);
    }

    /// Start or resume playback with a specific device on the user's account.
    ///
    /// If device is not specified the currently active device is used.
    ///
    /// The user may also pass a context_uri with an optional offset or a list
    /// of Uri to play in the queue.
    pub fn play(self: *@This(), device_id: ?[]const u8, context: ?player.StartResume) !void {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var request = try reqwest.Request.put(arena.allocator(), "https://api.spotify.com/v1/me/player/play", &.{});
        try request.bearerAuth(self.oauth.token.?.access);
        if (device_id) |device| {
            try request.param("device_id", device);
        }

        if (context) |ctx|
            try request.json(ctx)
        else
            try request.header("Content-Type", "application/json");

        var response = try request.send(arena.allocator());
        try unwrap(arena.allocator(), &response);
    }

    /// Pause playback on the user's account
    ///
    /// If device is not specified the currently active device is used.
    pub fn pause(self: *@This(), device_id: ?[]const u8) !void {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var request = try reqwest.Request.put(arena.allocator(), "https://api.spotify.com/v1/me/player/pause", &.{});
        try request.bearerAuth(self.oauth.token.?.access);
        if (device_id) |device| {
            try request.param("device_id", device);
        }

        var response = try request.send(arena.allocator());
        try unwrap(arena.allocator(), &response);
    }

    /// Skips to the next item in the user's queue.
    ///
    /// If device is not specified the currently active device is used.
    pub fn next(self: *@This(), device_id: ?[]const u8) !void {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var request = try reqwest.Request.post(arena.allocator(), "https://api.spotify.com/v1/me/player/next", &.{});
        try request.bearerAuth(self.oauth.token.?.access);
        if (device_id) |device| {
            try request.param("device_id", device);
        }

        var response = try request.send(arena.allocator());
        try unwrap(arena.allocator(), &response);
    }

    /// Skips to the previous item in the user's queue.
    ///
    /// If device is not specified the currently active device is used.
    pub fn previous(self: *@This(), device_id: ?[]const u8) !void {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var request = try reqwest.Request.post(arena.allocator(), "https://api.spotify.com/v1/me/player/previous", &.{});
        try request.bearerAuth(self.oauth.token.?.access);
        if (device_id) |device| {
            try request.param("device_id", device);
        }

        var response = try request.send(arena.allocator());
        try unwrap(arena.allocator(), &response);
    }

    /// Seek to a specific millisecond position in the user's currently playing item
    ///
    /// If device is not specified the currently active device is used.
    pub fn seekTo(self: *@This(), position: usize, device_id: ?[]const u8) !void {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var request = try reqwest.Request.put(arena.allocator(), "https://api.spotify.com/v1/me/player/seek", &.{});
        try request.bearerAuth(self.oauth.token.?.access);
        try request.param("position_ms", position);
        if (device_id) |device| {
            try request.param("device_id", device);
        }

        var response = try request.send(arena.allocator());
        try unwrap(arena.allocator(), &response);
    }

    /// Set the repeat state for the user's playback
    ///
    /// If device is not specified the currently active device is used.
    pub fn repeat(self: *@This(), state: player.Repeat, device_id: ?[]const u8) !void {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var request = try reqwest.Request.put(arena.allocator(), "https://api.spotify.com/v1/me/player/repeat", &.{});
        try request.bearerAuth(self.oauth.token.?.access);
        try request.param("state", state);
        if (device_id) |device| {
            try request.param("device_id", device);
        }

        var response = try request.send(arena.allocator());
        try unwrap(arena.allocator(), &response);
    }

    /// Set the shuffle state for the user's playback
    ///
    /// If device is not specified the currently active device is used.
    pub fn shuffle(self: *@This(), state: bool, device_id: ?[]const u8) !void {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var request = try reqwest.Request.put(arena.allocator(), "https://api.spotify.com/v1/me/player/shuffle", &.{});
        try request.bearerAuth(self.oauth.token.?.access);
        try request.param("state", state);
        if (device_id) |device| {
            try request.param("device_id", device);
        }

        var response = try request.send(arena.allocator());
        try unwrap(arena.allocator(), &response);
    }

    /// Set the volume percent for the user's playback
    ///
    /// If device is not specified the currently active device is used.
    ///
    /// The percent is automatically clamped at 100.
    pub fn volume(self: *@This(), percent: u8, device_id: ?[]const u8) !void {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var request = try reqwest.Request.put(arena.allocator(), "https://api.spotify.com/v1/me/player/volume", &.{});
        try request.bearerAuth(self.oauth.token.?.access);
        try request.param("volume_percent", @min(percent, 100));
        if (device_id) |device| {
            try request.param("device_id", device);
        }

        var response = try request.send(arena.allocator());
        try unwrap(arena.allocator(), &response);
    }

    /// Get the user's recently played items
    ///
    /// Caller is responsible for freeing memory allocated
    pub fn recentItems(self: *@This(), allocator: std.mem.Allocator, limit: ?u8, timestamp: ?player.RecentlyPlayed) !Result(Cursor(player.PlayHistory)) {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var request = try reqwest.Request.get(arena.allocator(), "https://api.spotify.com/v1/me/player/recently-played", &.{});
        try request.bearerAuth(self.oauth.token.?.access);
        if (limit) |l| try request.param("limit", l);
        if (timestamp) |t| switch (t) {
            .before => |before| try request.param("before", before),
            .after => |after| try request.param("after", after),
        };

        var response = try request.send(arena.allocator());
        try unwrap(arena.allocator(), &response);

        const body = try response.body(arena.allocator());
        return try .fromJsonLeaky(allocator, body);
    }

    /// Get the user's queue
    ///
    /// Caller is responsible for freeing memory allocated
    pub fn queue(self: *@This(), allocator: std.mem.Allocator) !Result(player.Queue) {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var request = try reqwest.Request.get(arena.allocator(), "https://api.spotify.com/v1/me/player/queue", &.{});
        try request.bearerAuth(self.oauth.token.?.access);

        var response = try request.send(arena.allocator());
        try unwrap(arena.allocator(), &response);

        const body = try response.body(arena.allocator());
        return try .fromJsonLeaky(allocator, body);
    }

    /// Add item to the user's queue
    ///
    /// If device is not specified the currently active device is used.
    pub fn addItemToQueue(self: *@This(), uri: Uri, device_id: ?[]const u8) !void {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var request = try reqwest.Request.post(arena.allocator(), "https://api.spotify.com/v1/me/player/queue", &.{});
        try request.bearerAuth(self.oauth.token.?.access);
        try request.param("uri", uri);
        if (device_id) |device| {
            try request.param("device_id", device);
        }

        var response = try request.send(arena.allocator());
        try unwrap(arena.allocator(), &response);
    }

    // ================[ PLAYLIST ]================

    /// Get a user's playlists.
    ///
    /// If the user id is not provided then it is assumed to be the current user.
    ///
    /// Caller is responsible for freeing memory allocated
    pub fn playlists(self: *@This(), allocator: std.mem.Allocator, user_id: ?[]const u8, limit: ?u8, offset: ?usize) !Result(Paginated(playlist.SimplifiedPlaylist)) {
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
