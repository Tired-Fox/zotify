const std = @import("std");
const common = @import("common.zig");
const Track = @import("track.zig").Track;
const Episode = @import("episode.zig").Episode;

pub const AdditionalType = enum {
    episode,

    pub fn format(
        self: *const @This(),
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        switch (self.*) {
            .episode => try writer.writeAll("episode")
        }
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

pub const Item = union(enum) {
    track: Track,
    episode: Episode,

    pub fn jsonStringify(self: *const @This(), writer: anytype) !void {
        switch (self.*) {
            .track => |track| try writer.write(track),
            .episode => |episode| try writer.write(episode),
        }
    }

    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) std.json.ParseFromValueError!@This() {
        if (source != .object) return error.UnexpectedToken;
        if (std.mem.eql(u8, source.object.get("type").?.string, "track")) {
            return .{
                .track = try std.json.innerParseFromValue(Track, allocator, source, options),
            };
        }
        return .{
            .episode = try std.json.innerParseFromValue(Episode, allocator, source, options),
        };
    }
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
