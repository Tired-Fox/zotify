const std = @import("std");

const log = std.log.scoped(.zotify_oauth);

const open = @import("open");
const oauth = @import("../oauth.zig");
const request = @import("../request.zig");

const randString = oauth.randString;
const Credentials = oauth.Credentials;
const Token = oauth.Token;

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

        pub fn handshake(self: *const @This(), allocator: std.mem.Allocator, creds: *const Credentials) ![]const u8 {
            const address = std.net.Address.parseIp("127.0.0.1", 8000) catch unreachable;
            var server = try address.listen(.{});

            const auth_req = req: {
                var params = request.QueryMap.init(allocator);
                defer params.deinit();
                try params.put("client_id", creds.id);
                try params.put("response_type", "code");
                try params.put("redirect_uri", "http://localhost:8000/zotify/pkce");
                try params.put("state", &self.state);
                try params.put("code_challenge_method", "S256");
                try params.put("code_challenge", &self.challenge);
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

                    if (!self.verifyState(state)) {
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
                try params.put("state", &self.state);
                try params.put("client_id", creds.id);
                try params.put("code_verifier", &self.verifier);
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
                    return try r.reader().readAllAlloc(allocator, @intCast(response.content_length orelse 8192));
                } else {
                    return error.ErrorFetchingAuthenticationToken;
                }
            }

            return error.ErrorFetchingAuthenticationToken;
        }
    };
}
