const Ast = @This();
pub const Error = std.mem.Allocator.Error;

root: usize,
definitions: std.ArrayList(Definition),

pub const Definition = union(enum) {
    root: Root,

    resources: Resources,
    resource: Resource,

    events: Events,
    event: Token,

    identifier: Token,
    colon: Token,
    brace_left: Token,
    brace_right: Token,
    comma: Token,
    star: Token,
    @"const": Token,
    @"volatile": Token,

    unexpected: Token,
    missing: Token.Type,
};

pub const Events = std.ArrayList(usize);

pub const Root = struct {
    name: usize,
    brace_left: usize,
    brace_right: usize,

    items: std.ArrayList(usize) = .empty,
    commas: std.ArrayList(usize) = .empty,
};

pub const Resources = struct {
    name: usize,
    brace_left: usize,
    brace_right: usize,

    items: std.ArrayList(usize) = .empty,
    commas: std.ArrayList(usize) = .empty,
};

pub const Resource = struct {
    name: usize,
    colon: usize,
    star: ?usize,
    @"const": ?usize,
    @"volatile": ?usize,
    type: usize,
};

pub fn parse(
    arena: std.mem.Allocator,
    content: []const u8,
    tokens: []const Token,
) Error!Ast {
    var definitions: std.ArrayList(Definition) = .empty;
    var state: State = .{
        .arena = arena,

        .definitions = &definitions,
        .content = content,
        .tokens = tokens,
    };
    return .{ .root = try state.parse(), .definitions = definitions };
}

const State = struct {
    arena: Allocator,

    definitions: *std.ArrayList(Definition),
    content: []const u8,
    tokens: []const Token,

    current: usize = 0,

    fn parse(self: *State) Error!usize {
        return self.root();
    }

    fn currentToken(self: *const State) Token {
        assert(self.current < self.tokens.len);
        return self.tokens[self.current];
    }
    fn lexeme(self: *const State, source: Token) []const u8 {
        assert(self.current < self.tokens.len);
        return source.lexeme(self.content);
    }
    fn append(self: *State, value: Definition) Error!usize {
        try self.definitions.append(self.arena, value);
        return self.definitions.items.len - 1;
    }
    fn unexpected(self: *State) Error!usize {
        defer self.current += 1;
        return try self.append(.{ .unexpected = self.currentToken() });
    }
    fn missing(self: *State, expected: Token.Type) Error!usize {
        return try self.append(.{ .missing = expected });
    }
    fn named(self: *State, comptime expected: []const u8) Error!?usize {
        const current = self.currentToken();
        if (current.type != .identifier or
            !std.mem.eql(u8, expected, self.lexeme(current)))
        {
            return null;
        }

        self.current += 1;
        return try self.append(.{ .identifier = current });
    }
    fn token(self: *State, comptime expected: Token.Type) Error!?usize {
        const current = self.currentToken();
        if (current.type != expected) {
            return null;
        }

        self.current += 1;
        return try self.append(@unionInit(Definition, @tagName(expected), current));
    }
    fn tokenOrMissing(self: *State, comptime expected: Token.Type) Error!usize {
        if (try self.token(expected)) |index| {
            return index;
        }
        return try self.missing(expected);
    }

    fn root(self: *State) Error!usize {
        const name_index = try self.token(.identifier) orelse try self.unexpected();

        var components: std.ArrayList(usize) = .empty;
        var commas: std.ArrayList(usize) = .empty;

        const brace_left_index = try self.tokenOrMissing(.brace_left);
        const brace_right_index = blk: {
            if (try self.token(.brace_right)) |index| {
                break :blk index;
            }
            while (true) {
                if (components.items.len != commas.items.len) {
                    assert(components.items.len == commas.items.len + 1);
                    try commas.append(
                        self.arena,
                        try self.append(.{ .missing = .comma }),
                    );
                }
                if (try self.component()) |index| {
                    try components.append(self.arena, index);
                } else {
                    break :blk try self.unexpected();
                }
                if (try self.token(.comma)) |index| {
                    try commas.append(self.arena, index);
                }

                if (try self.token(.brace_right)) |index| {
                    break :blk index;
                }
            }
        };

        return try self.append(.{
            .root = .{
                .name = name_index,
                .brace_left = brace_left_index,
                .items = components,
                .commas = commas,
                .brace_right = brace_right_index,
            },
        });
    }
    fn component(self: *State) Error!?usize {
        inline for (.{
            resources,
        }) |f| {
            if (try f(self)) |index| return index;
        }

        return null;
    }
    fn resources(self: *State) Error!?usize {
        const name_index = try self.named("resources") orelse return null;
        const brace_left_index = try self.tokenOrMissing(.brace_left);

        var resource_indices: std.ArrayList(usize) = .empty;
        var comma_indices: std.ArrayList(usize) = .empty;

        const brace_right_index = blk: {
            if (try self.token(.brace_right)) |index| {
                break :blk index;
            }
            while (true) {
                if (resource_indices.items.len != comma_indices.items.len) {
                    assert(resource_indices.items.len == comma_indices.items.len + 1);
                    try comma_indices.append(self.arena, try self.missing(.comma));
                }
                if (try self.resource()) |resource_index| {
                    try resource_indices.append(self.arena, resource_index);
                } else {
                    break :blk try self.unexpected();
                }
                if (try self.token(.comma)) |comma_index| {
                    try comma_indices.append(self.arena, comma_index);
                }

                if (try self.token(.brace_right)) |index| {
                    break :blk index;
                }
            }
        };

        return try self.append(.{ .resources = .{
            .name = name_index,
            .brace_left = brace_left_index,
            .brace_right = brace_right_index,

            .items = resource_indices,
            .commas = comma_indices,
        } });
    }
    fn resource(self: *State) Error!?usize {
        return try self.append(.{ .resource = .{
            .name = try self.token(.identifier) orelse return null,
            .colon = try self.tokenOrMissing(.colon),
            .star = try self.token(.star),
            .@"const" = try self.token(.@"const"),
            .@"volatile" = try self.token(.@"volatile"),
            .type = try self.tokenOrMissing(.identifier),
        } });
    }
};

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const assert = std.debug.assert;
const t = std.testing;

const Scanner = @import("Scanner.zig");
const Token = @import("Token.zig");
