const std = @import("std");

const log = std.log.scoped(.zotify_oauth);

const open = @import("open");
const oauth = @import("../oauth.zig");
const request = @import("../request.zig");

const randString = oauth.randString;
const Credentials = oauth.Credentials;
const Token = oauth.Token;

pub const CredentialFlow = struct {
    pub fn handshake(allocator: std.mem.Allocator, creds: *const Credentials) ![]const u8 {
        var token_req = try request.Request.post(allocator, "https://accounts.spotify.com/api/token", &.{});
        defer token_req.deinit();

        try token_req.basicAuth(creds.id, creds.secret);

        {
            var params = request.QueryMap.init(allocator);
            try params.put("grant_type", "client_credentials");
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

        return error.ErrorFetchingAuthenticationToken;
    }
};
