const std = @import("std");

const ExternalUrls = @import("common.zig").ExternalUrls;
const Followers = @import("common.zig").Followers;
const Image = @import("common.zig").Image;

pub const SimplifiedArtist = struct {
    external_urls: ?ExternalUrls = null,
    href: []const u8,
    id: []const u8,
    name: []const u8,
    uri: []const u8,

    pub fn jsonStringify(self: *const @This(), writer: anytype) !void {
        try writer.beginObject();
            if (self.external_urls) |external| {
                try writer.objectField("external_urls"); try writer.write(external);
            }
            try writer.objectField("href"); try writer.write(self.href);
            try writer.objectField("id"); try writer.write(self.id);
            try writer.objectField("name"); try writer.write(self.name);
            try writer.objectField("uri"); try writer.write(self.uri);
        try writer.endObject();
    }
};

pub const Artist = struct {
    external_urls: ?ExternalUrls = null,
    followers: Followers,
    genres: [][]const u8,
    href: []const u8,
    id: []const u8,
    images: []Image,
    name: []const u8,
    popularity: u8,
    uri: []const u8,

    pub fn jsonStringify(self: *const @This(), writer: anytype) !void {
        try writer.beginObject();
            if (self.external_urls) |external| {
                try writer.objectField("external_urls"); try writer.write(external);
            }
            try writer.objectField("followers"); try writer.write(self.followers);
            try writer.objectField("genres"); try writer.write(self.genres);
            try writer.objectField("href"); try writer.write(self.href);
            try writer.objectField("id"); try writer.write(self.id);
            try writer.objectField("images"); try writer.write(self.images);
            try writer.objectField("name"); try writer.write(self.name);
            try writer.objectField("popularity"); try writer.write(self.popularity);
            try writer.objectField("uri"); try writer.write(self.uri);
        try writer.endObject();
    }
};
