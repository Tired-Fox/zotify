const std = @import("std");
const common = @import("common.zig");

const reqwest = @import("../request.zig");
const SpotifyClient = @import("../api.zig").SpotifyClient;
const unwrap = @import("../api.zig").unwrap;
const Result = common.Result;
const Paginated = common.Paginated;

pub const SearchApi = struct {
};
