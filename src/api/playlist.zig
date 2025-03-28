const ExternalUrls = @import("common.zig").ExternalUrls;
const Image = @import("common.zig").Image;
const Owner = @import("common.zig").Owner;

pub const Tracks = struct {
    total: usize,
    href: []const u8,
};

pub const SimplifiedPlaylist = struct {
    collaborative: bool,
    public: bool,
    description: []const u8,
    href: []const u8,
    id: []const u8,
    name: []const u8,
    snapshot_id: []const u8,
    uri: []const u8,
    external_urls: ExternalUrls,
    owner: Owner,
    tracks: Tracks,
    images: ?[]Image = null,
};
