const std = @import("std");

const dotenvy = @import("dotenvy");
const request = @import("request.zig");
const json = @import("json");

const log = std.log.scoped(.zotify_oauth);

const PkceFlow = @import("oauth/pkce.zig").PkceFlow;
const AuthCodeFlow = @import("oauth/auth_code.zig").AuthCodeFlow;
const CredentialFlow = @import("oauth/credential.zig").CredentialFlow;

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
    secret: ?[]const u8,

    pub fn init(id: []const u8, secret: ?[]const u8) @This() {
        return .{ .id = id, .secret = secret };
    }
};

pub const Token = struct {
    access: []const u8,
    refresh: ?[]const u8,
    scopes: Scopes,
    expires: i64,

    pub fn toJson(self: *@This(), writer: anytype) !void {
        try writer.writeByte('{');
        try writer.print("\"access\":\"{s}\",", .{ self.access });
        if (self.refresh) |refresh| {
            try writer.print("\"refresh\":\"{s}\",", .{ refresh });
        }
        try writer.print("\"expires\":{d},", .{ self.expires });
        try writer.writeAll("\"scopes\":[");
        var count: usize = 0;
        inline for (@typeInfo(Scopes.Scope).@"enum".fields) |scope| {
            if (@field(self.scopes, scope.name)) {
                if (count > 0) try writer.writeByte(',');
                try writer.print("\"{s}\"", .{ Scopes.text(@enumFromInt(scope.value)) });
                count += 1;
            }
        }
        try writer.writeAll("]}");
    }

    pub fn fromJson(allocator: std.mem.Allocator, content: []const u8) !*@This() {
        const result = try std.json.parseFromSlice(
            struct {
                access: []const u8,
                refresh: ?[]const u8 = null,
                scopes: [][]const u8,
                expires: i64,
            },
            allocator,
            content,
            .{ .ignore_unknown_fields = true }
        );
        defer result.deinit();

        const token = try allocator.create(@This());

        var scopes: Scopes = .{};
        for (result.value.scopes) |scope| {
            scopes.toggle(scope);
        }

        token.* = .{
            .access = try allocator.dupe(u8, result.value.access),
            .refresh = if (result.value.refresh) |refresh| try allocator.dupe(u8, refresh) else null,
            .scopes = scopes,
            .expires = result.value.expires,
        };

        return token;
    }

    pub fn mergeResponse(self: *@This(), allocator: std.mem.Allocator, content: []const u8) !void {
        const now = std.time.timestamp();

        const result = try std.json.parseFromSlice(struct {
            access_token: []const u8,
            refresh_token: ?[]const u8 = null,
            expires_in: i64,
        }, allocator, content, .{ .ignore_unknown_fields = true });
        defer result.deinit();

        if (result.value.refresh_token) |rt| {
            if (self.refresh) |refresh| allocator.free(refresh);
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
            refresh_token: ?[]const u8 = null,
            expires_in: i64,
            scope: ?[]const u8 = null
        }, allocator, content, .{ .ignore_unknown_fields = true });
        defer result.deinit();

        var scopes: Scopes = .{};
        if (result.value.scope) |scope| {
            var iter = std.mem.splitSequence(u8, scope, " ");
            while (iter.next()) |s| {
                scopes.toggle(s);
            }
        }

        const token = try allocator.create(@This());

        token.* = .{
            .access = try allocator.dupe(u8, result.value.access_token),
            .refresh = if (result.value.refresh_token) |refresh| try allocator.dupe(u8, refresh) else null,
            .scopes = scopes,
            .expires = now + result.value.expires_in,
        };

        return token;
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.access);
        if (self.refresh) |refresh| allocator.free(refresh);
        allocator.destroy(self);
    }

    pub fn inScope(self: *const @This(), scopes: ?Scopes) bool {
        if (scopes) |expected| {
            return self.scopes == expected;
        } else if (@as(u17, @bitCast(self.scopes)) > 0) {
            return false;
        }
        return true;
    }
};

pub const REDIRECT_CONTENT: []const u8 = "<html><head><script>window.onload = () => { window.close(); }</script></head><body></body></html>";

pub const Scopes = packed struct(u17) {
    user_read_email: bool = false,
    user_read_private: bool = false,
    user_top_read: bool = false,
    user_read_recently_played: bool = false,
    user_follow_read: bool = false,
    user_library_read: bool = false,
    user_read_currently_playing: bool = false,
    user_read_playback_state: bool = false,
    user_read_playback_position: bool = false,
    playlist_read_collaborative: bool = false,
    playlist_read_private: bool = false,
    user_follow_modify: bool = false,
    user_library_modify: bool = false,
    user_modify_playback_state: bool = false,
    playlist_modify_public: bool = false,
    playlist_modify_private: bool = false,
    ugc_image_upload: bool = false,

    pub const Scope = std.meta.FieldEnum(@This());

    pub fn fromStringList(list: [][]const u8) @This() {
        var result: @This() = .{};
        for (list) |item| {
            result.toggle(item);
        }
        return result;
    }

    pub fn toggle(self: *@This(), value: []const u8) void {
        if (scope(value)) |v| {
            switch (v) {
                .user_read_email => self.user_read_email = true,
                .user_read_private => self.user_read_private = true,
                .user_top_read => self.user_top_read = true,
                .user_read_recently_played => self.user_read_recently_played = true,
                .user_follow_read => self.user_follow_read = true,
                .user_library_read => self.user_library_read = true,
                .user_read_currently_playing => self.user_read_currently_playing = true,
                .user_read_playback_state => self.user_read_playback_state = true,
                .user_read_playback_position => self.user_read_playback_position = true,
                .playlist_read_collaborative => self.playlist_read_collaborative = true,
                .playlist_read_private => self.playlist_read_private = true,
                .user_follow_modify => self.user_follow_modify = true,
                .user_library_modify => self.user_library_modify = true,
                .user_modify_playback_state => self.user_modify_playback_state = true,
                .playlist_modify_public => self.playlist_modify_public = true,
                .playlist_modify_private => self.playlist_modify_private = true,
                .ugc_image_upload => self.ugc_image_upload = true,
            }
        }
    }

    pub fn scope(value: []const u8) ?Scope {
        if (std.mem.eql(u8, value, "user-read-email")) return .user_read_email;
        if (std.mem.eql(u8, value, "user-read-private")) return .user_read_private;
        if (std.mem.eql(u8, value, "user-top-read")) return .user_top_read;
        if (std.mem.eql(u8, value, "user-read-recently-played")) return .user_read_recently_played;
        if (std.mem.eql(u8, value, "user-follow-read")) return .user_follow_read;
        if (std.mem.eql(u8, value, "user-library-read")) return .user_library_read;
        if (std.mem.eql(u8, value, "user-read-currently-playing")) return .user_read_currently_playing;
        if (std.mem.eql(u8, value, "user-read-playback-state")) return .user_read_playback_state;
        if (std.mem.eql(u8, value, "user-read-playback-position")) return .user_read_playback_position;
        if (std.mem.eql(u8, value, "playlist-read-collaborative")) return .playlist_read_collaborative;
        if (std.mem.eql(u8, value, "playlist-read-private")) return .playlist_read_private;
        if (std.mem.eql(u8, value, "user-follow-modify")) return .user_follow_modify;
        if (std.mem.eql(u8, value, "user-library-modify")) return .user_library_modify;
        if (std.mem.eql(u8, value, "user-modify-playback-state")) return .user_modify_playback_state;
        if (std.mem.eql(u8, value, "playlist-modify-public")) return .playlist_modify_public;
        if (std.mem.eql(u8, value, "playlist-modify-private")) return .playlist_modify_private;
        if (std.mem.eql(u8, value, "ugc-image-upload")) return .ugc_image_upload;
        return null;
    }

    pub fn text(field: Scope) []const u8 {
        return switch (field) {
            .user_read_email => "user-read-email",
            .user_read_private => "user-read-private",
            .user_top_read => "user-top-read",
            .user_read_recently_played => "user-read-recently-played",
            .user_follow_read => "user-follow-read",
            .user_library_read => "user-library-read",
            .user_read_currently_playing => "user-read-currently-playing",
            .user_read_playback_state => "user-read-playback-state",
            .user_read_playback_position => "user-read-playback-position",
            .playlist_read_collaborative => "playlist-read-collaborative",
            .playlist_read_private => "playlist-read-private",
            .user_follow_modify => "user-follow-modify",
            .user_library_modify => "user-library-modify",
            .user_modify_playback_state => "user-modify-playback-state",
            .playlist_modify_public => "playlist-modify-public",
            .playlist_modify_private => "playlist-modify-private",
            .ugc_image_upload => "ugc-image-upload",
        };
    }

    pub fn format(
        self: *const @This(),
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        inline for (@typeInfo(Scope).@"enum".fields, 0..) |field, i| {
            if (@field(self, field.name)) {
                if (i > 0) try writer.writeByte(' ');
                try writer.writeAll(text(@enumFromInt(field.value)));
            }
        }
    }
};

pub const OAuth = struct {
    arena: std.heap.ArenaAllocator,

    flow: Flow,
    creds: Credentials,
    token: ?*Token = null,

    /// The authorization flow redirect uri that should be used.
    ///
    /// This value must be start with `http://localhost` or `http://127.0.0.1`
    /// and be the format `http://{host}:{port}{path}`.
    ///
    /// This value is what is sent to spotify when authorizing and what is used
    /// to listen and handle the redirect request with a mini server.
    redirect: []const u8,

    options: Options,

    pub const Options = struct {
        /// The permission scopes the api should request
        /// when aquiring and refreshing a access token.
        scopes: Scopes = .{},

        /// The content to respond with when the auth server responds
        /// to the spotify redirect uri.
        ///
        /// The default content is html that has a script that will auto
        /// close the browser tab.
        redirect_content: ?[]const u8 = null,

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
        /// Does not require a client secret to be stored
        pkce,
        /// Requires both client id and client secret to be stored
        auth_code,
        /// Requires both client id and client secret to be stored
        credential,
    };

    pub fn init(allocator: std.mem.Allocator, flow: Flow, creds: Credentials, redirect: []const u8, options: Options) @This() {
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
            .redirect = redirect,
            .options = .{
                .scopes = if (flow == .credential) .{} else options.scopes,
                .redirect_content = options.redirect_content,
                .cache_path = options.cache_path,
                .auto_refresh = options.auto_refresh,
            },
        };
    }

    pub fn initEnv(allocator: std.mem.Allocator, flow: Flow, options: Options) !@This() {
        var arena = std.heap.ArenaAllocator.init(allocator);
        const allo = arena.allocator();

        var env_vars = try dotenvy.parse(allo, null);
        defer env_vars.deinit();

        const id = if (env_vars.get("ZOTIFY_CLIENT_ID")) |id| try allo.dupe(u8, id) else return error.MissingZotifyClientId;
        const secret = if (env_vars.get("ZOTIFY_CLIENT_SECRET")) |secret| try allo.dupe(u8, secret) else null;
        const redirect_var = env_vars.get("ZOTIFY_REDIRECT_URI") orelse return error.MissingZotifyRedirectUri;

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

        const redirect = try allo.alloc(u8, redirect_var.len);
        @memcpy(redirect, redirect_var);

        return .{
            .arena = arena,
            .flow = flow,
            .creds = Credentials.init(id, secret),
            .token = token,
            .redirect = redirect,
            .options = .{
                .scopes = if (flow == .credential) .{} else options.scopes,
                .redirect_content = options.redirect_content,
                .cache_path = options.cache_path,
                .auto_refresh = options.auto_refresh,
            },
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
        if (self.token == null or !self.token.?.inScope(self.options.scopes)) {
            try self.fetchToken();
            try self.saveToken();
        } else if (self.token.?.expires <= std.time.timestamp()) {
            if (self.token.?.refresh == null) {
                try self.fetchToken();
            } else {
                self.refreshToken() catch |err| switch (err) {
                    error.InvalidGrant => { try self.fetchToken(); },
                    else => return err,
                };
            }
            try self.saveToken();
        }
    }

    fn refreshToken(self: *@This()) !void {
        log.debug("refreshing auth token", .{});
        const allocator = self.arena.allocator();

        var req = try request.Request.post(allocator, "https://accounts.spotify.com/api/token", &.{});
        defer req.deinit();

        if (self.flow == .auth_code) {
            try req.basicAuth(self.creds.id, self.creds.secret.?);
        }

        {
            var params = request.QueryMap.init(allocator);
            try params.put("grant_type", "refresh_token");
            try params.put("refresh_token", self.token.?.refresh.?);
            try params.put("client_id", self.creds.id);
            defer params.deinit();

            try req.form(&params);
        }

        var response = try req.send(allocator);
        defer response.deinit();

        if (response.status() == .ok) {
            const body = try response.body(allocator, 8192);
            defer allocator.free(body);

            try self.token.?.mergeResponse(allocator, body);
        } else {
            const body = try response.body(allocator, 8192);
            defer allocator.free(body);

            std.debug.print("{s}\n", .{body});

            return error.InvalidGrant;
        }
    }

    fn fetchToken(self: *@This()) !void {
        log.debug("fetching new auth token", .{});
        switch (self.flow) {
            .pkce => {
                const flow = try PkceFlow(67).init();
                const allocator = self.arena.allocator();

                const token = try flow.handshake(allocator, &self.creds, self.redirect, &self.options);
                defer allocator.free(token);

                if (self.token) |t| t.deinit(allocator);
                self.token = try Token.fromResponse(allocator, token);
            },
            .auth_code => {
                const allocator = self.arena.allocator();

                const token = try AuthCodeFlow.handshake(allocator, &self.creds, self.redirect, &self.options);
                defer allocator.free(token);

                if (self.token) |t| t.deinit(allocator);
                self.token = try Token.fromResponse(allocator, token);
            },
            .credential => {
                const allocator = self.arena.allocator();

                const token = try CredentialFlow.handshake(allocator, &self.creds);
                defer allocator.free(token);

                if (self.token) |t| t.deinit(allocator);
                self.token = try Token.fromResponse(allocator, token);
            }
        }
    }
};
