const std = @import("std");
pub const Album = @import("album.zig").Album;
pub const SimplifiedArtist = @import("artist.zig").SimplifiedArtist;
pub const ExternalUrls = @import("common.zig").ExternalUrls;
pub const Reason = @import("common.zig").Reason;
pub const Map = @import("common.zig").Map;

pub const ExternalIds = struct {
    isrc: ?[]const u8 = null,
    ean: ?[]const u8 = null,
    upc: ?[]const u8 = null,

    pub fn jsonStringify(self: *const @This(), writer: anytype) !void {
        try writer.beginObject();
            if (self.isrc) |isrc| {
                try writer.objectField("isrc"); try writer.write(isrc);
            }
            if (self.ean) |ean| {
                try writer.objectField("ean"); try writer.write(ean);
            }
            if (self.upc) |upc| {
                try writer.objectField("upc"); try writer.write(upc);
            }
        try writer.endObject();
    }
};

pub const Track = struct {
    album: Album,
    artists: []SimplifiedArtist,
    available_markets: [][]const u8,
    disc_number: u8,
    duration_ms: usize,
    explicit: bool,
    external_ids: ?ExternalIds = null,
    external_urls: ?ExternalUrls = null,
    href: []const u8,
    id: []const u8,
    is_playable: bool = true,
    popularity: u8,
    // linked_from: void,
    name: []const u8,
    track_number: u8,
    uri: []const u8,
    is_local: bool,
    restrictions: ?Map(Reason) = null,

    pub fn jsonStringify(self: *const @This(), writer: anytype) !void {
        try writer.beginObject();
            try writer.objectField("album"); try writer.write(self.album);
            try writer.objectField("artists"); try writer.write(self.artists);
            try writer.objectField("available_markets"); try writer.write(self.available_markets);
            try writer.objectField("disc_number"); try writer.write(self.disc_number);
            try writer.objectField("duration_ms"); try writer.write(self.duration_ms);
            try writer.objectField("explicit"); try writer.write(self.explicit);
            if (self.external_ids) |external| {
                try writer.objectField("external_ids"); try writer.write(external);
            }
            if (self.external_urls) |external| {
                try writer.objectField("external_urls"); try writer.write(external);
            }
            try writer.objectField("href"); try writer.write(self.href);
            try writer.objectField("id"); try writer.write(self.id);
            try writer.objectField("is_playable"); try writer.write(self.is_playable);
            try writer.objectField("name"); try writer.write(self.name);
            try writer.objectField("track_number"); try writer.write(self.track_number);
            try writer.objectField("uri"); try writer.write(self.uri);
            try writer.objectField("is_local"); try writer.write(self.is_local);
            try writer.objectField("popularity"); try writer.write(self.popularity);
            if (self.restrictions) |restrictions| {
                try writer.objectField("restrictions");
                try writer.write(restrictions);
            }
        try writer.endObject();
    }
};
