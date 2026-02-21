pub const Token = @import("Token.zig");
pub const Scanner = @import("Scanner.zig");

test {
    _ = Token;
    _ = Scanner;
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
