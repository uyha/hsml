const Scanner = @This();
pub const Error = State.Error;

content: std.ArrayList(u8) = .empty,
tokens: std.ArrayList(Token) = .empty,

pub fn deinit(self: *Scanner, gpa: Allocator) void {
    self.content.deinit(gpa);
    self.tokens.deinit(gpa);
}

pub fn scan(gpa: Allocator, reader: *Io.Reader) Error!Scanner {
    var scanner: Scanner = .{};
    var state: State = .{
        .content = &scanner.content,
        .tokens = &scanner.tokens,
        .gpa = gpa,
        .reader = reader,
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

    return scanner;
}

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
        \\ if const  invoke
        \\   self
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
        .{ .type = .invoke, .pos = 19, .len = 6, .cursor = .{ .line = 1, .col = 11 } },
        .{ .type = .self, .pos = 29, .len = 4, .cursor = .{ .line = 2, .col = 3 } },
        .{ .type = .eof, .pos = 33, .len = 0, .cursor = .{ .line = 2, .col = 7 } },
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
        .{ .type = .luastr_left, .pos = 0, .len = 2, .cursor = .{ .line = 0, .col = 0 } },
        .{ .type = .luastr_content, .pos = 2, .len = 0, .cursor = .{ .line = 0, .col = 2 } },
        .{ .type = .luastr_right, .pos = 2, .len = 2, .cursor = .{ .line = 0, .col = 2 } },
        .{ .type = .luastr_left, .pos = 5, .len = 3, .cursor = .{ .line = 1, .col = 0 } },
        .{ .type = .luastr_content, .pos = 8, .len = 0, .cursor = .{ .line = 1, .col = 3 } },
        .{ .type = .luastr_right, .pos = 8, .len = 3, .cursor = .{ .line = 1, .col = 3 } },
        .{ .type = .luastr_left, .pos = 12, .len = 3, .cursor = .{ .line = 2, .col = 0 } },
        .{ .type = .luastr_content, .pos = 15, .len = 3, .cursor = .{ .line = 2, .col = 3 } },
        .{ .type = .luastr_right, .pos = 18, .len = 3, .cursor = .{ .line = 2, .col = 6 } },
        .{ .type = .luastr_left, .pos = 22, .len = 4, .cursor = .{ .line = 3, .col = 0 } },
        .{ .type = .luastr_content, .pos = 26, .len = 6, .cursor = .{ .line = 3, .col = 4 } },
        .{ .type = .luastr_right, .pos = 32, .len = 4, .cursor = .{ .line = 3, .col = 10 } },
        .{ .type = .luastr_left, .pos = 37, .len = 4, .cursor = .{ .line = 4, .col = 0 } },
        .{ .type = .luastr_content, .pos = 41, .len = 8, .cursor = .{ .line = 4, .col = 4 } },
        .{ .type = .luastr_right, .pos = 49, .len = 4, .cursor = .{ .line = 4, .col = 12 } },
        .{ .type = .eof, .pos = 54, .len = 0, .cursor = .{ .line = 5, .col = 0 } },
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
const t = std.testing;

const State = @import("Scanner/State.zig");

const Cursor = @import("Cursor.zig");
const Token = @import("Token.zig");
