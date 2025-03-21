const std = @import("std");

const StringMap = std.StringArrayHashMapUnmanaged([]const u8);

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

    pub fn put(self: *@This(), key: []const u8, value: []const u8) !void {
        const allocator = self.arena.allocator();
        const entry = try self.entries.getOrPut(allocator, try allocator.dupe(u8, key));
        if (entry.found_existing) {
            allocator.free(entry.value_ptr.*);
        }

        entry.value_ptr.* = try allocator.dupe(u8, value);
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
