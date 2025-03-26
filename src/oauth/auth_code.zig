const std = @import("std");

const log = std.log.scoped(.zotify_oauth);

const open = @import("open");
const oauth = @import("../oauth.zig");
const request = @import("../request.zig");

const randString = oauth.randString;
const Credentials = oauth.Credentials;
const Token = oauth.Token;

pub const AuthCode = struct {
    pub fn handshake(allocator: std.mem.Allocator, creds: *const Credentials, redirect: []const u8, options: *const oauth.OAuth.Options) ![]const u8 {
        const redirect_uri = try std.Uri.parse(redirect);  
        if (
            !std.mem.eql(u8, redirect_uri.host.?.percent_encoded, "localhost")
            and !std.mem.eql(u8, redirect_uri.host.?.percent_encoded, "127.0.0.1")
        ) {
            return error.RedirectHostMustBeLocalhost;
        }

        const address = std.net.Address.parseIp("127.0.0.1", redirect_uri.port.?) catch unreachable;
        const auth_state = randString(67, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789");
        var server = try address.listen(.{});

        const auth_req = req: {
            var params = request.QueryMap.init(allocator);
            defer params.deinit();
            try params.put("client_id", creds.id);
            try params.put("response_type", "code");
            try params.put("redirect_uri", redirect);
            try params.put("state", &auth_state);
            try params.put("scope", options.scopes);

            break :req try std.fmt.allocPrint(
                allocator,
                "https://accounts.spotify.com/authorize?{s}",
                .{ params }
            );
        };
        defer allocator.free(auth_req);
        try open.that(auth_req);

        var buffer: [8192]u8 = undefined;
        var conn = std.http.Server.init(try server.accept(), &buffer);
        defer conn.connection.stream.close();

        var req = try conn.receiveHead();
        const target = req.head.target;

        var code: ?[]const u8 = null;
        defer if (code) |c| allocator.free(c);
        if (std.mem.startsWith(u8, target, redirect_uri.path.percent_encoded)) {
            try req.respond(options.redirect_content orelse oauth.REDIRECT_CONTENT, .{});

            const url = try std.fmt.allocPrint(allocator, "{s}://{s}:{d}{s}", .{
                redirect_uri.scheme,
                redirect_uri.host.?.percent_encoded,
                redirect_uri.port.?,
                target,
            });
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

                if (!std.mem.eql(u8, &auth_state, state)) {
                    log.err("Request state does not match verifier state", .{});
                    return error.InvalidAuthorizationState;
                }
            }
        } else {
            try req.respond("", .{ .status = .not_found });
        }

        if (code) |c| {
            var token_req = try request.Request.post(allocator, "https://accounts.spotify.com/api/token", &.{});
            defer token_req.deinit();

            try token_req.basicAuth(creds.id, creds.secret);

            {
                var params = request.QueryMap.init(allocator);
                try params.put("grant_type", "authorization_code");
                try params.put("code", c);
                try params.put("redirect_uri", redirect);
                defer params.deinit();

                try token_req.form(&params);
            }

            var response = try token_req.send(allocator);
            defer response.deinit();

            if (response.status() == .ok) {
                return try response.body(allocator, 8192);
            } else {
                return error.AccessDenied;
            }
        }

        return error.ErrorFetchingAuthenticationToken;
    }
};
