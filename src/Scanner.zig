const Scanner = @This();

pub const Error = Allocator.Error || error{ReadFailed};

content: std.ArrayList(u8) = .empty,
tokens: std.ArrayList(Token) = .empty,

pub fn deinit(self: *Scanner, gpa: Allocator) void {
    self.content.deinit(gpa);
    self.tokens.deinit(gpa);
}

pub fn scan(gpa: Allocator, reader: *Io.Reader) Error!Scanner {
    var scanner: Scanner = .{};
    try State.scan(gpa, reader, &scanner.content, &scanner.tokens);
    return scanner;
}

const State = struct {
    gpa: Allocator,
    reader: *Io.Reader,
    content: *std.ArrayList(u8),
    tokens: *std.ArrayList(Token),

    current: usize = 0,
    len: usize = 0,

    start: Cursor = .{ .line = 0, .col = 0 },
    end: Cursor = .{ .line = 0, .col = 0 },

    pub fn scan(
        gpa: Allocator,
        reader: *Io.Reader,
        content: *std.ArrayList(u8),
        tokens: *std.ArrayList(Token),
    ) Error!void {
        var state: State = .{
            .gpa = gpa,
            .reader = reader,
            .content = content,
            .tokens = tokens,
        };
        while (true) {
            if (try state.peek() == null) {
                try state.scanCurrent();
                try state.appendToken(.eof);
                break;
            }

            state.len += 1;
            state.end.col += 1;

            try state.scanCurrent();
        }
    }

    fn scanCurrent(self: *State) Error!void {
        if (self.current == self.content.items.len) {
            return;
        }
        switch (self.content.items[self.current]) {
            ':' => try self.appendToken(.colon),
            '*' => try self.appendToken(.star),
            '{' => try self.appendToken(.brace_left),
            '}' => try self.appendToken(.brace_right),
            '(' => try self.appendToken(.paren_left),
            ')' => try self.appendToken(.paren_right),
            ',' => try self.appendToken(.comma),
            '.' => try self.appendToken(.dot),
            '-' => if (try self.match('>')) {
                try self.appendToken(.arrow);
            },
            '_' => {
                if (!try self.identifier()) {
                    try self.appendToken(.underscore);
                }
            },
            '\n' => {
                self.current += 1;
                self.len = 0;

                self.end = .{ .line = self.end.line + 1, .col = 0 };
                self.start = self.end;
            },
            ' ' => {
                self.current += 1;
                self.len = 0;

                self.start = self.end;
            },
            else => {
                inline for ([_]struct { []const u8, Token.Type }{
                    .{ "if", .@"if" },
                    .{ "const", .@"const" },
                    .{ "volatile", .@"volatile" },
                    .{ "invoke", .invoke },
                    .{ "self", .self },
                    .{ "from", .from },
                    .{ "not", .not },
                    .{ "and", .@"and" },
                    .{ "or", .@"or" },
                }) |keyword_token| {
                    if (try self.keyword(keyword_token[0], keyword_token[1])) {
                        break;
                    }
                } else if (try self.identifier() or try self.luastr()) {
                    return;
                } else {
                    try self.unexpected();
                }
            },
        }
    }

    fn appendToken(self: *State, token_type: Token.Type) Allocator.Error!void {
        try self.tokens.append(
            self.gpa,
            .{
                .type = token_type,
                .pos = self.current,
                .len = self.len,
                .cursor = self.start,
            },
        );
        self.current += self.len;
        self.len = 0;
        self.start = self.end;
    }
    fn peek(self: *State) Error!?u8 {
        assert(self.current + self.len <= self.content.items.len);
        if (self.current + self.len == self.content.items.len) {
            try self.content.append(
                self.gpa,
                self.reader.takeByte() catch |err| switch (err) {
                    error.EndOfStream => return null,
                    else => |e| return e,
                },
            );
        }
        return self.content.items[self.current + self.len];
    }
    fn match(self: *State, expected: u8) Error!bool {
        if (try self.peek()) |c| {
            if (c == expected) {
                self.len += 1;
                self.end.col += 1;
                return true;
            }
        }
        return false;
    }
    fn keyword(
        self: *State,
        comptime expected: []const u8,
        comptime token_type: Token.Type,
    ) Error!bool {
        if (self.content.items[self.current] != expected[0]) {
            return false;
        }

        for (expected[1..]) |c| {
            if (!try self.match(c)) {
                return false;
            }
        }

        try self.appendToken(token_type);
        return true;
    }
    fn identifier(self: *State) Error!bool {
        switch (self.content.items[self.current]) {
            'a'...'z', 'A'...'Z', '_' => |start| {
                while (try self.peek()) |c| {
                    switch (c) {
                        'a'...'z', 'A'...'Z', '0'...'9', '_' => {
                            self.len += 1;
                            self.end.col += 1;
                        },
                        else => break,
                    }
                }
                if (start == '_' and self.len == 1) {
                    return false;
                }
                try self.appendToken(.identifier);
                return true;
            },
            else => return false,
        }
    }
    fn unexpected(self: *State) Error!void {
        while (try self.peek()) |c| switch (c) {
            ' ', '\n', ':' => {
                try self.appendToken(.unexpected);
                return;
            },
            else => {
                self.len += 1;
                self.end.col += 1;
            },
        };
        try self.appendToken(.unexpected);
    }
    fn luastr(self: *State) Error!bool {
        if (self.content.items[self.current] != '[') {
            return false;
        }
        const level: usize = blk: {
            var equals: usize = 0;
            while (true) {
                if (try self.match('[')) {
                    break :blk equals;
                } else if (try self.match('=')) {
                    equals += 1;
                } else {
                    return false;
                }
            }
        };

        try self.appendToken(.string_open);
        assert(self.len == 0);

        while (try self.peek()) |c| {
            self.len += 1;
            self.end.col += 1;
            if (try self.luastrRight(level)) {
                break;
            } else {
                if (c == '\n') {
                    self.end.line += 1;
                    self.end.col = 0;
                }
            }
        } else {
            try self.appendToken(.string_content);
        }

        return true;
    }

    fn luastrRight(self: *State, level: usize) Error!bool {
        if (self.content.items[self.current + self.len - 1] != ']') {
            return false;
        }
        var close_level: usize = 0;

        while (true) {
            if (try self.match(']')) {
                if (close_level == level) {
                    self.len -= close_level + 2;
                    try self.appendToken(.string_content);

                    self.len = close_level + 2;
                    self.start.col -= self.len;
                    try self.appendToken(.string_close);

                    return true;
                }
                self.len -= close_level + 1;
                self.end.col -= close_level + 1;
                return false;
            } else if (try self.match('=')) {
                close_level += 1;

                if (close_level > level) {
                    self.len -= close_level;
                    self.end.col -= close_level;
                    return false;
                }
            } else {
                self.len -= close_level;
                return false;
            }
        }
    }
};

test "Single character tokens" {
    const gpa = t.allocator;

    var reader: std.Io.Reader = .fixed(
        \\:*{}(),.
        \\,
    );
    var scanner: Scanner = try .scan(gpa, &reader);
    defer scanner.deinit(gpa);

    try t.expectEqualDeep(&[_]Token{
        .{ .type = .colon, .pos = 0, .len = 1, .cursor = .{ .line = 0, .col = 0 } },
        .{ .type = .star, .pos = 1, .len = 1, .cursor = .{ .line = 0, .col = 1 } },
        .{ .type = .brace_left, .pos = 2, .len = 1, .cursor = .{ .line = 0, .col = 2 } },
        .{ .type = .brace_right, .pos = 3, .len = 1, .cursor = .{ .line = 0, .col = 3 } },
        .{ .type = .paren_left, .pos = 4, .len = 1, .cursor = .{ .line = 0, .col = 4 } },
        .{ .type = .paren_right, .pos = 5, .len = 1, .cursor = .{ .line = 0, .col = 5 } },
        .{ .type = .comma, .pos = 6, .len = 1, .cursor = .{ .line = 0, .col = 6 } },
        .{ .type = .dot, .pos = 7, .len = 1, .cursor = .{ .line = 0, .col = 7 } },
        .{ .type = .comma, .pos = 9, .len = 1, .cursor = .{ .line = 1, .col = 0 } },
        .{ .type = .eof, .pos = 10, .len = 0, .cursor = .{ .line = 1, .col = 1 } },
    }, scanner.tokens.items);
    try t.expectEqualStrings(",", scanner.tokens.items[8].lexeme(scanner.content.items));
    try t.expectEqualStrings("", scanner.tokens.items[9].lexeme(scanner.content.items));
}
test "Multi character tokens" {
    const gpa = t.allocator;

    var reader: std.Io.Reader = .fixed(
        \\->:->->
        \\ if const  volatile  invoke
        \\   self from
    );
    var scanner: Scanner = try .scan(gpa, &reader);
    defer scanner.deinit(gpa);

    try t.expectEqualDeep(&[_]Token{
        .{ .type = .arrow, .pos = 0, .len = 2, .cursor = .{ .line = 0, .col = 0 } },
        .{ .type = .colon, .pos = 2, .len = 1, .cursor = .{ .line = 0, .col = 2 } },
        .{ .type = .arrow, .pos = 3, .len = 2, .cursor = .{ .line = 0, .col = 3 } },
        .{ .type = .arrow, .pos = 5, .len = 2, .cursor = .{ .line = 0, .col = 5 } },
        .{ .type = .@"if", .pos = 9, .len = 2, .cursor = .{ .line = 1, .col = 1 } },
        .{ .type = .@"const", .pos = 12, .len = 5, .cursor = .{ .line = 1, .col = 4 } },
        .{ .type = .@"volatile", .pos = 19, .len = 8, .cursor = .{ .line = 1, .col = 11 } },
        .{ .type = .invoke, .pos = 29, .len = 6, .cursor = .{ .line = 1, .col = 21 } },
        .{ .type = .self, .pos = 39, .len = 4, .cursor = .{ .line = 2, .col = 3 } },
        .{ .type = .from, .pos = 44, .len = 4, .cursor = .{ .line = 2, .col = 8 } },
        .{ .type = .eof, .pos = 48, .len = 0, .cursor = .{ .line = 2, .col = 12 } },
    }, scanner.tokens.items);
    try t.expectEqualStrings("->", scanner.tokens.items[0].lexeme(scanner.content.items));
    try t.expectEqualStrings("if", scanner.tokens.items[4].lexeme(scanner.content.items));
    try t.expectEqualStrings("self", scanner.tokens.items[8].lexeme(scanner.content.items));
    try t.expectEqualStrings("from", scanner.tokens.items[9].lexeme(scanner.content.items));
}
test "Single identifier" {
    const gpa = t.allocator;

    var reader: std.Io.Reader = .fixed(
        \\simple:
    );
    var scanner: Scanner = try .scan(gpa, &reader);
    defer scanner.deinit(gpa);

    try t.expectEqualDeep(&[_]Token{
        .{ .type = .identifier, .pos = 0, .len = 6, .cursor = .{ .line = 0, .col = 0 } },
        .{ .type = .colon, .pos = 6, .len = 1, .cursor = .{ .line = 0, .col = 6 } },
        .{ .type = .eof, .pos = 7, .len = 0, .cursor = .{ .line = 0, .col = 7 } },
    }, scanner.tokens.items);
    try t.expectEqualStrings("simple", scanner.tokens.items[0].lexeme(scanner.content.items));
    try t.expectEqualStrings(":", scanner.tokens.items[1].lexeme(scanner.content.items));
}
test "Partial real" {
    const gpa = t.allocator;

    var reader: std.Io.Reader = .fixed(
        \\simple: {
        \\res0urc3s:{}
        \\}
    );
    var scanner: Scanner = try .scan(gpa, &reader);
    defer scanner.deinit(gpa);

    try t.expectEqualDeep(&[_]Token{
        .{ .type = .identifier, .pos = 0, .len = 6, .cursor = .{ .line = 0, .col = 0 } },
        .{ .type = .colon, .pos = 6, .len = 1, .cursor = .{ .line = 0, .col = 6 } },
        .{ .type = .brace_left, .pos = 8, .len = 1, .cursor = .{ .line = 0, .col = 8 } },
        .{ .type = .identifier, .pos = 10, .len = 9, .cursor = .{ .line = 1, .col = 0 } },
        .{ .type = .colon, .pos = 19, .len = 1, .cursor = .{ .line = 1, .col = 9 } },
        .{ .type = .brace_left, .pos = 20, .len = 1, .cursor = .{ .line = 1, .col = 10 } },
        .{ .type = .brace_right, .pos = 21, .len = 1, .cursor = .{ .line = 1, .col = 11 } },
        .{ .type = .brace_right, .pos = 23, .len = 1, .cursor = .{ .line = 2, .col = 0 } },
        .{ .type = .eof, .pos = 24, .len = 0, .cursor = .{ .line = 2, .col = 1 } },
    }, scanner.tokens.items);
}
test "Lua string" {
    const gpa = t.allocator;

    var reader: std.Io.Reader = .fixed(
        \\[[]]
        \\[=[]=]
        \\[=[aaa]=]
        \\[==[aaa]=]]==]
        \\[==[aaa]===]]==]
        \\
    );
    var scanner: Scanner = try .scan(gpa, &reader);
    defer scanner.deinit(gpa);

    try t.expectEqualDeep(&[_]Token{
        .{ .type = .string_open, .pos = 0, .len = 2, .cursor = .{ .line = 0, .col = 0 } },
        .{ .type = .string_content, .pos = 2, .len = 0, .cursor = .{ .line = 0, .col = 2 } },
        .{ .type = .string_close, .pos = 2, .len = 2, .cursor = .{ .line = 0, .col = 2 } },
        .{ .type = .string_open, .pos = 5, .len = 3, .cursor = .{ .line = 1, .col = 0 } },
        .{ .type = .string_content, .pos = 8, .len = 0, .cursor = .{ .line = 1, .col = 3 } },
        .{ .type = .string_close, .pos = 8, .len = 3, .cursor = .{ .line = 1, .col = 3 } },
        .{ .type = .string_open, .pos = 12, .len = 3, .cursor = .{ .line = 2, .col = 0 } },
        .{ .type = .string_content, .pos = 15, .len = 3, .cursor = .{ .line = 2, .col = 3 } },
        .{ .type = .string_close, .pos = 18, .len = 3, .cursor = .{ .line = 2, .col = 6 } },
        .{ .type = .string_open, .pos = 22, .len = 4, .cursor = .{ .line = 3, .col = 0 } },
        .{ .type = .string_content, .pos = 26, .len = 6, .cursor = .{ .line = 3, .col = 4 } },
        .{ .type = .string_close, .pos = 32, .len = 4, .cursor = .{ .line = 3, .col = 10 } },
        .{ .type = .string_open, .pos = 37, .len = 4, .cursor = .{ .line = 4, .col = 0 } },
        .{ .type = .string_content, .pos = 41, .len = 8, .cursor = .{ .line = 4, .col = 4 } },
        .{ .type = .string_close, .pos = 49, .len = 4, .cursor = .{ .line = 4, .col = 12 } },
        .{ .type = .eof, .pos = 54, .len = 0, .cursor = .{ .line = 5, .col = 0 } },
    }, scanner.tokens.items);
}
test "underscore" {
    const gpa = t.allocator;

    var reader: std.Io.Reader = .fixed(
        \\_ _a __ _a_
    );
    var scanner: Scanner = try .scan(gpa, &reader);
    defer scanner.deinit(gpa);

    try t.expectEqualDeep(&[_]Token{
        .{ .type = .underscore, .pos = 0, .len = 1, .cursor = .{ .line = 0, .col = 0 } },
        .{ .type = .identifier, .pos = 2, .len = 2, .cursor = .{ .line = 0, .col = 2 } },
        .{ .type = .identifier, .pos = 5, .len = 2, .cursor = .{ .line = 0, .col = 5 } },
        .{ .type = .identifier, .pos = 8, .len = 3, .cursor = .{ .line = 0, .col = 8 } },
        .{ .type = .eof, .pos = 11, .len = 0, .cursor = .{ .line = 0, .col = 11 } },
    }, scanner.tokens.items);
}
test "unexpected" {
    const gpa = t.allocator;

    var reader: std.Io.Reader = .fixed(
        \\1
    );
    var scanner: Scanner = try .scan(gpa, &reader);
    defer scanner.deinit(gpa);

    try t.expectEqualDeep(&[_]Token{
        .{ .type = .unexpected, .pos = 0, .len = 1, .cursor = .{ .line = 0, .col = 0 } },
        .{ .type = .eof, .pos = 1, .len = 0, .cursor = .{ .line = 0, .col = 1 } },
    }, scanner.tokens.items);
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const assert = std.debug.assert;
const t = std.testing;

const Cursor = @import("Cursor.zig");
const Token = @import("Token.zig");
