fn openFile(io: Io, path: []const u8) Io.File.OpenError!Io.File {
    if (std.fs.path.isAbsolute(path)) {
        return Io.Dir.openFileAbsolute(io, path, .{});
    }
    return Io.Dir.cwd().openFile(io, path, .{});
}

pub fn main(init: Init) !void {
    try parse(init);
}

fn scanFile(init: Init) !void {
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

fn parse(init: Init) !void {
    const arena = init.arena.allocator();

    var reader: std.Io.Reader = .fixed(
        \\simple {
        \\  resources {
        \\    motor: *Motor,
        \\    road: *const road,
        \\  },
        \\  events {red, yellow, green, speed}
        \\
    );
    var scanner: Scanner = try .scan(arena, &reader);
    defer scanner.deinit(arena);

    const ast: Ast = try .parse(
        arena,
        scanner.content.items,
        scanner.tokens.items,
    );
    std.debug.print("root: {}\n", .{ast.root});

    {
        var iter = try ast.iterator(arena);
        while (try iter.next(arena)) |node| {
            std.debug.print("{}\n", .{node});
        }
    }

    const content = scanner.content.items;

    var iter = try ast.iterator(arena);
    while (try iter.next(arena)) |node| {
        switch (node) {
            inline else => |payload| {
                if (@TypeOf(payload) == hsml.Token) {
                    std.debug.print("{s} ", .{payload.lexeme(content)});
                }
            },
        }
    }
    std.debug.print("\n", .{});

    // const scanned = scanner.tokens.items;
    // const parsed = tokens.items;
    //
    // std.debug.print("{} {}\n", .{ scanned.len, parsed.len });
    // for (
    //     scanner.tokens.items[0 .. scanner.tokens.items.len - 1],
    //     tokens.items,
    // ) |in, out| {
    //     std.debug.print("{} {}\n", .{ in.type == out.type, in.pos == out.pos });
    // }
}

const hsml = @import("hsml");
const Scanner = hsml.Scanner;
const Ast = hsml.Ast;

const std = @import("std");
const Init = std.process.Init;
const Io = std.Io;
