const std = @import("std");
const common = @import("common.zig");

const reqwest = @import("../request.zig");
const SpotifyClient = @import("../api.zig").SpotifyClient;
const unwrap = @import("../api.zig").unwrap;
const Result = common.Result;
const Cursor = common.Cursor;
const Uri = common.Uri;
const Paginated = common.Paginated;
const AdditionalType = common.AdditionalType;
const Item = common.Item;

const Track = @import("track.zig").Track;
const Episode = @import("episode.zig").Episode;

pub const PlayerApi = struct {
    /// Get the current user's playback state
    ///
    /// Caller is responsible for freeing allocated memory
    pub fn playbackState(self: *SpotifyClient, allocator: std.mem.Allocator, options: Options) !?Result(PlayerState) {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var request = try reqwest.Request.get(arena.allocator(), "https://api.spotify.com/v1/me/player", &.{});
        try request.bearerAuth(self.oauth.token.?.access);
        if (options.market) |market| try request.param("market", market);
        if (options.additional_types) |additional_types| try request.param("additional_types", additional_types);

        var response = try request.send(arena.allocator());
        try unwrap(arena.allocator(), &response, null);

        if (response.status() == .ok) {
            const body = try response.body(arena.allocator());
            return try .fromJsonLeaky(allocator, body);
        }
        return null;
    }

    /// Get the currently playing track for the current user
    ///
    /// Caller is responsible for freeing allocated memory
    pub fn currentlyPlaying(self: *SpotifyClient, allocator: std.mem.Allocator, options: Options) !Result(PlayerState) {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var request = try reqwest.Request.get(arena.allocator(), "https://api.spotify.com/v1/me/player/currently-playing", &.{});
        try request.bearerAuth(self.oauth.token.?.access);
        if (options.market) |market| try request.param("market", market);
        if (options.additional_types) |additional_types| try request.param("additional_types", additional_types);

        var response = try request.send(arena.allocator());
        try unwrap(arena.allocator(), &response, null);

        const body = try response.body(arena.allocator());
        return try .fromJsonLeaky(allocator, body);
    }

    /// Get the current user's playback state
    ///
    /// Caller is responsible for freeing allocated memory
    pub fn devices(self: *SpotifyClient, allocator: std.mem.Allocator) !Result([]Device) {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var request = try reqwest.Request.get(arena.allocator(), "https://api.spotify.com/v1/me/player/devices", &.{});
        try request.bearerAuth(self.oauth.token.?.access);

        var response = try request.send(arena.allocator());
        try unwrap(arena.allocator(), &response, null);

        const body = try response.body(arena.allocator());
        return try .fromWrappedJsonLeaky(.devices, allocator, body);
    }

    /// Transfer the playback to a specific `device`
    ///
    /// **play**:
    ///     - `true`: ensure that playback happens on the device
    ///     - `false`: keep the current playback state
    pub fn transferPlayback(self: *SpotifyClient, device_id: []const u8, start: bool) !void {
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
        try unwrap(arena.allocator(), &response, error.NoActiveDevice);
    }

    /// Start or resume playback with a specific device on the user's account.
    ///
    /// If device is not specified the currently active device is used.
    ///
    /// The user may also pass a context_uri with an optional offset or a list
    /// of Uri to play in the queue.
    pub fn play(self: *SpotifyClient, device_id: ?[]const u8, context: ?StartResume) !void {
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
        try unwrap(arena.allocator(), &response, error.NoActiveDevice);
    }

    /// Pause playback on the user's account
    ///
    /// If device is not specified the currently active device is used.
    pub fn pause(self: *SpotifyClient, device_id: ?[]const u8) !void {
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
        try unwrap(arena.allocator(), &response, error.NoActiveDevice);
    }

    /// Skips to the next item in the user's queue.
    ///
    /// If device is not specified the currently active device is used.
    pub fn next(self: *SpotifyClient, device_id: ?[]const u8) !void {
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
        try unwrap(arena.allocator(), &response, error.NoActiveDevice);
    }

    /// Skips to the previous item in the user's queue.
    ///
    /// If device is not specified the currently active device is used.
    pub fn previous(self: *SpotifyClient, device_id: ?[]const u8) !void {
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
        try unwrap(arena.allocator(), &response, error.NoActiveDevice);
    }

    /// Seek to a specific millisecond position in the user's currently playing item
    ///
    /// If device is not specified the currently active device is used.
    pub fn seekTo(self: *SpotifyClient, position: usize, device_id: ?[]const u8) !void {
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
        try unwrap(arena.allocator(), &response, error.NoActiveDevice);
    }

    /// Set the repeat state for the user's playback
    ///
    /// If device is not specified the currently active device is used.
    pub fn repeat(self: *SpotifyClient, state: Repeat, device_id: ?[]const u8) !void {
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
        try unwrap(arena.allocator(), &response, error.NoActiveDevice);
    }

    /// Set the shuffle state for the user's playback
    ///
    /// If device is not specified the currently active device is used.
    pub fn shuffle(self: *SpotifyClient, state: bool, device_id: ?[]const u8) !void {
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
        try unwrap(arena.allocator(), &response, error.NoActiveDevice);
    }

    /// Set the volume percent for the user's playback
    ///
    /// If device is not specified the currently active device is used.
    ///
    /// The percent is automatically clamped at 100.
    pub fn volume(self: *SpotifyClient, percent: u8, device_id: ?[]const u8) !void {
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
        try unwrap(arena.allocator(), &response, error.NoActiveDevice);
    }

    /// Get the user's recently played items
    ///
    /// Caller is responsible for freeing allocated memory
    pub fn recentItems(self: *SpotifyClient, allocator: std.mem.Allocator, limit: ?u8, timestamp: ?RecentlyPlayed) !Result(Cursor(PlayHistory)) {
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
        try unwrap(arena.allocator(), &response, null);

        const body = try response.body(arena.allocator());
        return try .fromJsonLeaky(allocator, body);
    }

    /// Get the user's queue
    ///
    /// Caller is responsible for freeing allocated memory
    pub fn queue(self: *SpotifyClient, allocator: std.mem.Allocator) !Result(Queue) {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var request = try reqwest.Request.get(arena.allocator(), "https://api.spotify.com/v1/me/player/queue", &.{});
        try request.bearerAuth(self.oauth.token.?.access);

        var response = try request.send(arena.allocator());
        try unwrap(arena.allocator(), &response, null);

        const body = try response.body(arena.allocator());
        return try .fromJsonLeaky(allocator, body);
    }

    /// Add item to the user's queue
    ///
    /// If device is not specified the currently active device is used.
    pub fn addItemToQueue(self: *SpotifyClient, uri: Uri, device_id: ?[]const u8) !void {
        try self.oauth.refresh();
        if (self.oauth.token == null) return error.Authorization;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var request = try reqwest.Request.post(arena.allocator(), "https://api.spotify.com/v1/me/player/queue", &.{});
        try request.bearerAuth(self.oauth.token.?.access);
        try request.param("uri", uri);
        if (device_id) |device| {
            try request.param("device_id", device, error.NoActiveDevice);
        }

        var response = try request.send(arena.allocator());
        try unwrap(arena.allocator(), &response, null);
    }
};

pub const Options = struct {
    market: ?[]const u8 = null,
    additional_types: ?AdditionalType = null,
};

pub const Device = struct {
    id: ?[]const u8 = null,
    is_active: bool,
    is_private_session: bool,
    is_restricted: bool,
    name: []const u8,
    type: []const u8,
    volume_percent: ?u8 = null,
    supports_volume: bool,
};

pub const Repeat = enum {
    off,
    track,
    context,

    pub fn format(
        self: *const @This(),
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        switch (self.*) {
            .off => try writer.writeAll("off"),
            .track => try writer.writeAll("track"),
            .context => try writer.writeAll("context"),
        }
    }
};

pub const Context = struct {
    type: common.Resource,
    href: []const u8,
    external_url: ?common.ExternalUrls = null,
    uri: []const u8,
};

pub const ContextActions = struct {
    interrupting_playback: ?bool = null,
    pausing: ?bool = null,
    resuming: ?bool = null,
    seeking: ?bool = null,
    skipping_next: ?bool = null,
    skipping_prev: ?bool = null,
    toggling_repeat_context: ?bool = null,
    toggling_shuffle: ?bool = null,
    toggling_repeat_track: ?bool = null,
    transfering_playback: ?bool = null,

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

pub const Actions = struct {
    disallows: ?ContextActions = null,

    pub fn jsonStringify(self: *const @This(), writer: anytype) !void {
        try writer.beginObject();
        if (self.disallows) |value| {
            try writer.objectField("disallows");
            try writer.write(value);
        }
        try writer.endObject();
    }
};

pub const CurrentlyPlayingType = enum {
    track,
    episode,
    ad,
    unknown,
};

pub const PlayerState = struct {
    device: Device,
    repeat_state: Repeat,
    shuffle_state: bool,
    context: ?Context,
    timestamp: i64,
    progress_ms: ?usize,
    is_playing: bool,
    currently_playing_type: CurrentlyPlayingType,
    item: ?Item,
    actions: Actions,

    pub fn jsonStringify(self: *const @This(), writer: anytype) !void {
        try writer.beginObject();
            try writer.objectField("device"); try writer.write(self.device);
            try writer.objectField("repeat"); try writer.write(self.repeat);
            try writer.objectField("shuffle"); try writer.write(self.shuffle);
            try writer.objectField("context"); try writer.write(self.context);
            try writer.objectField("timestamp"); try writer.write(self.timestamp);
            try writer.objectField("progress"); try writer.write(self.progress);
            try writer.objectField("playing"); try writer.write(self.playing);
            try writer.objectField("currently_playing_type"); try writer.write(self.currently_playing_type);
            try writer.objectField("item"); try writer.write(self.item);
            try writer.objectField("actions"); try writer.write(self.actions);
        try writer.endObject();
    }
};

pub const StartResume = union(enum) {
    context: struct {
        uri: common.Uri,
        offset: ?usize = null,
    },
    uris: [][]const u8,

    pub fn jsonStringify(self: *const @This(), writer: anytype) !void {
        try writer.beginObject();
        switch (self.*) {
            .context => |ctx| {
                try writer.objectField("context_uri");
                try writer.write(ctx.uri);

                if (ctx.offset) |offset| {
                    try writer.objectField("offset");
                    try writer.write(offset);
                }
            },
            .uris => |uris| {
                try writer.objectField("uris");
                try writer.write(uris);
            }
        }
        try writer.endObject();
    }
};

pub const PlayHistory = struct {
    track: Track,
    played_at: []const u8,
    context: Context,
};

pub const RecentlyPlayed = union(enum) {
    after: i64,
    before: i64,
};

pub const Queue = struct {
    currently_playing: Item,
    queue: []Item,
};
