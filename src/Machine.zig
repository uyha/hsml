const Machine = @This();

states: std.ArrayList(State),

pub const Parsed = struct {
    content: []const u8,
    tokens: []const Token,

    root: usize,
    eof: usize,
    nodes: []const Ast.Node,
};

pub const Error = Allocator.Error || error{ MissingRootState, MissingNode, MismatchNode };

pub fn init(arena: Allocator, parsed: Parsed) Error!Machine {
    var states: std.ArrayList(State) = .empty;
    var walker: Walker = try .init(arena, parsed, &states);
    defer walker.deinit(arena);

    try walker.walk(arena);

    return .{ .states = states };
}

const Walker = struct {
    content: []const u8,
    tokens: []const Token,

    root: usize,
    eof: usize,
    nodes: []const Ast.Node,

    states: *std.ArrayList(State),

    iter: Ast.Iterator,

    fn init(
        gpa: Allocator,
        parsed: Parsed,
        states: *std.ArrayList(State),
    ) Allocator.Error!Walker {
        return .{
            .content = parsed.content,
            .tokens = parsed.tokens,
            .nodes = parsed.nodes,
            .root = parsed.root,
            .eof = parsed.eof,
            .states = states,
            .iter = try .init(gpa, &.{parsed.root}, parsed.nodes),
        };
    }
    fn deinit(self: *Walker, gpa: Allocator) void {
        self.iter.deinit(gpa);
    }

    fn walk(self: *Walker, gpa: Allocator) Error!void {
        const root = try self.iter.next(gpa) orelse return error.MissingRootState;

        if (root != .state) {
            return error.MissingRootState;
        }

        const name = try self.getIdentifier(gpa);
        const state = try self.states.addOne(gpa);

        switch (root.state) {
            .bare => state.* = .bare(name),
            .import => {
                try self.discard(gpa, .from);
                state.* = .import(name, try self.getString(gpa));
            },
            .full => {
                state.* = .full(name);
                try self.discard(gpa, .brace_open);

                while (self.iter.peek()) |node| switch (node) {
                    .brace_close => {
                        try self.discard(gpa, .brace_close);
                        break;
                    },
                    .events => {
                        state.definition.full.events = try self.getEvents(gpa);
                    },
                    else => {
                        _ = try self.iter.next(gpa);
                    },
                };

                for (state.definition.full.events.items) |event| {
                    switch (event.definition) {
                        .bare => |value| std.debug.print("{s} {s}\n", .{ event.name, value }),
                        .lang => |value| {
                            var iter = value.iterator();
                            while (iter.next()) |entry| {
                                std.debug.print(
                                    "{s}: {s} {s}\n",
                                    .{ event.name, entry.key_ptr.*, entry.value_ptr.* },
                                );
                            }
                        },
                    }
                }
            },
        }
    }

    fn discard(
        self: *Walker,
        gpa: Allocator,
        expected: @typeInfo(Ast.Node).@"union".tag_type.?,
    ) Error!void {
        const node = try self.iter.next(gpa) orelse return error.MissingNode;
        if (node != expected) {
            std.debug.print("{}\n", .{node});
            return error.MismatchNode;
        }
    }

    fn getToken(
        self: *Walker,
        gpa: Allocator,
        comptime expected: @typeInfo(Ast.Node).@"union".tag_type.?,
    ) Error!Token {
        const node = try self.iter.next(gpa) orelse return error.MissingNode;

        if (node != expected) {
            std.debug.print("{}\n", .{node});
            return error.MismatchNode;
        }

        return @field(node, @tagName(expected));
    }
    fn getIdentifier(self: *Walker, gpa: Allocator) Error![]const u8 {
        const content = try self.getToken(gpa, .identifier);
        return content.lexeme(self.content);
    }
    fn getMap(self: *Walker, gpa: Allocator) Error!Ast.Map {
        const node = try self.iter.next(gpa) orelse return error.MissingNode;

        if (node != .map) {
            std.debug.print("{}\n", .{node});
            return error.MissingNode;
        }

        return node.map;
    }
    fn getBare(self: *Walker, gpa: Allocator) Error!Ast.Bare {
        const node = try self.iter.next(gpa) orelse return error.MissingNode;

        if (node != .bare) {
            std.debug.print("{}\n", .{node});
            return error.MissingNode;
        }

        return node.bare;
    }
    fn getEvents(self: *Walker, gpa: Allocator) Error!std.ArrayList(Event) {
        try self.discard(gpa, .events);
        try self.discard(gpa, .identifier);
        try self.discard(gpa, .brace_open);

        var result: std.ArrayList(Event) = .empty;

        while (self.iter.peek()) |node| switch (node) {
            .map => {
                try result.append(gpa, try self.getEvent(gpa));
            },
            .comma => try self.discard(gpa, .comma),
            .brace_close => {
                try self.discard(gpa, .brace_close);
                break;
            },
            else => |value| {
                std.debug.print("{}\n", .{value});
                unreachable;
            },
        };

        return result;
    }
    fn getEvent(self: *Walker, gpa: Allocator) Error!Event {
        const map = try self.getMap(gpa);
        switch (map) {
            .bare => {
                try self.discard(gpa, .bare);
                return .bare(try self.getIdentifier(gpa), try self.getString(gpa));
            },
            .lang => {
                return .lang(try self.getIdentifier(gpa), try self.getLang(gpa));
            },
        }
    }
    fn getString(self: *Walker, gpa: Allocator) Error![]const u8 {
        try self.discard(gpa, .string);
        try self.discard(gpa, .string_open);

        const content = try self.getToken(gpa, .string_content);
        try self.discard(gpa, .string_close);

        return content.lexeme(self.content);
    }
    fn getLang(self: *Walker, gpa: Allocator) Error!Event.Lang {
        try self.discard(gpa, .brace_open);

        var result: Event.Lang = .empty;

        while (self.iter.peek()) |node| {
            switch (node) {
                .bare => {
                    try self.discard(gpa, .bare);
                    try result.put(gpa, try self.getIdentifier(gpa), try self.getString(gpa));
                },
                .comma => try self.discard(gpa, .comma),
                .brace_close => {
                    try self.discard(gpa, .brace_close);
                    break;
                },
                else => |value| {
                    std.debug.print("{}\n", .{value});
                    unreachable;
                },
            }
        }

        return result;
    }
};

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Token = @import("Token.zig");
const Ast = @import("Ast.zig");

const State = @import("machine/State.zig");
const Event = @import("machine/Event.zig");
