const std = @import("std");
const print = std.debug.print;

const open = @import("open");
const dotenvy = @import("dotenvy");

const Token = struct {
    access: []const u8,
    refresh: []const u8,
    timestamp: u32,
};

const Credentials = struct {
    id: []const u8,
    secret: []const u8,

    pub fn init(id: []const u8, secret: []const u8) @This() {
        return .{ .id = id, .secret = secret };
    }
};

const OAuth = struct {
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
                // Verifier 
                const verifier = randString(43, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-~");
                print("VERIFIER: {any}\n", .{ verifier });

                // Challenge
                var hasher = std.crypto.hash.sha2.Sha256.init(.{});
                hasher.update(&verifier);
                const hash = hasher.finalResult();
                print("HASH: {any}\n", .{ hash });

                const allocator = self.arena.allocator();
                const Encoder = std.base64.url_safe_no_pad.Encoder;
                const out = try allocator.alloc(u8, Encoder.calcSize(hash.len));
                // This is what is sent in the request
                const base64 = Encoder.encode(out, &hash);
                print("STATE: {s}\n", .{ base64 });


                const address = std.net.Address.parseIp("127.0.0.1", 8000) catch unreachable;
                var server = try address.listen(.{});

                const auth_req = try std.fmt.allocPrint(allocator, "https://accounts.spotify.com/authorize?client_id={s}&response_type=code&redirect_uri={s}&state={s}&code_challenge_method=S256&code_challenge={s}", .{
                    self.creds.id,
                    "http%3A%2F%2Flocalhost%3A8000%2Fzotify%2Fpkce",
                    verifier,
                    base64,
                    // "%20"
                });
                defer allocator.free(auth_req);

                try open.that(auth_req);

                const log = std.log.scoped(.server);
                log.info("listening for 127.0.0.1:8000/zotify/pkce\n", .{});
 
                var buffer: [1024]u8 = undefined;
                var conn = std.http.Server.init(try server.accept(), &buffer);
                defer conn.connection.stream.close();

                log.info("handline new connection\n", .{});

                var request = try conn.receiveHead();
                const target = request.head.target;

                if (std.mem.startsWith(u8, target, "/zotify/pkce?")) {
                    const url = try std.fmt.allocPrint(allocator, "http://127.0.0.1:8000{s}", .{ target });
                    defer allocator.free(url);
                    const uri = try std.Uri.parse(url);

                    if (uri.query) |q| {
                        var iter = std.mem.splitSequence(u8, q.percent_encoded, "&");
                        var query_map = std.StringArrayHashMap([]const u8).init(allocator);
                        defer query_map.deinit();

                        while (iter.next()) |item| {
                            if (std.mem.containsAtLeast(u8, item, 1, "=")) {
                                var i = std.mem.splitSequence(u8, item, "=");
                                const key = i.next().?;
                                const value = item[key.len+1..];
                                try query_map.put(key, value);
                            }
                        }

                        const state = query_map.get("state").?;
                        const code = query_map.get("code").?;

                        print("STATE: {s}\n", .{ state });
                        print("CODE: {s}\n", .{ code });
                    }

                    try request.respond("{ status: \"okay\" }", .{
                        .extra_headers = &.{
                            .{ .name = "ContentType", .value = "application/json" }
                        }
                    });
                } else {
                    try request.respond("", .{ .status = .not_found });
                }


                // challenge
                // request auth
                // request access token
            },
            else => return error.AuthenticationMethodNotImplemented,
        }
    }
};

fn randString(comptime N: usize, needle: []const u8) [N]u8 {
    // Valid lengths are 43-128
    std.debug.assert(N > 42 and N < 129);
    const rand = std.crypto.random;

    var result: [N]u8 = undefined;
    for (0..N) |i| {
        result[i] = needle[rand.intRangeLessThan(usize, 0, needle.len)];
    }
    return result;
}

pub fn main() !void {
    // Create a general purpose allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();

    var oauth = try OAuth.initEnv(gpa.allocator(), .pkce);
    defer oauth.deinit();

    print("ID: {s}\n", .{ oauth.creds.id });
    print("SECRET: {s}\n", .{ oauth.creds.secret });

    try oauth.handshake();
}
