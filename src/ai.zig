const std = @import("std");
const math = @import("math.zig");
const path = @import("path.zig");
const maze = @import("maze.zig");
const config = @import("config.zig").config;
const Entity = @import("entity.zig").Entity;
const limited_maze = @import("limited_maze.zig");
const planner = @import("planner.zig");

pub const AI = struct {
    cell_position: math.Vec2(usize),
    position: math.Vec2(f32),
    velocity: math.Vec2(f32),
    acceleration: math.Vec2(f32),
    force: math.Vec2(f32),

    dead: bool = false,
    win: bool = false,
    target: math.Vec2(f32),
    target_cell: math.Vec2(usize),

    corners: std.ArrayListUnmanaged(path.Corner),
    current_corner: usize,

    sub_target: ?math.Vec2(f32),

    actions: std.ArrayListUnmanaged(planner.Action),
    current_action: ?planner.Action,

    environment: limited_maze.LimitedMaze,

    pub fn init(
        allocator: std.mem.Allocator,
        starting_position_cell: math.Vec2(usize),
        target_position_cell: math.Vec2(usize),
        environment: *maze.Maze,
    ) !@This() {
        const position = starting_position_cell.cast(f32).add(.init(0.5, 0.5));
        const target = target_position_cell.cast(f32).add(.init(0.5, 0.5));

        return .{
            .force = .Zero,
            .acceleration = .Zero,
            .velocity = .Zero,
            .position = position,
            .cell_position = starting_position_cell,

            .target = target,
            .target_cell = target_position_cell,

            .environment = try .init(allocator, environment, target_position_cell),

            .corners = .empty,
            .current_corner = 0,
            .sub_target = null,
            .actions = .empty,
            .current_action = null,
        };
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.corners.deinit(allocator);
        self.environment.deinit();
        self.actions.deinit(allocator);
    }

    pub fn setDirection(self: *@This()) void {
        if (self.current_corner == 0) {
            self.force = self.sub_target.?.subtract(self.position).normalize();
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
            self.force = direction.multiply((config.slow_down_speed - speed) / distance_to_corner);
        } else {
            self.force = direction;
        }

        if (distance_to_corner < config.corner_reached_distance) {
            // Move to the next corner
            self.current_corner -= 1;
        }
    }

    pub fn update(self: *@This(), delta_time: f32, environment: *maze.Maze) !void {
        if (self.dead) {
            return;
        }

        if (self.win) {
            return;
        }

        // Update Environment
        self.cell_position = .{
            .x = @intFromFloat(@trunc(self.position.x)),
            .y = @intFromFloat(@trunc(self.position.y)),
        };
        var should_replan = try self.environment.increaseVisibility(
            environment,
            self.cell_position,
        );
        try self.environment.visitCell(self.cell_position);
        if (try self.environment.flipLever(environment, self.cell_position)) {
            should_replan = true;
        }

        // Check if the action is completed
        if (self.current_action) |current_action| {
            switch (current_action) {
                .GoToTarget => |target| {
                    if (self.cell_position.equals(target)) {
                        self.current_action = self.actions.pop();
                        self.corners.clearRetainingCapacity();
                        self.current_corner = 0;
                        self.sub_target = null;
                    }
                },
                .Explore => {
                    if (self.sub_target) |sub_target| {
                        if (self.cell_position.equals(sub_target.floor().cast(usize))) {
                            self.corners.clearRetainingCapacity();
                            self.current_corner = 0;
                            self.sub_target = null;
                        }
                    }
                },
            }
        }

        // Check if we need to replan
        if (self.current_action == null or should_replan) {
            std.debug.print("Replanning...\n", .{});
            try planner.plan(
                self.environment.allocator,
                &self.environment,
                self.cell_position,
                self.target_cell,
                &self.actions,
            );

            self.corners.clearRetainingCapacity();
            self.current_corner = 0;
            self.sub_target = null;
            self.current_action = self.actions.pop();
        }
        if (self.target_cell.equals(self.cell_position)) {
            self.win = true;
            return;
        }

        // Perform Action
        switch (self.current_action.?) {
            .GoToTarget => |target| {
                if (self.sub_target == null) {
                    self.sub_target = target.cast(f32).add(.init(0.5, 0.5));
                    var path_to_target, _ = try path.aStar(
                        self.environment.allocator,
                        &self.environment,
                        self.cell_position,
                        target,
                        null,
                    );
                    try path_to_target.append(self.environment.allocator, self.cell_position);
                    defer path_to_target.deinit(self.environment.allocator);

                    try path.findCorners(
                        self.environment.allocator,
                        path_to_target.items,
                        &self.corners,
                    );
                    self.current_corner = self.corners.items.len;
                }
            },
            .Explore => {
                if (self.sub_target == null) {
                    var target = self.cell_position;
                    var target_cost: usize = 10_000_000;
                    var p: std.ArrayListUnmanaged(math.Vec2(usize)) = .empty;
                    defer p.deinit(self.environment.allocator);

                    for (self.environment.unexplored.keys()) |unexplored_cell| {
                        var path_to_unexplored, const cost = path.aStar(
                            self.environment.allocator,
                            &self.environment,
                            self.cell_position,
                            unexplored_cell,
                            null,
                        ) catch continue;

                        if (cost < target_cost) {
                            p.deinit(self.environment.allocator);
                            target = unexplored_cell;
                            target_cost = cost;
                            p = path_to_unexplored;
                        } else {
                            path_to_unexplored.deinit(self.environment.allocator);
                        }
                    }

                    try p.append(self.environment.allocator, self.cell_position);
                    try path.findCorners(
                        self.environment.allocator,
                        p.items,
                        &self.corners,
                    );

                    if (self.environment.unexplored.get(target)) |unexplored| {
                        if (unexplored.east) {
                            try self.corners.insert(self.environment.allocator, 0, .{
                                .location = target,
                                .direction = .init(1, 0),
                            });
                        } else if (unexplored.south) {
                            try self.corners.insert(self.environment.allocator, 0, .{
                                .location = target,
                                .direction = .init(0, 1),
                            });
                        } else if (unexplored.west) {
                            try self.corners.insert(self.environment.allocator, 0, .{
                                .location = target,
                                .direction = .init(-1, 0),
                            });
                        } else {
                            try self.corners.insert(self.environment.allocator, 0, .{
                                .location = target,
                                .direction = .init(0, -1),
                            });
                        }
                    }
                    self.current_corner = self.corners.items.len;
                    self.sub_target = target.cast(f32).add(.init(0.5, 0.5));
                }
            },
        }

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
