const Ast = @This();
pub const Error = std.mem.Allocator.Error;

nodes: std.ArrayList(Node),

pub fn root(self: *const Ast) usize {
    return self.nodes.items.len - 1;
}

pub fn iterator(self: *const Ast, gpa: Allocator) Allocator.Error!Iterator {
    return try .init(gpa, self.root(), self.nodes.items);
}

pub const Node = union(enum) {
    root: Root,

    resources: Many("resources"),
    resource: Resource,

    events: Many("events"),
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

pub const Root = struct {
    name: ?usize,
    brace_left: usize,
    brace_right: usize,

    items: std.ArrayList(usize) = .empty,
    commas: std.ArrayList(usize) = .empty,
};

pub fn Many(comptime expected_identifier: []const u8) type {
    return struct {
        pub const identifier = expected_identifier;

        name: usize,
        brace_left: usize,
        brace_right: usize,

        items: std.ArrayList(usize) = .empty,
        commas: std.ArrayList(usize) = .empty,
    };
}

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
    var ast: Ast = .{ .nodes = .empty };
    var state: State = .{
        .arena = arena,

        .nodes = &ast.nodes,
        .content = content,
        .tokens = tokens,
    };
    try state.parse();
    return ast;
}

const State = struct {
    arena: Allocator,

    nodes: *std.ArrayList(Node),
    content: []const u8,
    tokens: []const Token,

    current: usize = 0,

    fn parse(self: *State) Error!void {
        _ = try self.root();
    }

    fn currentToken(self: *const State) Token {
        assert(self.current < self.tokens.len);
        return self.tokens[self.current];
    }
    fn lexeme(self: *const State, source: Token) []const u8 {
        assert(self.current < self.tokens.len);
        return source.lexeme(self.content);
    }
    fn append(self: *State, value: Node) Error!usize {
        try self.nodes.append(self.arena, value);
        return self.nodes.items.len - 1;
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
        if (current.type == .eof) {
            return try self.append(@unionInit(Node, "missing", .identifier));
        }
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
        if (current.type == .eof) {
            return try self.append(@unionInit(Node, "missing", expected));
        }
        if (current.type != expected) {
            return null;
        }

        self.current += 1;
        return try self.append(@unionInit(Node, @tagName(expected), current));
    }
    fn tokenTrailing(self: *State, comptime expected: Token.Type) Error!?usize {
        const current = self.currentToken();
        if (current.type != expected) {
            return null;
        }

        self.current += 1;
        return try self.append(@unionInit(Node, @tagName(expected), current));
    }
    fn tokenOrMissing(self: *State, comptime expected: Token.Type) Error!usize {
        if (try self.token(expected)) |index| {
            return index;
        }
        return try self.missing(expected);
    }

    fn root(self: *State) Error!usize {
        const name = try self.token(.identifier);
        return try many(.root, component)(self, name);
    }
    fn component(self: *State) Error!?usize {
        const Match = struct {
            tag: std.meta.Tag(Node),
            child: fn (self: *State) Error!?usize,
        };
        const matches: []const Match = &.{
            .{ .tag = .resources, .child = resource },
            .{ .tag = .events, .child = event },
        };
        inline for (matches) |match| {
            if (try self.named(@tagName(match.tag))) |name| {
                return try many(match.tag, match.child)(self, name);
            }
        }

        return null;
    }
    fn Name(comptime tag: std.meta.Tag(Node)) type {
        const Payload = @FieldType(Node, @tagName(tag));
        return @FieldType(Payload, "name");
    }
    fn many(
        comptime tag: std.meta.Tag(Node),
        child: fn (self: *State) Error!?usize,
    ) fn (self: *State, name: Name(tag)) Error!usize {
        return struct {
            fn f(self: *State, name: Name(tag)) Error!usize {
                const brace_left = try self.tokenOrMissing(.brace_left);

                var items: std.ArrayList(usize) = .empty;
                var commas: std.ArrayList(usize) = .empty;

                const brace_right = blk: {
                    if (try self.token(.brace_right)) |index| {
                        break :blk index;
                    }
                    while (true) {
                        if (items.items.len != commas.items.len) {
                            assert(items.items.len == commas.items.len + 1);
                            try commas.append(self.arena, try self.missing(.comma));
                        }
                        if (try child(self)) |item_index| {
                            try items.append(self.arena, item_index);
                        } else {
                            break :blk try self.unexpected();
                        }
                        if (try self.token(.comma)) |comma_index| {
                            try commas.append(self.arena, comma_index);
                        }

                        if (try self.token(.brace_right)) |index| {
                            break :blk index;
                        }
                    }
                };

                return try self.append(@unionInit(Node, @tagName(tag), .{
                    .name = name,
                    .brace_left = brace_left,
                    .brace_right = brace_right,

                    .items = items,
                    .commas = commas,
                }));
            }
        }.f;
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
    fn event(self: *State) Error!?usize {
        const current = self.currentToken();
        if (current.type != .identifier) {
            return null;
        }

        self.current += 1;
        return try self.append(@unionInit(Node, "event", current));
    }
};

pub const Iterator = struct {
    stack: std.ArrayList(usize) = .empty,
    nodes: []const Node,

    pub fn init(gpa: Allocator, ast_root: usize, nodes: []const Node) Allocator.Error!Iterator {
        var result: Iterator = .{ .nodes = nodes };

        try result.stack.append(gpa, ast_root);

        return result;
    }

    pub fn next(self: *Iterator, gpa: Allocator) Allocator.Error!?Node {
        const node = self.nodes[self.stack.pop() orelse return null];

        switch (node) {
            .root => |payload| {
                try self.stack.append(gpa, payload.brace_right);
                try self.appendItemsCommas(
                    gpa,
                    payload.items.items,
                    payload.commas.items,
                );
                try self.stack.append(gpa, payload.brace_left);
                if (payload.name) |name| {
                    try self.stack.append(gpa, name);
                }
            },
            .resources => |payload| {
                try self.stack.append(gpa, payload.brace_right);
                try self.appendItemsCommas(
                    gpa,
                    payload.items.items,
                    payload.commas.items,
                );
                try self.stack.append(gpa, payload.brace_left);
                try self.stack.append(gpa, payload.name);
            },
            .resource => |payload| {
                try self.stack.append(gpa, payload.type);
                if (payload.@"volatile") |i| {
                    try self.stack.append(gpa, i);
                }
                if (payload.@"const") |i| {
                    try self.stack.append(gpa, i);
                }
                if (payload.star) |i| {
                    try self.stack.append(gpa, i);
                }
                try self.stack.append(gpa, payload.colon);
                try self.stack.append(gpa, payload.name);
            },
            .events => |payload| {
                try self.stack.append(gpa, payload.brace_right);
                try self.appendItemsCommas(
                    gpa,
                    payload.items.items,
                    payload.commas.items,
                );
                try self.stack.append(gpa, payload.brace_left);
                try self.stack.append(gpa, payload.name);
            },
            else => {},
        }

        return node;
    }

    fn appendItemsCommas(
        self: *Iterator,
        gpa: Allocator,
        items: []const usize,
        commas: []const usize,
    ) Allocator.Error!void {
        assert(items.len == commas.len or items.len == commas.len + 1);

        if (items.len == commas.len + 1) {
            try self.stack.append(gpa, items[items.len - 1]);
        }

        var bound = commas.len;
        while (bound > 0) : (bound -= 1) {
            const i = bound - 1;
            try self.stack.append(gpa, commas[i]);
            try self.stack.append(gpa, items[i]);
        }
    }
};

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const assert = std.debug.assert;
const t = std.testing;

const Scanner = @import("Scanner.zig");
const Token = @import("Token.zig");
