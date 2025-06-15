const math = @import("math.zig");
const std = @import("std");
const LimitedMaze = @import("limited_maze.zig").LimitedMaze;
const Cell = @import("maze.zig").Cell;
const config = @import("config.zig").config;
const path = @import("path.zig");
const Timer = @import("debug.zig").Timer;

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
    var timer: Timer = .start();
    defer timer.timestamp("Planning Completed");
    actions.clearRetainingCapacity();
    switch (config.planner) {
        .GOAP => {
            // Implement GOAP planning logic here
            const no_of_levers = environment.levers_found.count();
            const action_list = try allocator.alloc(
                math.Vec2(usize),
                no_of_levers + 1,
            );
            defer allocator.free(action_list);
            @memcpy(action_list[0..no_of_levers], environment.levers_found.keys());
            action_list[action_list.len - 1] = target_location;

            if (try goap(
                allocator,
                environment,
                starting_location,
                .ReachTarget,
                action_list,
                actions,
            )) return;

            if (no_of_levers > 0) {
                if (try goap(
                    allocator,
                    environment,
                    starting_location,
                    .FlickLever,
                    action_list,
                    actions,
                )) return;
            }

            try actions.append(allocator, .{ .Explore = {} });
            return;
        },
        .BehaviorTree => {
            // Check if you can go to the target
            {
                var path_to_target, _ = path.aStar(
                    allocator,
                    environment,
                    starting_location,
                    target_location,
                    null,
                ) catch .{ null, 0 };
                if (path_to_target != null) {
                    defer path_to_target.?.deinit(allocator);
                    try actions.append(allocator, .{ .GoToTarget = target_location });

                    return;
                }
            }

            // Check if you have a lever that can be flicked
            if (environment.levers_found.count() > 0) {
                var lever_location: ?math.Vec2(usize) = null;
                var lever_cost: usize = 10_000_000;
                for (environment.levers_found.keys()) |lever| {
                    var path_to_lever, const cost = path.aStar(
                        allocator,
                        environment,
                        starting_location,
                        lever,
                        null,
                    ) catch continue;
                    defer path_to_lever.deinit(allocator);

                    if (cost < lever_cost) {
                        lever_location = lever;
                        lever_cost = cost;
                    }
                }
                if (lever_location) |lever| {
                    try actions.append(allocator, .{ .GoToTarget = lever });

                    return;
                }
            }

            // Explore normally
            try actions.append(allocator, .{ .Explore = {} });
            return;
        },
    }
}

const GOAPState = struct {
    location: math.Vec2(usize),
    environment: LimitedMaze,
    previous_state: ?*GOAPState,
    levers_flicked: usize,
};

const AStarElem = struct {
    value: usize,
    state: *GOAPState,
};

fn heuristic(state: *GOAPState, goal: Goal) usize {
    switch (goal) {
        .ReachTarget => return path.heuristic(state.location, state.environment.target),
        .FlickLever => {
            var smallest_heuristic: usize = 10_000_000;
            for (state.environment.levers_found.keys()) |lever| {
                const h = path.heuristic(state.location, lever);
                if (h < smallest_heuristic) {
                    smallest_heuristic = h;
                }
            }
            return smallest_heuristic;
        },
    }
}

const Heap = std.PriorityQueue(AStarElem, void, struct {
    pub fn order(ctx: void, a: AStarElem, b: AStarElem) std.math.Order {
        _ = ctx;
        if (a.value < b.value) {
            return .lt;
        } else if (a.value > b.value) {
            return .gt;
        } else {
            // If values are equal, use heuristic to break ties
            const heuristic_a = path.heuristic(a.state.location, b.state.location);
            const heuristic_b = path.heuristic(b.state.location, a.state.location);
            if (heuristic_a < heuristic_b) {
                return .lt;
            } else if (heuristic_a > heuristic_b) {
                return .gt;
            } else {
                return .eq;
            }
        }
    }
}.order);

fn canPerformAction(
    allocator: std.mem.Allocator,
    state: *GOAPState,
    location: math.Vec2(usize),
) !struct { bool, usize } {
    var loop = state;
    while (loop.previous_state) |prev| {
        if (prev.location.equals(location)) {
            return .{ false, 0 };
        }
        loop = prev;
    }

    var path_to_location, const cost = path.aStar(
        allocator,
        &state.environment,
        state.location,
        location,
        null,
    ) catch |err| {
        if (err == error.NoPathFound) {
            return .{ false, 0 };
        }
        return err;
    };
    defer path_to_location.deinit(allocator);

    return .{ true, cost };
}

fn performAction(
    allocator: std.mem.Allocator,
    state: *GOAPState,
    location: math.Vec2(usize),
) !*GOAPState {
    const new_state = try allocator.create(GOAPState);
    new_state.* = .{
        .environment = try state.environment.cloneForPlanner(allocator),
        .location = location,
        .previous_state = state,
        .levers_flicked = state.levers_flicked,
    };
    if (new_state.environment.flipLeverForPlanning(location)) {
        new_state.levers_flicked += 1;
    }
    return new_state;
}

const Goal = enum { ReachTarget, FlickLever };

fn hasReachedGoal(state: *GOAPState, goal: Goal) bool {
    switch (goal) {
        .ReachTarget => return state.location.equals(state.environment.target),
        .FlickLever => return state.levers_flicked > 1,
    }
}

fn goap(
    allocator: std.mem.Allocator,
    environment: *LimitedMaze,
    starting_position_cell: math.Vec2(usize),
    goal: Goal,
    locations: []math.Vec2(usize),
    actions: *std.ArrayListUnmanaged(Action),
) !bool {
    var arena = std.heap.ArenaAllocator.init(allocator);
    const arena_allocator = arena.allocator();
    defer arena.deinit();

    const initial_state = try arena_allocator.create(GOAPState);
    initial_state.* = .{
        .environment = try environment.cloneForPlanner(arena_allocator),
        .location = starting_position_cell,
        .previous_state = null,
        .levers_flicked = 0,
    };

    var open: Heap = .init(arena_allocator, {});
    try open.add(.{
        .value = heuristic(initial_state, goal),
        .state = initial_state,
    });

    while (open.removeOrNull()) |e| {
        if (hasReachedGoal(e.state, goal)) {
            var current = e.state;

            while (current.previous_state) |prev| {
                try actions.append(allocator, .{ .GoToTarget = current.location });
                current = prev;
            }
            return true;
        }

        const cost = e.value - heuristic(e.state, goal);

        for (locations) |location| {
            if (location.equals(e.state.location)) continue;
            const can_perform, const steps = try canPerformAction(
                allocator,
                e.state,
                location,
            );
            if (!can_perform) continue;

            const new_state = try performAction(
                arena_allocator,
                e.state,
                location,
            );

            const cost_g = cost + steps;
            const cost_h = heuristic(new_state, goal);
            const total_cost = cost_g + cost_h;

            var found: ?AStarElem = null;
            var iter = open.iterator();
            var index: usize = 0;

            while (iter.next()) |f| {
                if (f.state.location.equals(location)) {
                    found = f;
                    break;
                }
                index += 1;
            }

            if (found) |f| {
                if (f.value > total_cost) {
                    _ = open.removeIndex(index);
                } else {
                    continue;
                }
            }
            try open.add(.{
                .value = total_cost,
                .state = new_state,
            });
        }
    }
    return false;
}
