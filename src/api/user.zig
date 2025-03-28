const ExternalUrls = @import("common.zig").ExternalUrls;
const Followers = @import("common.zig").Followers;
const Image = @import("common.zig").Image;

pub const ExplicitContent = struct {
    filter_enabled: bool,
    filter_locked: bool,
};

pub const Profile = struct {
    display_name: ?[]const u8 = null,
    external_urls: ExternalUrls,
    followers: ?Followers = null,
    href: []const u8,
    id: []const u8,
    images: []Image,
    uri: []const u8,

    ///  scope: user-read-private
    country: ?[]const u8 = null,
    ///  scope: user-read-private
    explicit_content: ?ExplicitContent = null,
    ///  scope: user-read-private
    product: []const u8,

    /// scope: user-read-email
    email: ?[]const u8 = null,
};
