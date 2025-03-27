const std = @import("std");

const SimplifiedArtist = @import("artist.zig").SimplifiedArtist;

const ExternalUrls = @import("common.zig").ExternalUrls;
const Reason = @import("common.zig").Reason;
pub const DatePrecision = @import("common.zig").DatePrecision;
pub const Map = @import("common.zig").Map;
pub const Image = @import("common.zig").Image;

pub const AlbumType = enum {
    album,
    single,
    compilation,
};

pub const Album = struct {
    type: AlbumType,
    total_tracks: u8,
    available_markets: [][]const u8,
    external_urls: ExternalUrls,
    href: []const u8,
    id: []const u8,
    images: []Image,
    name: []const u8,
    release_date: []const u8,
    release_date_precision: DatePrecision,
    uri: []const u8,
    artists: []SimplifiedArtist,
    restrictions: ?Map(Reason) = null,

    pub fn jsonStringify(self: *const @This(), writer: anytype) !void {
        try writer.beginObject();
            try writer.objectField("type"); try writer.write(self.type);
            try writer.objectField("total_tracks"); try writer.write(self.total_tracks);
            try writer.objectField("available_markets"); try writer.write(self.available_markets);
            try writer.objectField("external_urls"); try writer.write(self.external_urls);
            try writer.objectField("href"); try writer.write(self.href);
            try writer.objectField("id"); try writer.write(self.id);
            try writer.objectField("images"); try writer.write(self.images);
            try writer.objectField("name"); try writer.write(self.name);
            try writer.objectField("release_date"); try writer.write(self.release_date);
            try writer.objectField("release_date_precision"); try writer.write(self.release_date_precision);
            try writer.objectField("uri"); try writer.write(self.uri);
            try writer.objectField("artists"); try writer.write(self.artists);
            if (self.restrictions) |restrictions| {
                try writer.objectField("restrictions");
                try writer.write(restrictions);
            }
        try writer.endObject();
    }
};
