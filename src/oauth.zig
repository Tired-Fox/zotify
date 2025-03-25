const std = @import("std");

const dotenvy = @import("dotenvy");
const request = @import("request.zig");
const json = @import("json");

const log = std.log.scoped(.zotify_oauth);

const PKCE = @import("oauth/pkce.zig").PKCE;

pub fn randString(comptime N: usize, needle: []const u8) [N]u8 {
    // Valid lengths are 43-128
    const rand = std.crypto.random;

    var result: [N]u8 = undefined;
    for (0..N) |i| {
        result[i] = needle[rand.intRangeLessThan(usize, 0, needle.len)];
    }
    return result;
}

pub const Credentials = struct {
    id: []const u8,
    secret: []const u8,

    pub fn init(id: []const u8, secret: []const u8) @This() {
        return .{ .id = id, .secret = secret };
    }
};

pub const Token = struct {
    access: []const u8,
    refresh: []const u8,
    scopes: [][]const u8,
    expires: i64,

    pub fn toJson(self: *@This(), writer: anytype) !void {
        try writer.writeByte('{');
        try writer.print("\"access\": \"{s}\",", .{ self.access });
        try writer.print("\"refresh\": \"{s}\",", .{ self.refresh });
        try writer.print("\"expires\": {d},", .{ self.expires });
        try writer.writeAll("\"scopes\": [");
        for (self.scopes, 0..) |scope, i| {
            if (i != 0) try writer.writeByte(',');
            try writer.print("\"{s}\"", .{ scope });
        }
        try writer.writeAll("]}");
    }

    pub fn fromJson(allocator: std.mem.Allocator, content: []const u8) !*@This() {
        const result = try std.json.parseFromSlice(
            @This(),
            allocator,
            content,
            .{ .ignore_unknown_fields = true }
        );
        defer result.deinit();

        const token = try allocator.create(@This());

        const scopes = try allocator.alloc([]const u8, result.value.scopes.len);
        for (0..scopes.len) |i| {
            scopes[i] = try allocator.dupe(u8, result.value.scopes[i]);
        }

        token.* = .{
            .access = try allocator.dupe(u8, result.value.access),
            .refresh = try allocator.dupe(u8, result.value.refresh),
            .scopes = scopes,
            .expires = result.value.expires,
        };

        return token;
    }

    pub fn mergeResponse(self: *@This(), allocator: std.mem.Allocator, content: []const u8) !void {
        const now = std.time.timestamp();

        const result = try std.json.parseFromSlice(struct {
            access_token: []const u8,
            refresh_token: ?[]const u8,
            expires_in: i64,
        }, allocator, content, .{ .ignore_unknown_fields = true });
        defer result.deinit();

        if (result.value.refresh_token) |rt| {
            allocator.free(self.refresh);
            self.refresh = try allocator.dupe(u8, rt);
        }


        allocator.free(self.access);
        self.access = try allocator.dupe(u8, result.value.access_token);
        self.expires = now + result.value.expires_in;
    }

    pub fn fromResponse(allocator: std.mem.Allocator, content: []const u8) !*@This() {
        const now = std.time.timestamp();

        const result = try std.json.parseFromSlice(struct {
            access_token: []const u8,
            refresh_token: []const u8,
            expires_in: i64,
            scope: ?[]const u8 = null
        }, allocator, content, .{ .ignore_unknown_fields = true });
        defer result.deinit();

        var scopes = std.ArrayListUnmanaged([]const u8).empty;
        if (result.value.scope) |scope| {
            var iter = std.mem.splitSequence(u8, scope, " ");
            while (iter.next()) |s| {
                try scopes.append(allocator, try allocator.dupe(u8, s));
            }
        }

        const token = try allocator.create(@This());

        token.* = .{
            .access = try allocator.dupe(u8, result.value.access_token),
            .refresh = try allocator.dupe(u8, result.value.refresh_token),
            .scopes = try scopes.toOwnedSlice(allocator),
            .expires = now + result.value.expires_in,
        };

        return token;
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.access);
        allocator.free(self.refresh);
        for (self.scopes) |scope| {
            allocator.free(scope);
        }
        allocator.free(self.scopes);
        allocator.destroy(self);
    }
};

pub const OAuth = struct {
    arena: std.heap.ArenaAllocator,

    flow: Flow,
    creds: Credentials,
    token: ?*Token = null,

    options: Options,

    pub const Options = struct {
        /// The cache path, including the file name, of where
        /// to save the token when it is fetched.
        ///
        /// This also allows for the token to be loaded from the cache
        /// during the first token refresh.
        cache_path: ?[]const u8,
        /// Determine if the token should be automatically refreshed when
        /// making API calls.
        ///
        /// Defaults to true, and if it is set to false the caller is responsible
        /// for calling refresh when needed before any API calls.
        auto_refresh: bool = true,
    };

    pub const Flow = enum {
        pkce,
        code,
        credential,
        implicit,
    };

    pub fn init(allocator: std.mem.Allocator, flow: Flow, creds: Credentials, options: Options) @This() {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const allo = arena.allocator();

        const token: ?*Token = cache: {
            if (options.cache_path) |cache_path| {
                const cache = (@import("known-folders").getPath(allo, .data) catch break :cache null) orelse break :cache null;
                defer allo.free(cache);

                const path = std.fs.path.join(allo, &.{ cache, cache_path }) catch break :cache null;
                defer allo.free(path);

                std.fs.accessAbsolute(path, .{}) catch break :cache null;

                const file = std.fs.openFileAbsolute(path, .{}) catch break :cache null;
                defer file.close();

                const size = (file.metadata() catch break :cache null).size();
                const content = file.readToEndAlloc(allo, @intCast(size)) catch break :cache null;
                defer allo.free(content);

                const result = Token.fromJson(allo, content) catch break :cache null;
                break :cache result;
            }
            break :cache null;
        };

        return .{
            .arena = arena,
            .flow = flow,
            .creds = creds,
            .token = token,
            .options = options,
        };
    }

    pub fn initEnv(allocator: std.mem.Allocator, flow: Flow, options: Options) !@This() {
        var arena = std.heap.ArenaAllocator.init(allocator);
        const allo = arena.allocator();

        var env_vars = try dotenvy.parse(allo, null);
        defer env_vars.deinit();

        const id = if (env_vars.get("ZOTIFY_ID")) |id| try allo.dupe(u8, id) else return error.MissingZotifyIdEnvVariable;
        const secret = if (env_vars.get("ZOTIFY_SECRET")) |secret| try allo.dupe(u8, secret) else return error.MissingZotifySecretEnvVariable;

        const token: ?*Token = cache: {
            if (options.cache_path) |cache_path| {
                const cache = (@import("known-folders").getPath(allo, .data) catch break :cache null) orelse break :cache null;
                defer allo.free(cache);

                const path = std.fs.path.join(allo, &.{ cache, cache_path }) catch break :cache null;
                defer allo.free(path);

                std.fs.accessAbsolute(path, .{}) catch break :cache null;

                const file = std.fs.openFileAbsolute(path, .{}) catch break :cache null;
                defer file.close();

                const size = (file.metadata() catch break :cache null).size();
                const content = file.readToEndAlloc(allo, @intCast(size)) catch break :cache null;
                defer allo.free(content);

                const result = Token.fromJson(allo, content) catch break :cache null;
                break :cache result;
            }
            break :cache null;
        };

        std.debug.print("[TOKEN] {any}\n", .{ token });

        return .{
            .arena = arena,
            .flow = flow,
            .creds = Credentials.init(id, secret),
            .token = token,
            .options = options,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.arena.deinit();
    }

    pub fn saveToken(self: *@This()) !void {
        if (self.token) |token| {
            if (self.options.cache_path) |cache_path| {
                const allocator = self.arena.allocator();
                const cache = @import("known-folders").getPath(allocator, .data) catch return orelse return;
                defer allocator.free(cache);

                const path = try std.fs.path.join(allocator, &.{ cache, cache_path });
                defer allocator.free(path);

                std.fs.accessAbsolute(path, .{}) catch if (std.fs.path.dirname(cache_path)) |dirname| {
                    const dir = try std.fs.openDirAbsolute(cache, .{});
                    try dir.makePath(dirname);
                };

                const file = try std.fs.createFileAbsolute(path, .{});
                defer file.close();

                try token.toJson(file.writer());
            }
        }
    }

    pub fn refresh(self: *@This()) !void {
        if (self.token == null) {
            try self.handshake();
            try self.saveToken();
        } else if (self.token.?.expires <= std.time.timestamp()) {
            self.refreshToken() catch |err| switch (err) {
                error.InvalidGrant => { try self.handshake(); },
                else => return err,
            };
            try self.saveToken();
        }
    }

    fn refreshToken(self: *@This()) !void {
        log.debug("refreshing auth token", .{});
        const allocator = self.arena.allocator();
        const Encoder = std.base64.url_safe_no_pad.Encoder;

        var params = request.QueryMap.init(allocator);
        try params.put("grant_type", "refresh_token");
        try params.put("refresh_token", self.token.?.refresh);
        try params.put("client_id", self.creds.id);
        defer params.deinit();

        const uri = "https://accounts.spotify.com/api/token";
        var client = std.http.Client { .allocator = allocator };
        defer client.deinit();

        const authorization = auth: {
            const bearer = try std.fmt.allocPrint(
                allocator,
                "{s}:{s}",
                .{
                    self.creds.id,
                    self.creds.secret,
                }
            );
            defer allocator.free(bearer);

            const clen = Encoder.calcSize(bearer.len);
            const out: []u8 = try allocator.alloc(u8, clen);
            defer allocator.free(out);
            // This is what is sent in the request
            break :auth try std.fmt.allocPrint(allocator, "Basic {s}", .{ Encoder.encode(out, bearer) });
        };
        defer allocator.free(authorization);

        var server_headers: [1024 * 1024]u8 = undefined;
        var r = try client.open(.POST, try std.Uri.parse(uri), .{
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "application/x-www-form-urlencoded" },
                .{ .name = "Authorization", .value = authorization },
            },
            .server_header_buffer = &server_headers
        });
        defer r.deinit();


        r.transfer_encoding = .chunked;
        try r.send();
        try r.writer().print("{s}", .{ params });
        try r.finish();

        try r.wait();
        const response = r.response;
        if (response.status == .ok) {
            const body = try r.reader().readAllAlloc(allocator, @intCast(response.content_length orelse 8192));
            defer allocator.free(body);

            try self.token.?.mergeResponse(allocator, body);
        } else {
            const body = try r.reader().readAllAlloc(allocator, @intCast(response.content_length orelse 8192));
            defer allocator.free(body);
            std.debug.print("{s}\n", .{body});
            return error.InvalidGrant;
        }
    }

    fn handshake(self: *@This()) !void {
        log.debug("fetching new auth token", .{});
        switch (self.flow) {
            .pkce => {
                const flow = try PKCE(67).init();
                const allocator = self.arena.allocator();

                const token = try flow.handshake(allocator, &self.creds);
                defer self.arena.allocator().free(token);

                if (self.token) |t| t.deinit(allocator);
                self.token = try Token.fromResponse(allocator, token);
            },
            else => return error.AuthenticationMethodNotImplemented,
        }
    }
};
