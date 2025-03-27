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
};

pub const ContextType = enum {
    ablum,
    playlist,
    show,
    artist
};

pub const Context = struct {
    type: ContextType,
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
    repeat: Repeat,
    shuffle: bool,
    context: ?Context,
    timestamp: i64,
    progress: ?usize,
    playing: bool,
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
            try writer.objectField("currently_playing_type"); try writer.write(if (self.item) |item| @tagName(std.meta.activeTag(item)) else "unknown");
            try writer.objectField("item"); try writer.write(self.item);
            try writer.objectField("actions"); try writer.write(self.actions);
        try writer.endObject();
    }

    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) std.json.ParseFromValueError!PlayerState {
        const data = try std.json.innerParseFromValue(struct {
            device: Device,
            repeat_state: Repeat,
            shuffle_state: bool,
            context: ?Context,
            timestamp: i64,
            progress_ms: ?usize,
            is_playing: bool,
            actions: Actions,
            currently_playing_type: CurrentlyPlayingType,
            item: ?std.json.Value,
        }, allocator, source, options);

        return .{
            .device = data.device,
            .repeat = data.repeat_state,
            .shuffle = data.shuffle_state,
            .context = data.context,
            .timestamp = data.timestamp,
            .progress = data.progress_ms,
            .playing = data.is_playing,
            .actions = data.actions,
            .item = item: {
                if (data.item) |item| {
                    switch (data.currently_playing_type) {
                        .track => {
                            break :item .{ .track = try std.json.innerParseFromValue(Track, allocator, item, .{ .ignore_unknown_fields = true }) };
                        },
                        .episode => {
                            break :item .{ .episode = try std.json.innerParseFromValue(Episode, allocator, item, .{ .ignore_unknown_fields = true }) };
                        },
                        .ad, .unknown => {
                            break :item null;
                        }
                    }
                }
                break :item null;
            },
        };
    }
};
