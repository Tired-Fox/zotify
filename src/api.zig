const std = @import("std");
const oauth = @import("oauth.zig");

const reqwest = @import("request.zig");

const Result = @import("api/common.zig").Result;
pub const player = @import("api/player.zig");

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

    /// Get the current user's playback state
    ///
    /// Caller is responsible for freeing memory allocated. This can be done by calling `deinit` on `PlayerState`.
    pub fn getPlaybackState(self: *@This(), allocator: std.mem.Allocator, options: player.Options) !?Result(player.PlayerState) {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var request = try reqwest.Request.get(arena.allocator(), "https://api.spotify.com/v1/me/player", &.{});
        try request.bearerAuth(self.oauth.token.?.access);
        if (options.market) |market| try request.param("market", market);
        if (options.additional_types) |additional_types| try request.param("additional_types", additional_types);

        var response = try request.send(arena.allocator());
        switch (response.status()) {
            .ok => {
                const body = try response.body(arena.allocator());
                return try .fromJsonLeaky(allocator, body);
            },
            .no_content => return null,
            .unauthorized => return error.BadOrExpiredToken,
            .too_many_requests => return error.RateLimit,
            .forbidden => return error.BadOAuthRequest,
            else => return error.Unknown,
        }
    }

    /// Get the current user's playback state
    ///
    /// Caller is responsible for freeing memory allocated. This can be done by calling `deinit` on `PlayerState`.
    pub fn getDevices(self: *@This(), allocator: std.mem.Allocator) !Result([]player.Device) {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var request = try reqwest.Request.get(arena.allocator(), "https://api.spotify.com/v1/me/player/devices", &.{});
        try request.bearerAuth(self.oauth.token.?.access);

        var response = try request.send(arena.allocator());
        switch (response.status()) {
            .ok => {
                const body = try response.body(arena.allocator());
                return try .fromWrappedJsonLeaky(.devices, allocator, body);
            },
            .unauthorized => return error.BadOrExpiredToken,
            .too_many_requests => return error.RateLimit,
            .forbidden => return error.BadOAuthRequest,
            else => return error.Unknown,
        }
    }

    /// Transfer the playback to a specific `device`
    ///
    /// **play**:
    ///     - `true`: ensure that playback happens on the device
    ///     - `false`: keep the current playback state
    pub fn transferPlayback(self: *@This(), device_id: []const u8, play: bool) !void {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var request = try reqwest.Request.put(arena.allocator(), "https://api.spotify.com/v1/me/player", &.{});
        try request.bearerAuth(self.oauth.token.?.access);
        try request.json(.{
            .device_ids = [1][]const u8 { device_id },
            .play = play,
        });

        var response = try request.send(arena.allocator());
        switch (response.status()) {
            .no_content => {},
            .unauthorized => return error.BadOrExpiredToken,
            .too_many_requests => return error.RateLimit,
            .forbidden => return error.BadOAuthRequest,
            else => return error.Unknown,
        }
    }
};
