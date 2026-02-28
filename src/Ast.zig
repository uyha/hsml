const Ast = @This();
pub const Error = std.mem.Allocator.Error;

root: usize,
eof: usize,
nodes: std.ArrayList(Node),

pub fn iterator(self: *const Ast, gpa: Allocator) Allocator.Error!Iterator {
    return try .init(gpa, &.{ self.eof, self.root }, self.nodes.items);
}

pub const Node = union(enum) {
    root: Root,

    resources: Many,
    resource: Resource,

    events: Many,
    event: Token,

    guards: Many,
    guard: Guard,

    map: Map,

    identifier: Token,
    colon: Token,
    brace_left: Token,
    brace_right: Token,
    comma: Token,
    star: Token,
    @"const": Token,
    @"volatile": Token,

    string: String,
    string_open: Token,
    string_content: Token,
    string_close: Token,

    unexpected: Token,
    missing: Token.Type,

    eof: Token,
};

pub const String = struct {
    open: usize,
    content: usize,
    close: usize,
};
pub const Map = struct {
    name: usize,
    string: usize,
};

pub const Root = struct {
    name: ?usize,
    open: usize,
    close: usize,

    items: std.ArrayList(usize) = .empty,
    seps: std.ArrayList(usize) = .empty,
};

pub const Many = struct {
    name: usize,
    open: usize,
    close: usize,

    items: std.ArrayList(usize) = .empty,
    seps: std.ArrayList(usize) = .empty,
};

pub const Resource = union(enum) {
    map: usize,
    many: Many,
};
pub const Guard = union(enum) {
    map: usize,
    many: Many,
};

pub fn parse(
    arena: std.mem.Allocator,
    content: []const u8,
    tokens: []const Token,
) Error!Ast {
    var ast: Ast = .{ .root = undefined, .eof = undefined, .nodes = .empty };
    var state: State = .{
        .arena = arena,

        .nodes = &ast.nodes,
        .content = content,
        .tokens = tokens,
    };
    ast.root = try state.root();
    ast.eof = try state.eof();
    return ast;
}

const State = struct {
    arena: Allocator,

    nodes: *std.ArrayList(Node),
    content: []const u8,
    tokens: []const Token,

    current: usize = 0,

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
    fn string(self: *State) Error!?usize {
        return try self.append(.{ .string = .{
            .open = try self.token(.string_open) orelse return null,
            .content = try self.tokenOrMissing(.string_content),
            .close = try self.tokenOrMissing(.string_close),
        } });
    }

    fn root(self: *State) Error!usize {
        const config: ManyConfig = .{
            .open = .brace_left,
            .close = .brace_right,
            .seperator = .comma,
        };
        const name = try self.token(.identifier);
        const result = try self.many(config, component);

        return try self.append(.{ .root = .{
            .name = name,
            .open = result.open,
            .close = result.close,

            .items = result.items,
            .seps = result.seps,
        } });
    }
    fn eof(self: *State) Error!usize {
        const current = self.currentToken();
        if (current.type == .eof) {
            return try self.append(.{ .eof = current });
        }

        self.current += 1;
        return try self.missing(.eof);
    }
    fn component(self: *State) Error!?usize {
        const Match = struct {
            tag: std.meta.Tag(Node),
            child: fn (self: *State) Error!?usize,
        };
        const config: ManyConfig = .{
            .open = .brace_left,
            .close = .brace_right,
            .seperator = .comma,
        };
        const matches: []const Match = &.{
            .{ .tag = .resources, .child = resource },
            .{ .tag = .events, .child = event },
            .{ .tag = .guards, .child = guard },
        };
        inline for (matches) |match| {
            if (try self.named(@tagName(match.tag))) |name| {
                const result = try self.many(config, match.child);

                return try self.append(@unionInit(
                    Node,
                    @tagName(match.tag),
                    result.of(name),
                ));
            }
        }

        return null;
    }
    const ManyConfig = struct {
        open: Token.Type,
        close: Token.Type,
        seperator: Token.Type,
    };
    const ManyResult = struct {
        open: usize,
        close: usize,
        items: std.ArrayList(usize),
        seps: std.ArrayList(usize),

        fn of(self: ManyResult, name: usize) Many {
            return .{
                .name = name,
                .open = self.open,
                .close = self.close,

                .items = self.items,
                .seps = self.seps,
            };
        }
    };
    fn many(
        self: *State,
        comptime config: ManyConfig,
        comptime child: fn (self: *State) Error!?usize,
    ) Error!ManyResult {
        const open = try self.tokenOrMissing(config.open);

        var items: std.ArrayList(usize) = .empty;
        var seps: std.ArrayList(usize) = .empty;

        const close = blk: {
            if (try self.token(config.close)) |index| {
                break :blk index;
            }
            while (true) {
                if (items.items.len != seps.items.len) {
                    assert(items.items.len == seps.items.len + 1);
                    try seps.append(self.arena, try self.missing(.comma));
                }
                if (try child(self)) |item| {
                    try items.append(self.arena, item);
                } else {
                    break :blk try self.unexpected();
                }
                if (try self.tokenTrailing(config.seperator)) |comma| {
                    try seps.append(self.arena, comma);
                }

                if (try self.token(config.close)) |index| {
                    break :blk index;
                }
            }
        };
        return .{
            .open = open,
            .close = close,
            .items = items,
            .seps = seps,
        };
    }

    fn resource(self: *State) Error!?usize {
        return self.mapOrMany(.resource);
    }
    fn event(self: *State) Error!?usize {
        const current = self.currentToken();
        if (current.type != .identifier) {
            return null;
        }

        self.current += 1;
        return try self.append(.{ .event = current });
    }
    fn guard(self: *State) Error!?usize {
        return self.mapOrMany(.guard);
    }
    fn mapOrMany(self: *State, comptime tag: std.meta.Tag(Node)) Error!?usize {
        const name = try self.token(.identifier) orelse return null;

        if (try self.string()) |string_index| {
            const index = try self.append(.{ .map = .{
                .name = name,
                .string = string_index,
            } });
            return try self.append(@unionInit(Node, @tagName(tag), .{ .map = index }));
        }

        const many_result = try self.many(
            .{ .open = .brace_left, .close = .brace_right, .seperator = .comma },
            map,
        );
        return try self.append(@unionInit(Node, @tagName(tag), .{
            .many = many_result.of(name),
        }));
    }
    fn map(self: *State) Error!?usize {
        return try self.append(.{ .map = .{
            .name = try self.token(.identifier) orelse return null,
            .string = try self.string() orelse return null,
        } });
    }
};

pub const Iterator = struct {
    stack: std.ArrayList(usize) = .empty,
    nodes: []const Node,

    pub fn init(gpa: Allocator, initial: []const usize, nodes: []const Node) Allocator.Error!Iterator {
        var result: Iterator = .{ .nodes = nodes };

        for (initial) |item| {
            try result.stack.append(gpa, item);
        }

        return result;
    }

    pub fn next(self: *Iterator, gpa: Allocator) Allocator.Error!?Node {
        const node = self.nodes[self.stack.pop() orelse return null];

        switch (node) {
            .root => |payload| {
                try self.stack.append(gpa, payload.close);
                try self.appendItems(gpa, payload.items.items, payload.seps.items);
                try self.stack.append(gpa, payload.open);
                if (payload.name) |name| {
                    try self.stack.append(gpa, name);
                }
            },
            .resources => |payload| {
                try self.stack.append(gpa, payload.close);
                try self.appendItems(gpa, payload.items.items, payload.seps.items);
                try self.stack.append(gpa, payload.open);
                try self.stack.append(gpa, payload.name);
            },
            .resource => |payload| {
                switch (payload) {
                    .map => |map| {
                        try self.stack.append(gpa, map);
                    },
                    .many => |many| {
                        try self.stack.append(gpa, many.close);
                        try self.appendItems(gpa, many.items.items, many.seps.items);
                        try self.stack.append(gpa, many.open);
                        try self.stack.append(gpa, many.name);
                    },
                }
            },
            .events => |payload| {
                try self.stack.append(gpa, payload.close);
                try self.appendItems(gpa, payload.items.items, payload.seps.items);
                try self.stack.append(gpa, payload.open);
                try self.stack.append(gpa, payload.name);
            },
            .guards => |payload| {
                try self.stack.append(gpa, payload.close);
                try self.appendItems(gpa, payload.items.items, payload.seps.items);
                try self.stack.append(gpa, payload.open);
                try self.stack.append(gpa, payload.name);
            },
            .guard => |payload| {
                switch (payload) {
                    .map => |map| {
                        try self.stack.append(gpa, map);
                    },
                    .many => |many| {
                        try self.stack.append(gpa, many.close);
                        try self.appendItems(gpa, many.items.items, many.seps.items);
                        try self.stack.append(gpa, many.open);
                        try self.stack.append(gpa, many.name);
                    },
                }
            },
            .string => |payload| {
                try self.stack.append(gpa, payload.close);
                try self.stack.append(gpa, payload.content);
                try self.stack.append(gpa, payload.open);
            },
            .map => |payload| {
                try self.stack.append(gpa, payload.string);
                try self.stack.append(gpa, payload.name);
            },
            else => {},
        }

        return node;
    }

    fn appendItems(
        self: *Iterator,
        gpa: Allocator,
        items: []const usize,
        seps: []const usize,
    ) Allocator.Error!void {
        assert(items.len == seps.len or items.len == seps.len + 1);

        if (items.len == seps.len + 1) {
            try self.stack.append(gpa, items[items.len - 1]);
        }

        var bound = seps.len;
        while (bound > 0) : (bound -= 1) {
            const i = bound - 1;
            try self.stack.append(gpa, seps[i]);
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
