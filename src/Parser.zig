const Parser = @This();
pub const Error = std.mem.Allocator.Error;

root: usize,
definitions: std.ArrayList(Definition) = .empty,

pub fn parse(
    arena: std.mem.Allocator,
    content: *const std.ArrayList(u8),
    tokens: *const std.ArrayList(Token),
) Error!Parser {
    var parser: Parser = .{ .root = undefined };

    var state: State = .{
        .arena = arena,

        .definitions = &parser.definitions,
        .content = content,
        .tokens = tokens,
    };
    parser.root = try state.parse();

    return parser;
}

const State = struct {
    arena: Allocator,

    definitions: *std.ArrayList(Definition),
    content: *const std.ArrayList(u8),
    tokens: *const std.ArrayList(Token),

    current: usize = 0,

    fn parse(self: *State) Error!usize {
        return self.root();
    }

    fn currentToken(self: *const State) Token {
        assert(self.current < self.tokens.items.len);
        return self.tokens.items[self.current];
    }
    fn lexeme(self: *const State, source: Token) []const u8 {
        assert(self.current < self.tokens.items.len);
        return source.lexeme(self.content.items);
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
    fn identifier(self: *State) Error!?usize {
        return try self.token(.identifier);
    }
    fn colon(self: *State) Error!?usize {
        return try self.token(.colon);
    }
    fn braceLeft(self: *State) Error!?usize {
        return try self.token(.brace_left);
    }
    fn braceRight(self: *State) Error!?usize {
        return try self.token(.brace_right);
    }
    fn comma(self: *State) Error!?usize {
        return self.token(.comma);
    }

    fn root(self: *State) Error!usize {
        const name_index = try self.identifier() orelse try self.unexpected();

        var components: std.ArrayList(usize) = .empty;
        var commas: std.ArrayList(usize) = .empty;

        const brace_left_index = try self.braceLeft() orelse try self.unexpected();

        const brace_right_index = blk: {
            if (try self.braceRight()) |index| {
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
                if (try self.comma()) |index| {
                    try commas.append(self.arena, index);
                }

                if (try self.braceRight()) |index| {
                    break :blk index;
                }
            }
        };

        return try self.append(.{
            .root = .{
                .name = name_index,
                .brace_left = brace_left_index,
                .components = components,
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
        const brace_left_index = try self.braceLeft() orelse try self.unexpected();
        const brace_right_index = try self.braceRight() orelse try self.unexpected();

        return try self.append(.{ .resources = .{
            .identifier = name_index,
            .brace_left = brace_left_index,
            .brace_right = brace_right_index,
        } });
    }
};

test {
    const gpa = t.allocator;
    var arena: ArenaAllocator = .init(gpa);
    defer arena.deinit();

    var reader: std.Io.Reader = .fixed(
        \\simple {
        \\  resources {},
        \\}
    );
    const scanner: Scanner = try .scan(arena.allocator(), &reader);
    const parser: Parser = try .parse(
        arena.allocator(),
        &scanner.content,
        &scanner.tokens,
    );

    try t.expectEqualDeep(&[_]Definition{
        .{ .identifier = scanner.tokens.items[0] },
        .{ .brace_left = scanner.tokens.items[1] },
        .{ .identifier = scanner.tokens.items[2] },
        .{ .brace_left = scanner.tokens.items[3] },
        .{ .brace_right = scanner.tokens.items[4] },
        .{ .resources = .{
            .identifier = 2,
            .brace_left = 3,
            .brace_right = 4,
        } },
        .{ .comma = scanner.tokens.items[5] },
        .{ .brace_right = scanner.tokens.items[6] },
    }, parser.definitions.items[0..8]);

    const root = parser.definitions.items[parser.root];
    const name = parser.definitions.items[root.root.name].identifier;

    try t.expect(root == .root);
    try t.expectEqualStrings("simple", name.lexeme(scanner.content.items));
    try t.expectEqualSlices(usize, &.{5}, root.root.components.items);
    try t.expectEqualSlices(usize, &.{6}, root.root.commas.items);
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const assert = std.debug.assert;
const t = std.testing;

const definition = @import("definition.zig");
const Definition = definition.Definition;
const Root = definition.Root;
const Scanner = @import("Scanner.zig");
const Token = @import("Token.zig");
