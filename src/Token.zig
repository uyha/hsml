const Token = @This();

pub const Type = enum {
    colon,
    star,
    comma,

    brace_open,
    brace_close,

    paren_open,
    paren_close,

    when,
    from,
    call,
    goto,

    not,
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
