pub const Token = @import("Token.zig");
pub const Scanner = @import("Scanner.zig");

pub const Tokens = struct {
    content: std.ArrayList(u8),
    tokens: std.ArrayList(Token),

    pub fn scan(gpa: Allocator, reader: *Io.Reader) Scanner.Error!Tokens {
        var scanner: Scanner = .init(gpa, reader);
        try scanner.scan();

        return .{
            .content = scanner.content,
            .tokens = scanner.tokens,
        };
    }

    pub fn deinit(self: *const Tokens, gpa: Allocator) void {
        self.tokens.deinit(gpa);
        self.content.deinit(gpa);
    }
};

test {
    _ = Token;
    _ = Scanner;
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
