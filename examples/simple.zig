const State = enum { running, pausing, accelerating };
const Event = enum { red, yellow, green, speed };

pub fn has_pedestrian() bool {
    return false;
}
pub fn stable_speed() bool {
    return true;
}

pub fn harsh_stop() void {
    std.debug.print("{s}:{} ({s})\n", .{ @src().file, @src().line, @src().fn_name });
}
pub fn soft_stop() void {
    std.debug.print("{s}:{} ({s})\n", .{ @src().file, @src().line, @src().fn_name });
}
pub fn accelerate() void {
    std.debug.print("{s}:{} ({s})\n", .{ @src().file, @src().line, @src().fn_name });
}

const StateMachine = struct {
    state: State = .pausing,

    pub const init: StateMachine = .{};

    pub fn process(self: *StateMachine, event: Event) void {
        switch (self.state) {
            .running => {
                switch (event) {
                    .red => {
                        harsh_stop();
                        self.state = .pausing;
                    },
                    .yellow => {
                        soft_stop();
                        self.state = .pausing;
                    },
                    .green => {
                        if (has_pedestrian()) {
                            harsh_stop();
                            self.state = .pausing;
                        }
                    },
                    else => {},
                }
            },
            .pausing => {
                switch (event) {
                    .green => {
                        if (!has_pedestrian()) {
                            accelerate();
                            self.state = .accelerating;
                        }
                    },
                    else => {},
                }
            },
            .accelerating => {
                switch (event) {
                    .speed => {
                        if (stable_speed()) {
                            std.debug.print("{s}:{} ({s})\n", .{ @src().file, @src().line, @src().fn_name });
                            self.state = .running;
                        }
                    },
                    else => {},
                }
            },
        }
    }
};

pub fn main() !void {
    var sm: StateMachine = .{};

    sm.process(.green);
    sm.process(.speed);
}

const std = @import("std");
