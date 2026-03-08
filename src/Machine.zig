const StateMachine = @This();

states: std.ArrayList(State) = .empty,

pub const Parsed = struct {
    content: []const u8,
    tokens: []const Token,

    root: usize,
    eof: usize,
    nodes: []const Node,
};

pub fn walk(arena: Allocator, parsed: Parsed) StateMachine {
    _ = arena;
    _ = parsed;

    return .{};
}

test {
    _ = State;
}

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Token = @import("Token.zig");
pub const Node = @import("Ast.zig").Node;

pub const State = @import("machine/State.zig");
