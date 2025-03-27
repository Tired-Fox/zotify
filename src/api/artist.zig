const std = @import("std");

const ExternalUrls = @import("common.zig").ExternalUrls;

pub const SimplifiedArtist = struct {
    external_urls: ?ExternalUrls = null,
    href: []const u8,
    id: []const u8,
    name: []const u8,
    uri: []const u8,

    pub fn jsonStringify(self: *const @This(), writer: anytype) !void {
        try writer.beginObject();
            try writer.objectField("href"); try writer.write(self.href);
            try writer.objectField("id"); try writer.write(self.id);
            try writer.objectField("name"); try writer.write(self.name);
            try writer.objectField("uri"); try writer.write(self.uri);
            if (self.external_urls) |external| {
                try writer.objectField("external_urls"); try writer.write(external);
            }
        try writer.endObject();
    }
};
