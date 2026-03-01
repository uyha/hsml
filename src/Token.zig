const Token = @This();

pub const Type = enum {
    colon,
    star,
    brace_left,
    brace_right,
    paren_left,
    paren_right,
    comma,
    dot,

    when,
    from,
    call,
    not,
    goto,
    @"and",
    @"or",

    underscore,
    identifier,

    string_open,
    string_content,
    string_close,

    eof,

    unexpected,
};

type: Type,
pos: usize,
len: usize,

cursor: Cursor,

pub fn lexeme(self: Token, content: []const u8) []const u8 {
    return content[self.pos .. self.pos + self.len];
}

const Cursor = @import("Cursor.zig");
