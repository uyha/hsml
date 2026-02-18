const Token = @This();

pub const Type = enum {
    colon,
    star,
    left_brace,
    right_brace,
    left_paren,
    right_paren,
    comma,
    dot,

    arrow,

    @"const",
    @"if",
    invoke,
    self,
    identifier,

    eof,

    unexpected,
};

type: Type,
pos: usize,
len: usize,

line: usize,
col: usize,

pub fn lexeme(self: Token, content: []const u8) []const u8 {
    return content[self.pos .. self.pos + self.len];
}
