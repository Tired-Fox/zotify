const std = @import("std");

pub const Resource = enum {
    ablum,
    playlist,
    show,
    artist,
    track,
    episode,
    user,
    collection,
    your_episodes,
};

pub const Uri = struct {
    type: Resource,
    uri: []const u8,

    pub fn format(
        self: *const @This(),
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        switch(self.type) {
            .collection => try writer.print("spotify:user:{s}:collection", .{ self.uri }),
            .your_episodes => try writer.print("spotify:user:{s}:collection:your-episodes", .{ self.uri }),
            else => |other| try writer.print("spotify:{s}:{s}", .{ @tagName(other), self.uri }),
        }
    }
};

pub fn Result(T: type) type {
    return struct {
        arena: std.heap.ArenaAllocator,
        value: T,

        pub fn deinit(self: @This()) void {
            self.arena.deinit();
        }

        /// The caller owns the memory and is responsible for freeing it
        pub fn fromJsonLeaky(allocator: std.mem.Allocator, content: []const u8) !@This() {
            var arena = std.heap.ArenaAllocator.init(allocator);
            errdefer arena.deinit();
            const allo = arena.allocator();

            const parsed = try std.json.parseFromSlice(std.json.Value, allo, content, .{ .ignore_unknown_fields = true });
            defer parsed.deinit();

            return .{
                .value = try std.json.parseFromValueLeaky(
                    T,
                    allo,
                    parsed.value,
                    .{ .ignore_unknown_fields = true }
                ),
                .arena = arena,
            };
        }

        /// The caller owns the memory and is responsible for freeing it
        pub fn fromWrappedJsonLeaky(inner: @Type(.enum_literal), allocator: std.mem.Allocator, content: []const u8) !@This() {
            var arena = std.heap.ArenaAllocator.init(allocator);
            errdefer arena.deinit();
            const allo = arena.allocator();

            const parsed = try std.json.parseFromSlice(std.json.Value, allo, content, .{ .ignore_unknown_fields = true });
            defer parsed.deinit();

            if (parsed.value != .object) return error.UnexpectedToken;
            const data = parsed.value.object.get(@tagName(inner)) orelse return error.MissingField;

            return .{
                .value = try std.json.parseFromValueLeaky(
                    T,
                    allo,
                    data,
                    .{ .ignore_unknown_fields = true }
                ),
                .arena = arena,
            };
        }
    };
}

pub const ExternalUrls = struct {
    spotify: []const u8,

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        allocator.free(self.spotify);
    }
};

pub const DatePrecision = enum {
    day,
    month,
    year,
};

pub const Reason = enum {
    market,
    product,
    explicit,
};

pub fn Map(T: type) type {
    return struct {
        inner: std.StringArrayHashMap(T),

        pub fn jsonStringify(self: *const @This(), writer: anytype) !void {
            try writer.beginObject();
            var it = self.inner.iterator();
            while (it.next()) |entry| {
                try writer.objectField(entry.key_ptr.*);
                try writer.write(entry.value_ptr.*);
            }
            try writer.endObject();
        }

        pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) std.json.ParseFromValueError!@This() {
            if (source != .object) return error.UnexpectedToken;

            var restrictions = std.StringArrayHashMap(T).init(allocator);
            var it = source.object.iterator();

            while (it.next()) |entry| {
                const key = try allocator.alloc(u8, entry.key_ptr.len);
                @memcpy(key, entry.key_ptr.*);

                try restrictions.put(
                    key,
                    try std.json.innerParseFromValue(T, allocator, entry.value_ptr.*, options)
                );
            }

            return .{
                .inner = restrictions
            };
        }
    };
}

pub const Image = struct {
    height: ?usize = null,
    width: ?usize = null,
    url: []const u8,
};

pub const Cursors = struct {
    before: i64,
    after: i64,
};

pub fn Cursor(T: type) type {
    return struct {
        href: []const u8,
        limit: u8,
        items: []T,
        next: ?[]const u8 = null,
        total: ?usize = null,
        cursors: ?Cursors = null,
    };
}

pub fn Paginated(T: type) type {
    return struct {
        href: []const u8,
        limit: u8,
        offset: usize,
        total: usize,
        next: ?[]const u8 = null,
        previous: ?[]const u8 = null,
        items: []T,

        pub fn jsonStringify(self: *const @This(), writer: anytype) !void {
            try writer.beginObject();
                try writer.objectField("href"); try writer.write(self.href);
                try writer.objectField("limit"); try writer.write(self.limit);
                try writer.objectField("offset"); try writer.write(self.offset);
                try writer.objectField("total"); try writer.write(self.total);

                if (self.next) |next| {
                    try writer.objectField("next"); try writer.write(next);
                }
                if (self.previous) |previous| {
                    try writer.objectField("previous"); try writer.write(previous);
                }

                try writer.objectField("items"); try writer.write(self.items);
            try writer.endObject();
        }
    };
}

pub const Followers = struct {
    href: ?[]const u8 = null,
    total: usize,
};

pub const Owner = struct {
    external_urls: ExternalUrls,
    followers: ?Followers = null,
    href: []const u8,
    id: []const u8,
    uri: []const u8,
    display_name: ?[]const u8 = null,
};
