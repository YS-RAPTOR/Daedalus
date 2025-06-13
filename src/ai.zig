const std = @import("std");
const math = @import("math.zig");
const path = @import("path.zig");
const maze = @import("maze.zig");
const config = @import("config.zig").config;
const Entity = @import("entity.zig").Entity;

pub const AI = struct {
    cell_position: math.Vec2(usize),
    position: math.Vec2(f32),
    velocity: math.Vec2(f32),
    acceleration: math.Vec2(f32),
    force: math.Vec2(f32),

    dead: bool = false,
    win: bool = false,
    target: math.Vec2(f32),
    energy_level: f32,

    corners: std.ArrayListUnmanaged(path.Corner),
    current_corner: usize,

    const PlanState = struct {
        energy: f32,
        location: math.Vec2(usize),
        previous_state: ?*PlanState = null,
    };

    const AStarElem = struct {
        value: usize,
        state: *PlanState,
    };

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
        environment: *maze.Maze,
        state: *PlanState,
        location: math.Vec2(usize),
    ) !struct { bool, usize } {
        var loop = state;
        while (loop.previous_state) |prev| {
            if (prev.location.equals(location)) {
                return .{ false, 0 };
            }
            loop = prev;
        }

        const max_steps: isize = @intFromFloat(
            (config.max_energy_level / config.energy_multiplier) * config.energy_mistake_multiplier,
        );

        var path_to_location = path.aStar(
            allocator,
            environment,
            state.location,
            location,
            max_steps,
        ) catch |err| {
            if (err == error.NoPathFound) {
                return .{ false, 0 };
            }
            return err;
        };
        defer path_to_location.deinit(allocator);

        if (path_to_location.items.len >= max_steps) {
            return .{ false, 0 };
        }
        return .{ true, path_to_location.items.len };
    }

    fn performAction(
        allocator: std.mem.Allocator,
        state: *PlanState,
        location: math.Vec2(usize),
    ) !*PlanState {
        const new_state = try allocator.create(PlanState);
        new_state.* = .{
            .energy = config.max_energy_level,
            .location = location,
            .previous_state = state,
        };
        return new_state;
    }

    fn plan(
        allocator: std.mem.Allocator,
        environment: *maze.Maze,
        starting_position_cell: math.Vec2(usize),
        target_position_cell: math.Vec2(usize),
        locations: []math.Vec2(usize),
    ) !std.ArrayListUnmanaged(math.Vec2(usize)) {
        var arena = std.heap.ArenaAllocator.init(allocator);
        const arena_allocator = arena.allocator();
        defer arena.deinit();

        const initial_state = try arena_allocator.create(PlanState);
        initial_state.* = .{
            .energy = config.max_energy_level,
            .location = starting_position_cell,
            .previous_state = null,
        };

        var open: Heap = .init(arena_allocator, {});
        try open.add(.{
            .value = path.heuristic(starting_position_cell, target_position_cell),
            .state = initial_state,
        });

        while (open.removeOrNull()) |e| {
            if (e.state.location.equals(target_position_cell)) {
                var full_path: std.ArrayListUnmanaged(math.Vec2(usize)) = .empty;
                var current = e.state;

                while (current.previous_state) |prev| {
                    var path_section = try path.aStar(
                        allocator,
                        environment,
                        prev.location,
                        current.location,
                        null,
                    );
                    defer path_section.deinit(allocator);
                    try full_path.appendSlice(allocator, path_section.items);
                    current = prev;
                }
                try full_path.append(allocator, starting_position_cell);
                return full_path;
            }

            const cost = e.value - path.heuristic(e.state.location, target_position_cell);

            for (locations) |location| {
                if (location.equals(e.state.location)) continue;
                const can_perform, const steps = try canPerformAction(
                    allocator,
                    environment,
                    e.state,
                    location,
                );
                if (!can_perform) continue;

                const cost_g = cost + steps;
                const cost_h = path.heuristic(location, target_position_cell);
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
                const new_state = try performAction(
                    arena_allocator,
                    e.state,
                    location,
                );
                try open.add(.{
                    .value = total_cost,
                    .state = new_state,
                });
            }
        }
        std.debug.print(
            "No Plan found from {any} to {any}\n",
            .{ starting_position_cell, target_position_cell },
        );
        return error.NoPathFound;
    }

    pub fn init(
        allocator: std.mem.Allocator,
        starting_position_cell: math.Vec2(usize),
        target_position_cell: math.Vec2(usize),
        environment: *maze.Maze,
    ) !@This() {
        var locations: std.ArrayListUnmanaged(math.Vec2(usize)) = try .initCapacity(
            allocator,
            config.no_of_energy_cells + 1,
        );
        defer locations.deinit(allocator);

        for (0..config.maze_size) |i| {
            for (0..config.maze_size) |j| {
                if (environment.cells.items[environment.getIndex(i, j)].energy) {
                    locations.appendAssumeCapacity(.{ .x = i, .y = j });
                }
            }
        }
        locations.appendAssumeCapacity(target_position_cell);

        var path_to_target = try plan(
            allocator,
            environment,
            starting_position_cell,
            target_position_cell,
            locations.items,
        );
        defer path_to_target.deinit(allocator);

        // For Debug purposes
        for (path_to_target.items) |pos| {
            const index = environment.getIndex(pos.x, pos.y);
            environment.cells.items[index].path = true;
        }

        var corners = try path.findCorners(
            allocator,
            path_to_target.items,
        );
        errdefer corners.deinit(allocator);

        // For Debug purposes
        for (corners.items) |corner| {
            const index = environment.getIndex(corner.location.x, corner.location.y);
            environment.cells.items[index].corner = true;
        }

        const position = starting_position_cell.cast(f32).add(.init(0.5, 0.5));
        const target = target_position_cell.cast(f32).add(.init(0.5, 0.5));

        return .{
            .cell_position = starting_position_cell,
            .force = .Zero,
            .acceleration = .Zero,
            .velocity = .Zero,
            .position = position,
            .energy_level = config.max_energy_level,
            .corners = corners,
            .target = target,
            .current_corner = corners.items.len,
        };
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.corners.deinit(allocator);
    }

    pub fn setDirection(self: *@This()) void {
        if (self.current_corner == 0) {
            self.force = self.target.subtract(self.position).normalize();
            return;
        }

        const current_corner = self.corners.items[self.current_corner - 1];
        const corner_position = current_corner.location.cast(f32).add(.init(0.5, 0.5));
        const displacement = corner_position.subtract(self.position);
        const distance_to_corner = displacement.trueLength();
        const direction = displacement.divide(distance_to_corner);

        const speed = self.velocity.length();
        if (distance_to_corner < config.corner_lerp_distance) {
            self.force = math.lerp(
                current_corner.direction.cast(f32),
                direction,
                distance_to_corner / config.corner_lerp_distance,
            );
        } else if (distance_to_corner < config.slow_down_distance and speed > config.slow_down_speed) {
            self.force = direction.multiply(-1);
        } else {
            self.force = direction;
        }

        if (distance_to_corner < config.corner_reached_distance) {
            // Move to the next corner
            self.current_corner -= 1;
        }
    }

    pub fn update(self: *@This(), delta_time: f32, environment: *maze.Maze) void {
        if (self.dead) {
            return;
        }

        if (self.win) {
            return;
        }

        self.setDirection();
        self.cell_position = .{
            .x = @intFromFloat(@trunc(self.position.x)),
            .y = @intFromFloat(@trunc(self.position.y)),
        };

        if (environment.consumeEnergy(self.cell_position)) {
            self.energy_level = config.max_energy_level;
        }

        // Update Player Position and Velocity
        if (self.velocity.length() > 0) {
            var friction_force = self.velocity.normalize();
            friction_force = friction_force.multiply(-config.friction * config.mass * 9.81);
            self.force = self.force.add(friction_force);
        }
        self.acceleration = self.force.divide(config.mass);
        self.velocity = self.velocity.add(
            self.acceleration.multiply(delta_time),
        );
        self.position = self.position.add(
            self.velocity.multiply(delta_time),
        );
        self.force = .Zero;

        // Update Player Energy Level
        const energy_consumed = self.velocity.trueLength() * config.energy_multiplier;
        self.energy_level -= energy_consumed;

        if (self.energy_level < 0) {
            self.dead = true;
        }

        if (self.target.subtract(self.position).trueLength() < config.corner_reached_distance) {
            self.win = true;
        }
    }

    pub fn submitEntities(self: *@This(), entities: []Entity, offset: usize, cell_size: f32) usize {
        const player_radius: f32 = cell_size * config.player_radius_percentage;

        // Player
        entities[offset] = .{
            .position = self.position,
            .radius = player_radius,
            .entiy_type = blk: {
                if (self.energy_level > config.max_energy_level * 0.9) {
                    break :blk .Player10;
                } else if (self.energy_level > config.max_energy_level * 0.8) {
                    break :blk .Player9;
                } else if (self.energy_level > config.max_energy_level * 0.7) {
                    break :blk .Player8;
                } else if (self.energy_level > config.max_energy_level * 0.6) {
                    break :blk .Player7;
                } else if (self.energy_level > config.max_energy_level * 0.5) {
                    break :blk .Player6;
                } else if (self.energy_level > config.max_energy_level * 0.4) {
                    break :blk .Player5;
                } else if (self.energy_level > config.max_energy_level * 0.3) {
                    break :blk .Player4;
                } else if (self.energy_level > config.max_energy_level * 0.2) {
                    break :blk .Player3;
                } else if (self.energy_level > config.max_energy_level * 0.1) {
                    break :blk .Player2;
                } else {
                    break :blk .Player1;
                }
            },
        };

        // Target
        entities[offset + 1] = .{
            .position = self.target,
            .radius = player_radius,
            .entiy_type = .Target,
        };

        return offset + 2;
    }
};
