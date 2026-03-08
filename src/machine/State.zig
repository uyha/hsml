name: []const u8,

events: std.ArrayList(void) = .empty,
guards: std.ArrayList(void) = .empty,
actions: std.ArrayList(void) = .empty,
transitions: std.ArrayList(void) = .empty,

const std = @import("std");
