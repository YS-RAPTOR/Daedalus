const std = @import("std");
const builtins = @import("builtin");
const Application = @import("application.zig").Application;

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

    var app = try Application.init(allocator);
    defer app.deinit();
    try app.run();
}
