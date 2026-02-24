const Cursor = @This();

line: usize = 0,
col: usize = 0,

pub fn format(
    self: Cursor,
    writer: *std.Io.Writer,
) std.Io.Writer.Error!void {
    try writer.print(".{{ .line = {}, .col = {} }}", .{ self.line, self.col });
}

const std = @import("std");
