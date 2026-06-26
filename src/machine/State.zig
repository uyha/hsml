const State = @This();

name: []const u8,
definition: Definition,

pub fn bare(name: []const u8) State {
    return .{ .name = name, .definition = .bare };
}
pub fn import(name: []const u8, source: []const u8) State {
    return .{ .name = name, .definition = .{ .import = source } };
}
pub fn full(name: []const u8) State {
    return .{
        .name = name,
        .definition = .{
            .full = .{
                .state = .empty,
                .events = .empty,
                .guards = .empty,
                .actions = .empty,
                .transitions = .empty,
            },
        },
    };
}

pub const Full = struct {
    state: std.ArrayList(State),
    events: std.ArrayList(Event),
    guards: std.ArrayList(void),
    actions: std.ArrayList(void),
    transitions: std.ArrayList(void),
};
pub const Definition = union(enum) {
    bare: void,
    import: []const u8,
    full: Full,
};

const std = @import("std");

const Event = @import("Event.zig");
