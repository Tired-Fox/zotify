pub const Image = @import("common.zig").Image;
pub const ExternalUrls = @import("common.zig").ExternalUrls;
pub const DatePrecision = @import("common.zig").DatePrecision;
pub const Map = @import("common.zig").Map;
pub const Reason = @import("common.zig").Reason;

pub const ResumePoint = struct {
    fully_played: bool = false,
    resume_position_ms: usize,
};

pub const Episode = struct {
    description: []const u8,
    html_description: []const u8,
    duration_ms: usize,
    explicit: bool,
    external_urls: ExternalUrls,
    href: []const u8,
    id: []const u8,
    images: []Image,
    is_externally_hosted: bool,
    is_playable: bool,
    language: []const u8,
    languages: [][]const u8,
    name: []const u8,
    release_date: []const u8,
    release_date_precision: DatePrecision,
    uri: []const u8,
    show: Show,
    resume_point: ?ResumePoint = null,
    restrictions: ?Map(Reason) = null,

    pub fn jsonStringify(self: *const @This(), writer: anytype) !void {
        try writer.beginObject();
            try writer.objectField("description"); try writer.write(self.description);
            try writer.objectField("html_description"); try writer.write(self.html_description);
            try writer.objectField("duration_ms"); try writer.write(self.duration_ms);
            try writer.objectField("explicit"); try writer.write(self.explicit);
            try writer.objectField("external_urls"); try writer.write(self.external_urls);
            try writer.objectField("href"); try writer.write(self.href);
            try writer.objectField("id"); try writer.write(self.id);
            try writer.objectField("image"); try writer.write(self.images);
            try writer.objectField("is_externally_hosted"); try writer.write(self.is_externally_hosted);
            try writer.objectField("is_playable"); try writer.write(self.is_playable);
            try writer.objectField("language"); try writer.write(self.language);
            try writer.objectField("languages"); try writer.write(self.languages);
            try writer.objectField("name"); try writer.write(self.name);
            try writer.objectField("release_date"); try writer.write(self.release_date);
            try writer.objectField("release_date_precision"); try writer.write(self.release_date_precision);
            try writer.objectField("uri"); try writer.write(self.uri);
            if (self.resume_point) |resume_point| {
                try writer.objectField("resume_point"); try writer.write(resume_point);
            }
            if (self.restrictions) |restrictions| {
                try writer.objectField("restrictions"); try writer.write(restrictions);
            }
            try writer.objectField("show"); try writer.write(self.show);
        try writer.endObject();
    }
};

pub const Copyright = struct {
    text: []const u8,
    type: []const u8,
};

pub const Show = struct {
    available_markets: [][]const u8,
    copyrights: []Copyright,
    description: []const u8,
    html_description: []const u8,
    explicit: bool,
    external_urls: ExternalUrls,
    href: []const u8,
    id: []const u8,
    images: []Image,
    is_externally_hosted: bool,
    languages: [][]const u8,
    media_type: []const u8,
    name: []const u8,
    publisher: []const u8,
    uri: []const u8,
    total_episodes: usize,
};
