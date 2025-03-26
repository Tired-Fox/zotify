const std = @import("std");
const oauth = @import("oauth.zig");

const reqwest = @import("request.zig");

pub const player = @import("api/player.zig");

pub const SpotifyClient = struct {
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

    pub fn getPlaybackState(self: *@This(), allocator: std.mem.Allocator, options: player.Options) !?[]const u8 {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var request = try reqwest.Request.get(allocator, "https://api.spotify.com/v1/me/player", &.{});
        defer request.deinit();

        try request.bearerAuth(self.oauth.token.?.access);

        if (options.market) |market| try request.param("market", market);
        if (options.additional_types) |additional_types| try request.param("additional_types", additional_types);

        var response = try request.send(allocator);
        defer response.deinit();

        // switch (response.status()) {
        //     .ok => {
        //         return try response.body(allocator);
        //     },
        //     .unauthorized => return error.BadOrExpiredToken,
        //     .too_many_requests => return error.RateLimit,
        //     .forbidden => return error.BadOAuthRequest,
        //     .no_content => return null,
        //     else => return error.Unknown,
        // }
        return null;
    }
};
