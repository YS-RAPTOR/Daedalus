const std = @import("std");

pub const Timer = struct {
    time: i64,

    pub fn start() @This() {
        return Timer{ .time = std.time.microTimestamp() };
    }

    pub fn timestamp(self: *@This(), message: []const u8) void {
        const current_time = std.time.microTimestamp();
        std.debug.print("Timestamp: {s}, Elapsed: {d} ns\n", .{
            message,
            current_time - self.time,
        });
        self.time = current_time;
    }
};
