const std = @import("std");
const oauth = @import("oauth.zig");

const reqwest = @import("request.zig");
const common = @import("api/common.zig");

const Result = common.Result;
const Cursor = common.Cursor;
const TimeRange = common.TimeRange;
const Paginated = common.Paginated;
const Uri = common.Uri;

pub const player = @import("api/player.zig");
pub const playlist = @import("api/playlist.zig");
pub const user = @import("api/user.zig");

pub fn unwrap(allocator: std.mem.Allocator, response: *reqwest.Response, not_found: ?anyerror) !void {
    switch (response.status().class()) {
        .informational, .success, .redirect => return,
        else => switch (response.status()) {
            .unauthorized => return error.BadOrExpiredToken,
            .too_many_requests => return error.RateLimit,
            .forbidden => return error.BadOAuthRequest,
            .not_found => return not_found orelse error.NotFound,
            else => {
                const body = try response.body(allocator);
                defer allocator.free(body);

                std.log.err("[{any}] {s}", .{ response.status(), body });
                return error.Unknown;
            },
        }
    }
}

// The allocator held in this struct is used for constructing and sending the requests.
// It is also used for temporary allocated memory while parsing the body of the response.
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
    pub usingnamespace user.UserApi;

    // ================[ PLAYER ]================
    pub usingnamespace player.PlayerApi;

    // ================[ PLAYLIST ]================
    pub usingnamespace playlist.PlaylistApi;
};
