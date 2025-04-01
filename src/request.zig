const std = @import("std");

const StringMap = std.StringArrayHashMapUnmanaged([]const u8);

/// A query map is the query values at the end of a uri
///
/// This object will encode the value of the key value pair
/// *ONLY* when it is formated to a string.
///
/// This map owns all the memory of the allocated entries
pub const QueryMap = struct {
    arena: std.heap.ArenaAllocator,
    entries: StringMap,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .entries = StringMap.empty,
            .arena = std.heap.ArenaAllocator.init(allocator)
        };
    }

    pub fn deinit(self: *@This()) void {
        self.arena.deinit();
    }

    pub fn put(self: *@This(), key: []const u8, value: anytype) !void {
        const allocator = self.arena.allocator();
        const entry = try self.entries.getOrPut(allocator, try allocator.dupe(u8, key));
        if (entry.found_existing) {
            allocator.free(entry.value_ptr.*);
        }

        entry.value_ptr.* = try std.fmt.allocPrint(allocator, "{s}", .{ value });
    }

    pub fn get(self: *@This(), key: []const u8) ?[]const u8 {
        return self.entries.get(key);
    }

    pub fn parse(allocator: std.mem.Allocator, source: []const u8, options: DecodeOptions) !@This() {
        var query: @This() = .init(allocator);
        errdefer query.deinit();

        const allo = query.arena.allocator();

        var entries = std.mem.splitSequence(u8, source, "&");
        while (entries.next()) |entry| {
            var iter = std.mem.splitSequence(u8, entry, "=");
            const key = iter.next().?;
            const value = try percentDecode(allo, iter.next().?, options);

            try query.entries.put(
                allo,
                try allo.dupe(u8, key),
                value,
            );
        }

        return query;
    }

    pub fn stringify(self: *const @This(), writer: anytype) !void {
        try writer.print("{s}", .{ self });
    }

    pub fn stringifyAlloc(self: *const @This(), allocator: std.mem.Allocator) ![]const u8 {
        return try std.fmt.allocPrint(allocator, "{s}", .{ self });
    }

    pub fn format(
        self: *const @This(),
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            if (iter.index > 1) try writer.writeByte('&');
            try writer.print("{s}=", .{ entry.key_ptr.* });
            try percentEncodeWriter(writer, entry.value_ptr.*, .{});
        }
    }
};

/// A query map is the query values at the end of a uri
///
/// This object will encode the value of the key value pair
/// *ONLY* when it is formated to a string.
///
/// The caller owns all the memory allocated entries
pub const QueryMapUnmanaged = struct {
    items: StringMap = StringMap.empty,

    pub const empty: @This() = .{};

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        var it = self.items.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.items.deinit(allocator);
    }

    fn formatValue(value: anytype, writer: anytype) !void {
        switch (@typeInfo(@TypeOf(value))) {
            .float, .comptime_float, .comptime_int, .int => {
                try writer.print("{d}", .{ value });
            },
            .bool => {
                try writer.print("{?}", .{ value });
            },
            .pointer => |p| {
                if (p.size == .slice) {
                    switch (p.child) {
                        u8 => try writer.print("{s}", .{ value }),
                        else => {
                            for (value, 0..) |v, i| {
                                if (i > 0) try writer.writeByte(',');
                                try formatValue(v, writer);
                            }
                        }
                    }
                } else {
                    try writer.print("{s}", .{ value });
                }
            },
            else => {
                try writer.print("{s}", .{ value });
            }
        }
    }

    pub fn put(self: *@This(), allocator: std.mem.Allocator, key: []const u8, value: anytype) !void {
        const entry = try self.items.getOrPut(allocator, try allocator.dupe(u8, key));
        if (entry.found_existing) {
            allocator.free(entry.value_ptr.*);
        }

        var v = std.ArrayList(u8).init(allocator);
        try formatValue(value, v.writer());
        entry.value_ptr.* = try v.toOwnedSlice();
    }

    pub fn get(self: *@This(), key: []const u8) ?[]const u8 {
        return self.items.get(key);
    }

    pub fn parse(allocator: std.mem.Allocator, source: []const u8, options: DecodeOptions) !@This() {
        var query: @This() = .empty;
        errdefer query.deinit(allocator);

        var entries = std.mem.splitSequence(u8, source, "&");
        while (entries.next()) |entry| {
            var iter = std.mem.splitSequence(u8, entry, "=");
            const key = iter.next().?;
            const value = try percentDecode(allocator, iter.next().?, options);

            try query.items.put(
                allocator,
                try allocator.dupe(u8, key),
                value,
            );
        }

        return query;
    }

    pub fn stringify(self: *const @This(), writer: anytype) !void {
        try writer.print("{s}", .{ self });
    }

    pub fn stringifyAlloc(self: *const @This(), allocator: std.mem.Allocator) ![]const u8 {
        return try std.fmt.allocPrint(allocator, "{s}", .{ self });
    }

    pub fn format(
        self: *const @This(),
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        var iter = self.items.iterator();
        while (iter.next()) |entry| {
            if (iter.index > 1) try writer.writeByte('&');
            try writer.print("{s}=", .{ entry.key_ptr.* });
            try percentEncodeWriter(writer, entry.value_ptr.*, .{});
        }
    }
};

pub const EncodeOptions = struct {
    alpha: bool = false,
    digit: bool = false,
    space: enum(u3) { raw, encode, plus } = .encode,

    @"!": bool = true,
    @"\"": bool = true,
    @"#": bool = true,
    @"$": bool = true,
    @"%": bool = true,
    @"&": bool = true,
    @"'": bool = true,
    @"(": bool = true,
    @")": bool = true,
    @"*": bool = true,
    @",": bool = true,
    @"/": bool = true,
    @":": bool = true,
    @";": bool = true,
    @"<": bool = true,
    @"=": bool = true,
    @">": bool = true,
    @"?": bool = true,
    @"+": bool = true,
    @"-": bool = false,
    @"_": bool = false,
    @".": bool = false,
    @"@": bool = true,
    @"[": bool = true,
    @"\\": bool = true,
    @"]": bool = true,
    @"^": bool = true,
    @"`": bool = true,
    @"{": bool = true,
    @"|": bool = true,
    @"}": bool = true,
    other: bool = true,

    pub fn shouldEncode(self: *const @This(), codepoint: []const u8) bool {
        if (codepoint.len == 1) {
            if (codepoint[0] == ' ') return self.space != .raw;
            if (std.ascii.isAlphabetic(codepoint[0])) return self.alpha;
            if (std.ascii.isDigit(codepoint[0])) return self.digit;

            switch (codepoint[0]) {
                '!' => return self.@"!",
                '\"' => return self.@"\"",
                '#' => return self.@"#",
                '$' => return self.@"$",
                '%' => return self.@"%",
                '&' => return self.@"&",
                '\'' => return self.@"'",
                '(' => return self.@"(",
                ')' => return self.@")",
                '*' => return self.@"*",
                ',' => return self.@",",
                '/' => return self.@"/",
                ':' => return self.@":",
                ';' => return self.@";",
                '<' => return self.@"<",
                '=' => return self.@"=",
                '>' => return self.@">",
                '?' => return self.@"?",
                '@' => return self.@"@",
                '[' => return self.@"[",
                '\\' => return self.@"\\",
                ']' => return self.@"]",
                '^' => return self.@"^",
                '`' => return self.@"`",
                '{' => return self.@"{",
                '|' => return self.@"|",
                '}' => return self.@"}",
                '+' => return self.@"+",
                '-' => return self.@"-",
                '.' => return self.@".",
                '_' => return self.@"_",
                else => {}
            }
        }
        return self.other;
    }
};

pub fn percentEncode(allocator: std.mem.Allocator, source: []const u8, options: EncodeOptions) ![]const u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    errdefer buffer.deinit();
    try percentEncodeWriter(buffer.writer(), source, options);
    return try buffer.toOwnedSlice();
}

pub fn percentEncodeWriter(writer: anytype, source: []const u8, options: EncodeOptions) !void {
    // Force `+` to be encoded if ` ` is encoded as `+` to avoid conflict
    if (options.space == .plus and !options.@"+") return error.EncodingConflictSpaceAndPlus;

    var char_iter = std.unicode.Utf8Iterator { .i = 0, .bytes = source };
    while (char_iter.nextCodepointSlice()) |codepoint| {
        if (options.shouldEncode(codepoint)) {
            if (std.mem.eql(u8, codepoint, " ") and options.space == .plus) {
                try writer.writeByte('+');
            } else {
                for (codepoint) |byte| {
                    try writer.print("%{X}", .{ byte });
                }
            }
        } else {
            try writer.writeAll(codepoint);
        }
    }
}

pub const DecodeOptions = struct {
    space: enum { plus, percent } = .percent,
};

pub fn percentDecode(allocator: std.mem.Allocator, source: []const u8, options: DecodeOptions) ![]const u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    errdefer buffer.deinit();
    try percentDecodeWriter(buffer.writer(), source, options);
    return try buffer.toOwnedSlice();
}

pub fn percentDecodeWriter(writer: anytype, source: []const u8, options: DecodeOptions) !void {
    var i: usize = 0;
    while (i < source.len) : (i+=1) {
        if (source[i] == '%') {
            if (i + 2 >= source.len) return error.InvalidEncoding;
            try writer.writeByte(try std.fmt.parseInt(u8, source[i+1..i+3], 16));
            i += 2;
        } else if (source[i] == '+' and options.space == .plus) {
            try writer.writeByte(' ');
        } else {
            try writer.writeByte(source[i]);
        }
    }
}

/// Http request conveniance wrapper
pub const Request = struct {
    arena: std.heap.ArenaAllocator,

    method: std.http.Method,
    uri: []const u8,

    headers: std.ArrayListUnmanaged(std.http.Header) = .empty,
    query: QueryMapUnmanaged = .empty,
    content: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, method: std.http.Method, uri: []const u8, headers: []const std.http.Header) !@This() {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();

        var h = std.ArrayListUnmanaged(std.http.Header).empty;
        try h.appendSlice(arena.allocator(), headers);

        return .{
            .arena = arena,
            .method = method,
            .uri = uri,
            .headers = h,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.arena.deinit();
    }

    pub fn get(allocator: std.mem.Allocator, uri: []const u8, headers: []const std.http.Header) !@This() {
        return try @This().init(allocator, .GET, uri, headers);
    }

    pub fn post(allocator: std.mem.Allocator, uri: []const u8, headers: []const std.http.Header) !@This() {
        return try @This().init(allocator, .POST, uri, headers);
    }

    pub fn put(allocator: std.mem.Allocator, uri: []const u8, headers: []const std.http.Header) !@This() {
        return try @This().init(allocator, .PUT, uri, headers);
    }

    pub fn delete(allocator: std.mem.Allocator, uri: []const u8, headers: []const std.http.Header) !@This() {
        return try @This().init(allocator, .DELETE, uri, headers);
    }

    /// Add a query parameter to the uri
    pub fn param(self: *@This(), key: []const u8, value: anytype) !void {
        try self.query.put(self.arena.allocator(), key, value);
    }

    /// Add an `Authorization` header with the format `Basic <base64:'{username}:{password}'>`
    pub fn basicAuth(self: *@This(), username: []const u8, password: ?[]const u8) !void {
        const Encoder = std.base64.url_safe_no_pad.Encoder;
        const allocator = self.arena.allocator();

        var basic = std.ArrayList(u8).init(allocator);
        defer basic.deinit();

        try basic.writer().print("{s}:", .{ username });
        if (password) |p| {
            try basic.writer().print("{s}", .{ p });
        }

        const clen = Encoder.calcSize(basic.items.len);
        const out: []u8 = try allocator.alloc(u8, clen);
        defer allocator.free(out);

        try self.headers.append(allocator, .{
            .name = "Authorization",
            .value = try std.fmt.allocPrint(allocator, "Basic {s}", .{ Encoder.encode(out, basic.items) })
        });
    }

    /// Add an `Authorization` header with the format `Bearer {token}`
    pub fn bearerAuth(self: *@This(), token: []const u8) !void {
        try self.headers.append(self.arena.allocator(), .{
            .name = "Authorization",
            .value = try std.fmt.allocPrint(self.arena.allocator(), "Bearer {s}", .{ token })
        });
    }

    pub fn header(self: *@This(), key: []const u8, value: []const u8) !void {
        try self.headers.append(self.arena.allocator(), .{
            .name = key,
            .value = value,
        });
    }

    /// Format the content passed in as a string body with no additional `Content-Type` headers
    pub fn body(self: *@This(), content: anytype) !void {
        if (self.content) |b| self.arena.allocator().free(b);
        self.content = try std.fmt.allocPrint(self.arena.allocator(), "{s}", .{ content });
    }

    /// Format the content passed in as a string body with an addtional `Content-Type` header
    /// of `application/x-www-form-urlencoded`
    pub fn form(self: *@This(), content: anytype) !void {
        if (self.content) |b| self.arena.allocator().free(b);
        self.content = try std.fmt.allocPrint(self.arena.allocator(), "{s}", .{ content });
        try self.headers.append(self.arena.allocator(), .{ .name = "Content-Type", .value = "application/x-www-form-urlencoded" });
    }

    /// Format the content passed in as a string body with an addtional `Content-Type` header
    /// of `application/json`
    pub fn json(self: *@This(), content: anytype) !void {
        const T = @TypeOf(content);
        if (self.content) |b| self.arena.allocator().free(b);

        if (@typeInfo(T) == .@"struct" and @typeInfo(T).@"struct".fields.len == 0) {
            self.content = "{}";
        } else {
            self.content = try std.json.stringifyAlloc(self.arena.allocator(), content, .{ });
        }

        try self.headers.append(self.arena.allocator(), .{ .name = "Content-Type", .value = "application/json" });
    }

    /// Send the request and wait for the response
    ///
    /// It is a light wrapper around `std.http.Client.Request` and `std.http.Client.Response`
    /// to make parsing the body easier. It also contains all the memory allocated for the
    /// response so calling `deinit` will free all related memory.
    ///
    /// The response will have all it's memory allocated to the passed in allocator
    /// so that this request instance can have `deinit` called.
    pub fn send(self: *@This(), alloc: std.mem.Allocator) !Response {
        var arena = std.heap.ArenaAllocator.init(alloc);
        errdefer arena.deinit();
        const allocator = arena.allocator();

        var client = std.http.Client { .allocator = allocator };

        const uri = uri: {
            var url = std.ArrayList(u8).init(allocator);
            try url.appendSlice(self.uri);

            if (self.query.items.entries.len > 0) {
                try url.append('?');
                try url.writer().print("{s}", .{ self.query });
            }

            break :uri try std.Uri.parse(try url.toOwnedSlice());
        };

        if (self.method != .GET and self.method != .HEAD) {
            try self.headers.append(allocator, .{
                .name = "Content-Length",
                .value = try std.fmt.allocPrint(allocator, "{d}", .{
                    if (self.content) |cnt| cnt.len else 0
                })
            });
        }

        const header_buffer = try allocator.alloc(u8, 8192);
        const headers = try self.headers.toOwnedSlice(allocator);

        var req = try client.open(self.method, uri, .{
            .server_header_buffer = header_buffer,
            .extra_headers = headers 
        });

        if (self.method.requestHasBody() and self.content != null) {
            req.transfer_encoding = .{ .content_length = self.content.?.len };
        }

        try req.send();
        if (self.content) |content| try req.writer().writeAll(content);
        try req.finish();
        try req.wait();

        return .{
            .arena = arena,
            .request = req,
            .response = req.response,
        };
    }
};

/// Http response conveniance wrapper
pub const Response = struct {
    arena: std.heap.ArenaAllocator,
    request: std.http.Client.Request,
    response: std.http.Client.Response,

    /// Free all memory related to the response
    pub fn deinit(self: *@This()) void {
        self.request.deinit();
        self.arena.deinit();
    }

    /// The http response state
    pub fn status(self: *const @This()) std.http.Status {
        return self.response.status;
    }

    /// Get an iterator over all response headers
    pub fn headers(self: *const @This()) std.http.HeaderIterator {
        return self.response.iterateHeaders();
    }

    /// Read the body of the response as text.
    ///
    /// Caller owns the memory and is repsonsible for freeing it.
    pub fn body(self: *@This(), allocator: std.mem.Allocator) ![]const u8 {
        if (self.response.content_length) |clen| {
            return try self.request
                .reader()
                .readAllAlloc(allocator, @intCast(clen));
        }
        var buffer = std.ArrayList(u8).init(allocator);
        var reader = self.request.reader();
        while (true) {
            try buffer.append(reader.readByte() catch break);
        }
        return try buffer.toOwnedSlice();
    }

    /// Read the body of the response as json.
    ///
    /// Caller owns the memory and is repsonsible for freeing it.
    pub fn json(self: *@This(), allocator: std.mem.Allocator, T: type) !std.json.Parsed(T) {
        const content = try self.body(allocator);
        defer allocator.free(content);

        return try std.json.parseFromSlice(T, allocator, content, .{ .ignore_unknown_fields = true });
    }

    /// Read the body of the response as a form.
    ///
    /// Caller owns the memory and is repsonsible for freeing it.
    pub fn form(self: *@This(), allocator: std.mem.Allocator) !QueryMapUnmanaged {
        const content = try self.body(allocator);
        defer allocator.free(content);

        return try QueryMapUnmanaged.parse(allocator, content, .{});
    }
};
