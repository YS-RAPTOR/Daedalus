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

    corners: std.ArrayListUnmanaged(path.Corner),
    current_corner: usize,

    pub fn init(
        allocator: std.mem.Allocator,
        starting_position_cell: math.Vec2(usize),
        target_position_cell: math.Vec2(usize),
        environment: *maze.Maze,
    ) !@This() {
        var path_to_target = try path.aStar(
            allocator,
            environment,
            starting_position_cell,
            target_position_cell,
            null,
        );
        try path_to_target.append(allocator, starting_position_cell);
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

        _ = environment; // Unused variable, but might be used in the future
        self.setDirection();
        self.cell_position = .{
            .x = @intFromFloat(@trunc(self.position.x)),
            .y = @intFromFloat(@trunc(self.position.y)),
        };

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
            .entiy_type = .Player,
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
