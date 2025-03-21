const std = @import("std");
const print = std.debug.print;

const zotify = @import("zotify");
const OAuth = zotify.OAuth;

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
