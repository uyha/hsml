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

    bare: Bare,
    map: Map,

    resources: Many,
    events: Many,
    guards: Many,
    actions: Many,

    transitions: Many,
    transition: Transition,
    transition_from: Transition.From,
    transition_to: Transition.To,
    transition_guard: Many,
    transition_action: Many,

    @"const": Token,
    @"if": Token,
    @"volatile": Token,
    arrow: Token,
    brace_left: Token,
    brace_right: Token,
    colon: Token,
    comma: Token,
    identifier: Token,
    invoke: Token,
    paren_left: Token,
    paren_right: Token,
    star: Token,
    underscore: Token,

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
pub const Bare = struct {
    name: usize,
    string: usize,
};
pub const Map = union(enum) {
    bare: usize,
    lang: Many,
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

pub const Transition = struct {
    star: ?usize,
    from: usize,
    to: ?usize,
    guard: ?usize,
    action: ?usize,

    pub const From = struct {
        open: usize,
        close: usize,

        state: usize,
        comma: usize,
        event: usize,
    };
    pub const To = struct { arrow: usize, name: usize };
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
    fn peek(self: *const State) ?Token {
        assert(self.current < self.tokens.len);
        if (self.current + 1 < self.tokens.len) {
            return self.tokens[self.current + 1];
        }
        return null;
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
    fn identifier(self: *State) Error!?usize {
        return try self.token(.identifier);
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
            .{ .tag = .resources, .child = map },
            .{ .tag = .events, .child = map },
            .{ .tag = .guards, .child = map },
            .{ .tag = .actions, .child = map },
            .{ .tag = .transitions, .child = transition },
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

    fn transition(self: *State) Error!?usize {
        return try self.append(.{ .transition = .{
            .star = try self.token(.star),
            .from = try self.transitionFrom() orelse try self.missing(.paren_left),
            .guard = try self.transitionGuard(),
            .action = try self.transitionAction(),
            .to = try self.transitionTo(),
        } });
    }
    fn transitionFrom(self: *State) Error!?usize {
        return try self.append(.{ .transition_from = .{
            .open = try self.token(.paren_left) orelse return null,
            .state = try self.token(.identifier) orelse try self.tokenOrMissing(.underscore),
            .comma = try self.tokenOrMissing(.comma),
            .event = try self.token(.identifier) orelse try self.tokenOrMissing(.underscore),
            .close = try self.tokenOrMissing(.paren_right),
        } });
    }
    fn transitionGuard(self: *State) Error!?usize {
        const name = try self.token(.@"if") orelse return null;
        const content = try self.many(
            .{ .open = .paren_left, .close = .paren_right, .seperator = .comma },
            identifier,
        );
        return try self.append(.{ .transition_guard = content.of(name) });
    }
    fn transitionAction(self: *State) Error!?usize {
        const name = try self.token(.invoke) orelse return null;
        const content = try self.many(
            .{ .open = .paren_left, .close = .paren_right, .seperator = .comma },
            identifier,
        );
        return try self.append(.{ .transition_guard = content.of(name) });
    }
    fn transitionTo(self: *State) Error!?usize {
        return try self.append(.{ .transition_to = .{
            .arrow = try self.token(.arrow) orelse return null,
            .name = try self.tokenOrMissing(.identifier),
        } });
    }
    fn bare(self: *State) Error!?usize {
        const current = self.currentToken();
        const next = self.peek() orelse return null;

        if (current.type != .identifier or next.type != .string_open) {
            return null;
        }

        return try self.append(.{ .bare = .{
            .name = try self.identifier() orelse unreachable,
            .string = try self.string() orelse unreachable,
        } });
    }
    fn map(self: *State) Error!?usize {
        if (try self.bare()) |index| {
            return try self.append(.{ .map = .{ .bare = index } });
        }

        const name = try self.identifier() orelse return null;
        const result = try self.many(
            .{ .open = .brace_left, .close = .brace_right, .seperator = .comma },
            bare,
        );
        return try self.append(.{ .map = .{ .lang = result.of(name) } });
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
            .bare => |payload| {
                try self.stack.append(gpa, payload.string);
                try self.stack.append(gpa, payload.name);
            },
            .map => |payload| {
                switch (payload) {
                    .bare => |bare| {
                        try self.stack.append(gpa, bare);
                    },
                    .lang => |lang| {
                        try self.stack.append(gpa, lang.close);
                        try self.appendItems(gpa, lang.items.items, lang.seps.items);
                        try self.stack.append(gpa, lang.open);
                        try self.stack.append(gpa, lang.name);
                    },
                }
            },
            .transition => |payload| {
                if (payload.to) |index| {
                    try self.stack.append(gpa, index);
                }
                if (payload.action) |index| {
                    try self.stack.append(gpa, index);
                }
                if (payload.guard) |index| {
                    try self.stack.append(gpa, index);
                }
                try self.stack.append(gpa, payload.from);
                if (payload.star) |index| {
                    try self.stack.append(gpa, index);
                }
            },
            .transition_from => |payload| {
                try self.stack.append(gpa, payload.close);
                try self.stack.append(gpa, payload.event);
                try self.stack.append(gpa, payload.comma);
                try self.stack.append(gpa, payload.state);
                try self.stack.append(gpa, payload.open);
            },
            .transition_to => |payload| {
                try self.stack.append(gpa, payload.name);
                try self.stack.append(gpa, payload.arrow);
            },
            .string => |payload| {
                try self.stack.append(gpa, payload.close);
                try self.stack.append(gpa, payload.content);
                try self.stack.append(gpa, payload.open);
            },
            inline else => |payload, tag| {
                switch (@TypeOf(payload)) {
                    Token, Token.Type => {},
                    Many => {
                        try self.stack.append(gpa, payload.close);
                        try self.appendItems(gpa, payload.items.items, payload.seps.items);
                        try self.stack.append(gpa, payload.open);
                        try self.stack.append(gpa, payload.name);
                    },
                    else => @compileError(std.fmt.comptimePrint(
                        "{} is not handled",
                        .{tag},
                    )),
                }
            },
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
