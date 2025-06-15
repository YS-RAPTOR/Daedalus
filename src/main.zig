const std = @import("std");
const builtins = @import("builtin");
const Application = @import("application.zig").Application;
const Timer = @import("debug.zig").Timer;
const config = @import("config.zig").config;

pub fn main() !void {
    // Initialize allocator
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const allocator, const is_debug = gpa: {
        break :gpa switch (builtins.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    var timer: Timer = .start();
    defer timer.timestamp("Maze Completed");

    std.debug.print("Planner: {}, has snapshot: {}, Maze Size: {}, No of Doors: {}\n", .{
        config.planner,
        config.has_snapshot_at_start,
        config.maze_size,
        config.no_of_doors,
    });

    var app = try Application.init(allocator);
    defer app.deinit();
    try app.run();
}
