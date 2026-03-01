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
        \\    motor [[*Motor]],
        \\    road {
        \\      zig [[*const Road]],
        \\      cpp [[Road const &]],
        \\    }
        \\  },
        \\
        \\  states {
        \\    running from [[running.hsml]],
        \\    pausing,
        \\    accelerating,
        \\  },
        \\
        \\  events {red [[Red]], yellow [[Yellow]], green [[Green]], speed [[Speed]]},
        \\
        \\  guards {
        \\    has_pedestrian [[self.road.has_pedestrian()]],
        \\    has_fuel {
        \\      zig [[has_fuel(self.motor)]],
        \\      cpp [[nope()]],
        \\    }
        \\  },
        \\
        \\  actions {
        \\    harsh_stop [[self.motor.harsh_stop()]],
        \\    soft_stop [[self.motor.soft_stop()]],
        \\    accelerate {
        \\      zig [[self.motor.accelerate()]],
        \\      cpp [[this->motor.accelerate()]],
        \\    },
        \\  },
        \\
        \\  transitions {
        \\   *(pausing, green) when (has_pedestrian) call (accelerate) goto accelerating,
        \\
        \\    (running, red) call (harsh_stop) goto pausing,
        \\    (running, yellow) call (soft_stop) goto pausing,
        \\    (running, green) when (has_pedestrian) call (harsh_stop) goto pausing,
        \\
        \\    (_, speed) when (stable_speed) goto running,
        \\  },
        \\}
    );
    const scan_start = Clock.boot.now(init.io);
    var scanner: Scanner = try .scan(arena, &reader);
    const scan_end = Clock.boot.now(init.io);
    defer scanner.deinit(arena);

    const parse_start = Clock.boot.now(init.io);
    const ast: Ast = try .parse(arena, scanner.content.items, scanner.tokens.items);
    const parse_end = Clock.boot.now(init.io);
    std.debug.print("root: {}\n", .{ast.root});

    {
        var iter = try ast.iterator(arena);
        while (try iter.next(arena)) |node| {
            std.debug.print("{}\n", .{node});
        }
        std.debug.print("\n", .{});
    }

    const content = scanner.content.items;
    {
        var iter = try ast.iterator(arena);
        while (try iter.next(arena)) |node| {
            switch (node) {
                inline else => |payload| {
                    if (@TypeOf(payload) == hsml.Token) {
                        if (payload.type == .eof) {
                            std.debug.print("<eof>\n", .{});
                        } else {
                            std.debug.print("{s} ", .{payload.lexeme(content)});
                        }
                    }
                },
            }
        }
    }

    std.debug.print("scanning took {}ns\n", .{scan_start.durationTo(scan_end).nanoseconds});
    std.debug.print("parsing took {}ns\n", .{parse_start.durationTo(parse_end).nanoseconds});
}

const hsml = @import("hsml");
const Scanner = hsml.Scanner;
const Ast = hsml.Ast;

const std = @import("std");
const Init = std.process.Init;
const Io = std.Io;
const Clock = Io.Clock;
