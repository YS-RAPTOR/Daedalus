const math = @import("math.zig");
const std = @import("std");
const LimitedMaze = @import("limited_maze.zig").LimitedMaze;
const config = @import("config.zig").config;
const path = @import("path.zig");

pub const Action = union(enum) {
    GoToTarget: math.Vec2(usize),
    Explore: void,
};

pub fn plan(
    allocator: std.mem.Allocator,
    environment: *LimitedMaze,
    starting_location: math.Vec2(usize),
    target_location: math.Vec2(usize),
    actions: *std.ArrayListUnmanaged(Action),
) !void {
    actions.clearRetainingCapacity();
    var converted_environment = environment.convert();
    switch (config.planner) {
        .GOAP => {
            // Implement GOAP planning logic here
            try actions.append(allocator, .{ .Explore = {} });
            return;
        },
        .BehaviorTree => {
            // Check if you can go to the target
            {
                var path_to_target = path.aStar(
                    allocator,
                    &converted_environment,
                    starting_location,
                    target_location,
                    null,
                ) catch null;
                if (path_to_target != null) {
                    defer path_to_target.?.deinit(allocator);
                    try actions.append(allocator, .{ .GoToTarget = target_location });

                    std.debug.print("Pathing to target", .{});
                    return;
                }
            }

            // Check if you have a lever that can be flicked
            if (environment.levers_found.count() > 0) {
                var lever_location: ?math.Vec2(usize) = null;
                var lever_steps: usize = 10_000_000;
                for (environment.levers_found.keys()) |lever| {
                    var path_to_lever = path.aStar(
                        allocator,
                        &converted_environment,
                        starting_location,
                        lever,
                        null,
                    ) catch continue;
                    defer path_to_lever.deinit(allocator);

                    const steps = path_to_lever.items.len;
                    if (steps < lever_steps) {
                        lever_location = lever;
                        lever_steps = steps;
                    }
                }
                if (lever_location) |lever| {
                    try actions.append(allocator, .{ .GoToTarget = lever });

                    std.debug.print("Pathing to lever at {any}\n", .{lever});
                    return;
                }
            }

            // Explore normally
            try actions.append(allocator, .{ .Explore = {} });
            std.debug.print("Exploring normally\n", .{});
            return;
        },
    }
}
