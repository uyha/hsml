const Event = @This();

name: []const u8,

definition: Definition,

pub const Definition = union(enum) {
    bare: []const u8,
    lang: Lang,
};

pub fn bare(name: []const u8, content: []const u8) Event {
    return .{
        .name = name,
        .definition = .{ .bare = content },
    };
}
pub fn lang(name: []const u8, map: Lang) Event {
    return .{
        .name = name,
        .definition = .{ .lang = map },
    };
}

const std = @import("std");
pub const Lang = std.StringHashMapUnmanaged([]const u8);
