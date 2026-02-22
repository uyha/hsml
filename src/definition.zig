pub const Definition = union(enum) {
    root: Root,

    component: Component,

    resources: Resources,

    events: Events,
    event: Token,

    identifier: Token,
    colon: Token,
    brace_left: Token,
    brace_right: Token,
    comma: Token,

    unexpected: Token,
    missing: Token.Type,
};

pub const Events = std.ArrayList(usize);

pub const Root = struct {
    name: usize,
    brace_left: usize,
    brace_right: usize,
    components: std.ArrayList(usize) = .empty,
    commas: std.ArrayList(usize) = .empty,
};

pub const Resources = struct {
    identifier: usize,
    brace_left: usize,
    brace_right: usize,
};

pub const Component = struct {
    identifier: usize,
    colon: usize,
    brace_left: usize,
    brace_right: usize,
};

test {
    const gpa = t.allocator;

    var reader: std.Io.Reader = .fixed("hello");
    var scanner: Scanner = try .scan(gpa, &reader);
    defer scanner.deinit(gpa);

    var definitions: std.ArrayList(Definition) = .empty;
    defer definitions.deinit(gpa);

    var events: Definition = .{ .events = .empty };
    defer events.events.deinit(gpa);

    try definitions.append(gpa, .{ .event = scanner.tokens.items[0] });
}

const std = @import("std");
const t = std.testing;

const Token = @import("Token.zig");
const Scanner = @import("Scanner.zig");
