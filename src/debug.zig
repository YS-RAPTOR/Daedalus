const std = @import("std");

pub const Timer = struct {
    time: u64,

    pub fn start() @This() {
        return Timer{ .time = std.time.milliTimestamp() };
    }

    pub fn timestamp(self: *@This(), message: []const u8) u64 {
        const current_time = std.time.milliTimestamp();
        std.debug.print("Timestamp: {s}, Elapsed: {d} ms\n", .{
            message,
            current_time - self.time,
        });
        self.time = current_time;
    }
};
