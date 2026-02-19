const Scanner = @This();

pub const Error = Allocator.Error || error{ReadFailed};

pub const Cursor = struct {
    line: usize,
    col: usize,
};

content: std.ArrayList(u8) = .empty,
tokens: std.ArrayList(Token) = .empty,

current: usize = 0,
len: usize = 0,

start: Cursor = .{ .line = 1, .col = 1 },
end: Cursor = .{ .line = 1, .col = 1 },

arena: Allocator,
reader: *Io.Reader,

pub fn init(arena: Allocator, reader: *Io.Reader) Scanner {
    return .{ .arena = arena, .reader = reader };
}

pub fn deinit(self: *Scanner) void {
    self.content.deinit(self.arena);
    self.tokens.deinit(self.arena);
}

pub fn scan(self: *Scanner) Error!void {
    while (true) {
        if (try self.peek() == null) {
            try self.scanCurrent();
            try self.appendToken(.eof);
            break;
        }

        self.len += 1;
        self.end.col += 1;

        try self.scanCurrent();
    }
}

fn scanCurrent(self: *Scanner) Error!void {
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
        '\n' => {
            self.current += 1;
            self.len = 0;

            self.end = .{ .line = self.end.line + 1, .col = 1 };
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
                .{ "invoke", .invoke },
                .{ "self", .self },
            }) |keyword_token| {
                if (try self.keyword(keyword_token[0], keyword_token[1])) {
                    break;
                }
            } else if (try self.identifier()) {
                return;
            } else {
                try self.unexpected();
            }
        },
    }
}

fn appendToken(self: *Scanner, token_type: Token.Type) Allocator.Error!void {
    try self.tokens.append(
        self.arena,
        .{
            .type = token_type,
            .pos = self.current,
            .len = self.len,
            .line = self.start.line,
            .col = self.start.col,
        },
    );
    self.current += self.len;
    self.len = 0;
    self.start = self.end;
}
fn peek(self: *Scanner) Error!?u8 {
    if (self.current + self.len == self.content.items.len) {
        try self.content.append(
            self.arena,
            self.reader.takeByte() catch |err| switch (err) {
                error.EndOfStream => return null,
                else => |e| return e,
            },
        );
    }
    return self.content.items[self.current + self.len];
}
fn match(self: *Scanner, expected: u8) Error!bool {
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
    self: *Scanner,
    comptime expected: []const u8,
    comptime token_type: Token.Type,
) Error!bool {
    if (self.content.items[self.current] == expected[0]) {
        for (expected[1..]) |c| {
            if (!try self.match(c)) {
                return false;
            }
        }

        try self.appendToken(token_type);
        return true;
    }
    return false;
}
fn identifier(self: *Scanner) Error!bool {
    switch (self.content.items[self.current]) {
        'a'...'z', 'A'...'Z' => {
            while (try self.peek()) |c| {
                switch (c) {
                    'a'...'z', 'A'...'Z', '0'...'9', '_' => {
                        self.len += 1;
                        self.end.col += 1;
                    },
                    else => break,
                }
            }
            try self.appendToken(.identifier);
            return true;
        },
        else => {},
    }

    return false;
}
fn unexpected(self: *Scanner) Error!void {
    while (try self.peek()) |c| switch (c) {
        ' ', '\n', ':' => {
            try self.appendToken(.unexpected);
            return;
        },
        else => self.len += 1,
    };
    try self.appendToken(.unexpected);
}

test "Single character tokens" {
    const gpa = t.allocator;

    var reader: std.Io.Reader = .fixed(
        \\:*{}(),.
        \\,
    );
    var scanner: Scanner = .init(gpa, &reader);
    defer scanner.deinit();

    try scanner.scan();

    try t.expectEqualDeep(&[_]Token{
        .{ .type = .colon, .pos = 0, .len = 1, .line = 1, .col = 1 },
        .{ .type = .star, .pos = 1, .len = 1, .line = 1, .col = 2 },
        .{ .type = .brace_left, .pos = 2, .len = 1, .line = 1, .col = 3 },
        .{ .type = .brace_right, .pos = 3, .len = 1, .line = 1, .col = 4 },
        .{ .type = .paren_left, .pos = 4, .len = 1, .line = 1, .col = 5 },
        .{ .type = .paren_right, .pos = 5, .len = 1, .line = 1, .col = 6 },
        .{ .type = .comma, .pos = 6, .len = 1, .line = 1, .col = 7 },
        .{ .type = .dot, .pos = 7, .len = 1, .line = 1, .col = 8 },
        .{ .type = .comma, .pos = 9, .len = 1, .line = 2, .col = 1 },
        .{ .type = .eof, .pos = 10, .len = 0, .line = 2, .col = 2 },
    }, scanner.tokens.items);
    try t.expectEqualStrings(",", scanner.tokens.items[8].lexeme(scanner.content.items));
    try t.expectEqualStrings("", scanner.tokens.items[9].lexeme(scanner.content.items));
}
test "Multi character tokens" {
    const gpa = t.allocator;

    var reader: std.Io.Reader = .fixed(
        \\->:->->
        \\ if const  invoke
        \\   self
    );
    var scanner: Scanner = .init(gpa, &reader);
    defer scanner.deinit();

    try scanner.scan();

    try t.expectEqualDeep(&[_]Token{
        .{ .type = .arrow, .pos = 0, .len = 2, .line = 1, .col = 1 },
        .{ .type = .colon, .pos = 2, .len = 1, .line = 1, .col = 3 },
        .{ .type = .arrow, .pos = 3, .len = 2, .line = 1, .col = 4 },
        .{ .type = .arrow, .pos = 5, .len = 2, .line = 1, .col = 6 },
        .{ .type = .@"if", .pos = 9, .len = 2, .line = 2, .col = 2 },
        .{ .type = .@"const", .pos = 12, .len = 5, .line = 2, .col = 5 },
        .{ .type = .invoke, .pos = 19, .len = 6, .line = 2, .col = 12 },
        .{ .type = .self, .pos = 29, .len = 4, .line = 3, .col = 4 },
        .{ .type = .eof, .pos = 33, .len = 0, .line = 3, .col = 8 },
    }, scanner.tokens.items);
    try t.expectEqualStrings("->", scanner.tokens.items[0].lexeme(scanner.content.items));
    try t.expectEqualStrings("if", scanner.tokens.items[4].lexeme(scanner.content.items));
    try t.expectEqualStrings("self", scanner.tokens.items[7].lexeme(scanner.content.items));
}
test "Single identifier" {
    const gpa = t.allocator;

    var reader: std.Io.Reader = .fixed(
        \\simple:
    );
    var scanner: Scanner = .init(gpa, &reader);
    defer scanner.deinit();

    try scanner.scan();

    try t.expectEqualDeep(&[_]Token{
        .{ .type = .identifier, .pos = 0, .len = 6, .line = 1, .col = 1 },
        .{ .type = .colon, .pos = 6, .len = 1, .line = 1, .col = 7 },
        .{ .type = .eof, .pos = 7, .len = 0, .line = 1, .col = 8 },
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
    var scanner: Scanner = .init(gpa, &reader);
    defer scanner.deinit();

    try scanner.scan();

    try t.expectEqualDeep(&[_]Token{
        .{ .type = .identifier, .pos = 0, .len = 6, .line = 1, .col = 1 },
        .{ .type = .colon, .pos = 6, .len = 1, .line = 1, .col = 7 },
        .{ .type = .brace_left, .pos = 8, .len = 1, .line = 1, .col = 9 },
        .{ .type = .identifier, .pos = 10, .len = 9, .line = 2, .col = 1 },
        .{ .type = .colon, .pos = 19, .len = 1, .line = 2, .col = 10 },
        .{ .type = .brace_left, .pos = 20, .len = 1, .line = 2, .col = 11 },
        .{ .type = .brace_right, .pos = 21, .len = 1, .line = 2, .col = 12 },
        .{ .type = .brace_right, .pos = 23, .len = 1, .line = 3, .col = 1 },
        .{ .type = .eof, .pos = 24, .len = 0, .line = 3, .col = 2 },
    }, scanner.tokens.items);
}
test "unexpected" {
    const gpa = t.allocator;

    var reader: std.Io.Reader = .fixed(
        \\1
    );
    var scanner: Scanner = .init(gpa, &reader);
    defer scanner.deinit();

    try scanner.scan();

    try t.expectEqualDeep(&[_]Token{
        .{ .type = .unexpected, .pos = 0, .len = 1, .line = 1, .col = 1 },
        .{ .type = .eof, .pos = 1, .len = 0, .line = 1, .col = 2 },
    }, scanner.tokens.items);
}

const Token = @import("Token.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const t = std.testing;
const assert = std.debug.assert;
