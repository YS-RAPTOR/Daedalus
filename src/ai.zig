const std = @import("std");
const math = @import("math.zig");
const path = @import("path.zig");
const maze = @import("maze.zig");
const config = @import("config.zig").config;
const Entity = @import("entity.zig").Entity;

pub const AI = struct {
    position: math.Vec2(f32),
    velocity: math.Vec2(f32),
    acceleration: math.Vec2(f32),
    force: math.Vec2(f32),

    collisions: *maze.Maze,

    dead: bool = false,
    target: math.Vec2(f32),
    energy_level: f32,

    corners: std.ArrayListUnmanaged(path.Corner),
    current_corner: usize,

    pub fn init(
        allocator: std.mem.Allocator,
        starting_position_cell: math.Vec2(usize),
        target_position_cell: math.Vec2(usize),
        environment: *maze.Maze,
    ) !@This() {
        // TODO: Implement GOAP
        var path_to_target = try path.aStar(
            allocator,
            environment,
            starting_position_cell,
            target_position_cell,
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
            .force = .Zero,
            .acceleration = .Zero,
            .velocity = .Zero,
            .position = position,
            .energy_level = 100,
            .corners = corners,
            .collisions = environment,
            .target = target,
            .current_corner = corners.items.len - 1,
        };
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.corners.deinit(allocator);
    }

    pub fn setDirection(self: *@This()) void {
        if (self.current_corner < 0) {
            return;
        }

        const current_corner = self.corners.items[self.current_corner];
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
            std.debug.print(
                "AI: Lerp direction: {any} to {any} with distance {any}: {}\n",
                .{ direction, current_corner.direction.cast(f32), distance_to_corner, self.velocity },
            );
        } else if (distance_to_corner < config.slow_down_distance and speed > config.slow_down_speed) {
            self.force = direction.multiply(-1);
            std.debug.print(
                "AI: Slow Down: {any} with distance {any}: {}\n",
                .{ self.force, distance_to_corner, self.velocity },
            );
        } else {
            self.force = direction;
            std.debug.print(
                "AI: Set direction: {any} with distance {any}: {}\n",
                .{ direction, distance_to_corner, self.velocity },
            );
        }

        if (distance_to_corner < config.corner_reached_distance) {
            // Move to the next corner
            self.current_corner -= 1;
        }
    }

    pub fn update(self: *@This(), delta_time: f32) void {
        self.setDirection();

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
    }

    pub fn submitEntities(self: *@This(), entities: []Entity, offset: usize, cell_size: f32) usize {
        const player_radius: f32 = cell_size * config.player_radius_percentage;

        // Player
        entities[offset] = .{
            .position = self.position,
            .radius = player_radius,
            .entiy_type = blk: {
                if (self.energy_level > 90) {
                    break :blk .Player10;
                } else if (self.energy_level > 80) {
                    break :blk .Player9;
                } else if (self.energy_level > 70) {
                    break :blk .Player8;
                } else if (self.energy_level > 60) {
                    break :blk .Player7;
                } else if (self.energy_level > 50) {
                    break :blk .Player6;
                } else if (self.energy_level > 40) {
                    break :blk .Player5;
                } else if (self.energy_level > 30) {
                    break :blk .Player4;
                } else if (self.energy_level > 20) {
                    break :blk .Player3;
                } else if (self.energy_level > 10) {
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
