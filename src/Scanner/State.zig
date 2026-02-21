const State = @This();

pub const Error = Allocator.Error || error{ReadFailed};

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

    try self.appendToken(.luastr_left);
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
        try self.appendToken(.luastr_content);
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
                try self.appendToken(.luastr_content);

                self.len = close_level + 2;
                self.start.col -= self.len;
                try self.appendToken(.luastr_right);

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

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const assert = std.debug.assert;

const Cursor = @import("../Cursor.zig");
const Token = @import("../Token.zig");
