fn openFile(io: Io, path: []const u8) Io.File.OpenError!Io.File {
    if (std.fs.path.isAbsolute(path)) {
        return Io.Dir.openFileAbsolute(io, path, .{});
    }
    return Io.Dir.cwd().openFile(io, path, .{});
}

pub fn main(init: Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();

    var iter = init.minimal.args.iterate();
    _ = iter.skip();

    const path = iter.next() orelse {
        try std.Io.File.stderr().writeStreamingAll(init.io, "Please give an input path\n");
        return;
    };
    const file: std.Io.File = try openFile(io, path);
    defer file.close(io);

    var buffer: [128]u8 = undefined;
    var freader = file.readerStreaming(io, &buffer);
    const reader = &freader.interface;

    const scanner: Scanner = try .scan(arena, reader);

    for (scanner.tokens.items) |token| {
        std.debug.print("{} \"{s}\"\n", .{ token, token.lexeme(scanner.content.items) });
    }
}

const hsml = @import("hsml");
const Scanner = hsml.Scanner;

const std = @import("std");
const Init = std.process.Init;
const Io = std.Io;
