const std = @import("std");
const print = std.debug.print;

const open = @import("open");
const dotenvy = @import("dotenvy");

pub const request = @import("request.zig");

const log = std.log.scoped(.server);

pub const Token = struct {
    arena: std.heap.ArenaAllocator,

    access: []const u8,
    refresh: []const u8,
    scopes: [][]const u8,
    expires: i64,

    const AuthToken = struct {
        access_token: []const u8,
        refresh_token: []const u8,
        expires_in: i64,
        scope: ?[]const u8 = null
    };

    pub fn fromJson(allocator: std.mem.Allocator, content: []const u8) !@This() {
        const now = std.time.timestamp();
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();

        const token = try std.json.parseFromSlice(AuthToken, allocator, content, .{ .ignore_unknown_fields = true });

        var scopes: [][]const u8 = undefined;
        if (token.value.scope) |scope| {
            var buffer = std.ArrayList([]const u8).init(arena.allocator());
            var iter = std.mem.splitSequence(u8, scope, ",");
            while (iter.next()) |s| {
                try buffer.append(s);
            }

            scopes = try buffer.toOwnedSlice();
        } else {
            scopes = try allocator.alloc([]const u8, 0);
        }


        return .{
            .access = try arena.allocator().dupe(u8, token.value.access_token),
            .refresh = try arena.allocator().dupe(u8, token.value.refresh_token),
            .scopes = scopes,
            .expires = now + token.value.expires_in,
            .arena = arena,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.arena.deinit();
    }
};

pub const Credentials = struct {
    id: []const u8,
    secret: []const u8,

    pub fn init(id: []const u8, secret: []const u8) @This() {
        return .{ .id = id, .secret = secret };
    }
};

pub const OAuth = struct {
    arena: std.heap.ArenaAllocator,

    method: Method,
    creds: Credentials,
    token: ?Token = null,

    pub const Method = enum {
        pkce,
        code,
        credential,
        implicit
    };

    pub fn init(allocator: std.mem.Allocator, method: Method, creds: Credentials) @This() {
        return .{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .method = method,
            .creds = creds,
        };
    }

    pub fn initEnv(allocator: std.mem.Allocator, method: Method) !@This() {
        var arena = std.heap.ArenaAllocator.init(allocator);
        const allo = arena.allocator();

        var env_vars = try dotenvy.parse(allo, null);
        defer env_vars.deinit();

        const id = if (env_vars.get("ZOTIFY_ID")) |id| try allo.dupe(u8, id) else return error.MissingZotifyIdEnvVariable;
        const secret = if (env_vars.get("ZOTIFY_SECRET")) |secret| try allo.dupe(u8, secret) else return error.MissingZotifySecretEnvVariable;

        return .{
            .arena = arena,
            .method = method,
            .creds = Credentials.init(id, secret),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.arena.deinit();
    }

    pub fn handshake(self: *@This()) !void {
        switch (self.method) {
            .pkce => {
                const allocator = self.arena.allocator();
                const pkce = try PKCE(43).init();

                const address = std.net.Address.parseIp("127.0.0.1", 8000) catch unreachable;
                var server = try address.listen(.{});

                const auth_req = req: {
                    var params = request.QueryMap.init(allocator);
                    defer params.deinit();
                    try params.put("client_id", self.creds.id);
                    try params.put("response_type", "code");
                    try params.put("redirect_uri", "http://localhost:8000/zotify/pkce");
                    try params.put("state", &pkce.state);
                    try params.put("code_challenge_method", "S256");
                    try params.put("code_challenge", &pkce.challenge);
                    try params.put("scope", "user-read-playback-state");

                    break :req try std.fmt.allocPrint(
                        allocator,
                        "https://accounts.spotify.com/authorize?{s}",
                        .{ params }
                    );
                };
                defer allocator.free(auth_req);
                try open.that(auth_req);

                log.info("waiting for request at 127.0.0.1:8000/zotify/pkce", .{});
 
                var buffer: [1024]u8 = undefined;
                var conn = std.http.Server.init(try server.accept(), &buffer);
                defer conn.connection.stream.close();

                var req = try conn.receiveHead();
                const target = req.head.target;

                var code: ?[]const u8 = null;
                defer if (code) |c| allocator.free(c);
                if (std.mem.startsWith(u8, target, "/zotify/pkce?")) {
                    try req.respond("{ status: \"okay\" }", .{
                        .extra_headers = &.{
                            .{ .name = "ContentType", .value = "application/json" }
                        }
                    });

                    const url = try std.fmt.allocPrint(allocator, "http://127.0.0.1:8000{s}", .{ target });
                    defer allocator.free(url);
                    const uri = try std.Uri.parse(url);

                    if (uri.query) |q| {
                        var query = try request.QueryMap.parse(allocator, q.percent_encoded, .{});
                        defer query.deinit();

                        const state = query.get("state").?;

                        if (query.get("error")) |e| {
                            log.err("{s}", .{ e });
                            if (std.mem.eql(u8, e, "access_denied")) {
                                return error.AccessDenied;
                            }
                            return error.AuthorizationError;
                        }

                        code = try allocator.dupe(u8, query.get("code").?);

                        if (!pkce.verifyState(state)) {
                            log.err("Request state does not match verifier state", .{});
                            return error.InvalidAuthorizationState;
                        }
                    }
                } else {
                    try req.respond("", .{ .status = .not_found });
                }

                if (code) |c| {
                    var params = request.QueryMap.init(allocator);
                    try params.put("grant_type", "authorization_code");
                    try params.put("code", c);
                    try params.put("redirect_uri", "http://localhost:8000/zotify/pkce");
                    try params.put("state", &pkce.state);
                    try params.put("client_id", self.creds.id);
                    try params.put("code_verifier", &pkce.verifier);
                    defer params.deinit();

                    const uri = "https://accounts.spotify.com/api/token";
                    var client = std.http.Client { .allocator = allocator };
                    defer client.deinit();

                    var server_headers: [1024 * 1024]u8 = undefined;
                    var r = try client.open(.POST, try std.Uri.parse(uri), .{
                        .extra_headers = &.{
                            .{ .name = "Content-Type", .value = "application/x-www-form-urlencoded" }
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

                        var token = try Token.fromJson(allocator, body);
                        defer token.deinit();

                        print("Access: {s}\n", .{token.access});
                        print("Refresh: {s}\n", .{token.refresh});
                        print("Scopes:\n", .{});
                        for (token.scopes) |scope| {
                            print("{s}\n", .{scope});
                        }
                    } else {
                        return error.ErrorFetchingAuthenticationToken;
                    }
                }

                // challenge
                // request auth
                // request access token
            },
            else => return error.AuthenticationMethodNotImplemented,
        }
    }
};

pub fn PKCE(N: usize) type {
    std.debug.assert(N > 42 and N < 129);

    const Sha256 = std.crypto.hash.sha2.Sha256;
    const Encoder = std.base64.url_safe_no_pad.Encoder;

    const clen = Encoder.calcSize(Sha256.digest_length);

    return struct {
        state: [32]u8,

        verifier: [N]u8,
        hash: [Sha256.digest_length]u8,
        challenge: [clen:0]u8,

        pub fn init() !@This() {
            const verifier = randString(N, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789");

            var hasher = Sha256.init(.{});
            hasher.update(&verifier);
            const hash = hasher.finalResult();

            var out: [clen:0]u8 = [_:0]u8 { 0 } ** clen;
            // This is what is sent in the request
            _ = Encoder.encode(&out, &hash);

            return .{
                .state = randString(32, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"),
                .verifier = verifier,
                .hash = hash,

                .challenge = out, 
            };
        }

        pub fn deinit(self: *@This()) void {
            self.arena.deinit();
        }

        pub fn verifyState(self: *const @This(), other: []const u8) bool {
            return std.mem.eql(u8, &self.state, other);
        }
    };
}

fn randString(comptime N: usize, needle: []const u8) [N]u8 {
    // Valid lengths are 43-128
    const rand = std.crypto.random;

    var result: [N]u8 = undefined;
    for (0..N) |i| {
        result[i] = needle[rand.intRangeLessThan(usize, 0, needle.len)];
    }
    return result;
}
