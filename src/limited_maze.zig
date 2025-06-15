const config = @import("config.zig").config;
const std = @import("std");
const maze = @import("maze.zig");
const math = @import("math.zig");
const Cell = maze.Cell;

const Unexplored = packed struct(u8) {
    east: bool = false,
    west: bool = false,
    south: bool = false,
    north: bool = false,
    padding: u4 = 0,
};

pub const LimitedMaze = struct {
    cells: []Cell,
    unexplored: std.AutoArrayHashMapUnmanaged(math.Vec2(usize), Unexplored),
    explored: std.AutoArrayHashMapUnmanaged(math.Vec2(usize), void),
    size: math.Vec2(usize),
    target: math.Vec2(usize),

    doors_found: std.AutoArrayHashMapUnmanaged(math.Vec2(usize), void),
    levers_found: std.AutoArrayHashMapUnmanaged(math.Vec2(usize), void),

    doors_to_levers: std.AutoArrayHashMapUnmanaged(math.Vec2(usize), math.Vec2(usize)),
    levers_to_doors: std.AutoArrayHashMapUnmanaged(math.Vec2(usize), math.Vec2(usize)),

    allocator: std.mem.Allocator,

    pub fn getIndex(self: *@This(), x: usize, y: usize) usize {
        return y * self.size.x + x;
    }

    pub fn init(
        allocator: std.mem.Allocator,
        environment: *maze.Maze,
        target: math.Vec2(usize),
    ) !@This() {
        var self: @This() = .{
            .cells = try allocator.alloc(Cell, environment.size.x * environment.size.y),
            .unexplored = .empty,
            .explored = .empty,
            .size = environment.size,
            .doors_found = .empty,
            .levers_found = .empty,
            .doors_to_levers = try environment.doors_to_levers.clone(allocator),
            .levers_to_doors = try environment.levers_to_doors.clone(allocator),
            .allocator = allocator,
            .target = target,
        };
        if (config.has_snapshot_at_start) {
            @memcpy(self.cells, environment.cells);

            for (self.doors_to_levers.keys()) |door| {
                try self.doors_found.put(self.allocator, door, {});
            }

            for (self.levers_to_doors.keys()) |lever| {
                try self.levers_found.put(self.allocator, lever, {});
            }
        } else {
            @memset(self.cells, .Walled);
        }

        return self;
    }

    pub fn deinit(self: *@This()) void {
        self.allocator.free(self.cells);
        self.unexplored.deinit(self.allocator);
        self.explored.deinit(self.allocator);
        self.doors_found.deinit(self.allocator);
        self.levers_found.deinit(self.allocator);
        self.doors_to_levers.deinit(self.allocator);
        self.levers_to_doors.deinit(self.allocator);
    }

    pub inline fn getCellInDirection(
        location: math.Vec2(usize),
        direction: Direction,
    ) ?math.Vec2(usize) {
        switch (direction) {
            .East => {
                return location;
            },
            .South => {
                return location;
            },
            .West => {
                if (location.x > 0) {
                    const left: math.Vec2(usize) = .init(location.x - 1, location.y);
                    return left;
                }
            },
            .North => {
                if (location.y > 0) {
                    const up: math.Vec2(usize) = .init(location.x, location.y - 1);
                    return up;
                }
            },
        }
        return null;
    }

    pub inline fn getNeighboutInDirection(
        self: *@This(),
        location: math.Vec2(usize),
        direction: Direction,
    ) ?math.Vec2(usize) {
        const index = self.getIndex(location.x, location.y);
        const cell = self.cells[index];
        switch (direction) {
            .East => {
                if (!cell.east) return .init(location.x + 1, location.y);
            },
            .South => {
                if (!cell.south) return .init(location.x, location.y + 1);
            },
            .West => {
                if (location.x > 0) {
                    const left: math.Vec2(usize) = .init(location.x - 1, location.y);
                    const left_index = self.getIndex(left.x, left.y);
                    if (!self.cells[left_index].east) {
                        return left;
                    }
                }
            },
            .North => {
                if (location.y > 0) {
                    const up: math.Vec2(usize) = .init(location.x, location.y - 1);
                    const up_index = self.getIndex(up.x, up.y);
                    if (!self.cells[up_index].south) {
                        return up;
                    }
                }
            },
        }
        return null;
    }

    pub fn getNeighbours(self: *@This(), location: math.Vec2(usize)) [4]?math.Vec2(usize) {
        var result: [4]?math.Vec2(usize) = .{ null, null, null, null };
        result[0] = self.getNeighboutInDirection(location, .East);
        result[1] = self.getNeighboutInDirection(location, .South);
        result[2] = self.getNeighboutInDirection(location, .West);
        result[3] = self.getNeighboutInDirection(location, .North);
        return result;
    }

    pub const Direction = enum { East, South, West, North };

    pub fn getUnexplored(
        direction: Direction,
        neighbours: [4]?math.Vec2(usize),
    ) ?Unexplored {
        var unexplored: Unexplored = .{
            .east = false,
            .west = false,
            .south = false,
            .north = false,
        };
        var number_of_unexplored: usize = 0;

        if (neighbours[0]) |_| {
            if (direction == .North or direction == .South) {
                number_of_unexplored += 1;
                unexplored.east = true;
            }
        }

        if (neighbours[1]) |_| {
            if (direction == .East or direction == .West) {
                number_of_unexplored += 1;
                unexplored.south = true;
            }
        }

        if (neighbours[2]) |_| {
            if (direction == .North or direction == .South) {
                number_of_unexplored += 1;
                unexplored.west = true;
            }
        }

        if (neighbours[3]) |_| {
            if (direction == .East or direction == .West) {
                number_of_unexplored += 1;
                unexplored.north = true;
            }
        }
        std.debug.assert(number_of_unexplored < 3);
        if (number_of_unexplored == 0) {
            return null;
        }
        return unexplored;
    }

    fn increaseVisibilityInDirection(
        self: *@This(),
        environment: *maze.Maze,
        dir_location: ?math.Vec2(usize),
        direction: Direction,
    ) !bool {
        var location: math.Vec2(usize) = dir_location orelse return false;
        var should_replan = false;
        while (true) {
            // NOTE: Replan triggered in these conditions:
            //      Door state changes from previously explored state.
            //      Found a lever.
            //      Found a door.
            //      Found the target.

            const neighbours = environment.getNeighbours(location);

            const index = self.getIndex(location.x, location.y);

            if (!self.cells[index].explored and location.equals(self.target)) {
                should_replan = true;
            }

            if (self.cells[index].explored) {
                if (self.cells[index].south != environment.cells[index].south or
                    self.cells[index].east != environment.cells[index].east)
                {
                    should_replan = true;
                }
            }

            self.cells[index].south = environment.cells[index].south;
            self.cells[index].east = environment.cells[index].east;
            self.cells[index].south_door = environment.cells[index].south_door;
            self.cells[index].east_door = environment.cells[index].east_door;
            self.cells[index].lever = environment.cells[index].lever;
            self.cells[index].explored = true;

            if (self.cells[index].lever) {
                if (!self.levers_found.contains(location)) {
                    try self.levers_found.put(self.allocator, location, {});
                    should_replan = true;
                }
            }

            if (self.cells[index].south_door or self.cells[index].east_door) {
                if (!self.doors_found.contains(location)) {
                    try self.doors_found.put(self.allocator, location, {});
                    should_replan = true;
                }
            }

            if (getUnexplored(direction, neighbours)) |unexplored| {
                if (!self.explored.contains(location) and !self.unexplored.contains(location)) {
                    try self.unexplored.put(self.allocator, location, unexplored);
                    self.cells[index].path = true;
                }
            }

            if (neighbours[@intFromEnum(direction)]) |new| {
                location = new;
            } else {
                if (direction == .North) {
                    const up = getCellInDirection(
                        location,
                        .North,
                    ) orelse break;
                    const up_index = self.getIndex(up.x, up.y);

                    if (self.cells[up_index].explored) {
                        if (self.cells[up_index].south != environment.cells[up_index].south) {
                            should_replan = true;
                        }
                    }
                    self.cells[up_index].south = environment.cells[up_index].south;
                    self.cells[up_index].south_door = environment.cells[up_index].south_door;
                    self.cells[up_index].explored = true;

                    if (self.cells[up_index].south_door) {
                        if (!self.doors_found.contains(up)) {
                            try self.doors_found.put(self.allocator, up, {});
                            should_replan = true;
                        }
                    }
                } else if (direction == .West) {
                    const left = getCellInDirection(
                        location,
                        .West,
                    ) orelse break;
                    const left_index = self.getIndex(left.x, left.y);

                    if (self.cells[left_index].explored) {
                        if (self.cells[left_index].east != environment.cells[left_index].east) {
                            should_replan = true;
                        }
                    }

                    self.cells[left_index].east = environment.cells[left_index].east;
                    self.cells[left_index].east_door = environment.cells[left_index].east_door;
                    self.cells[left_index].explored = true;

                    if (self.cells[left_index].east_door) {
                        if (!self.doors_found.contains(left)) {
                            try self.doors_found.put(self.allocator, left, {});
                            should_replan = true;
                        }
                    }
                }
                break;
            }
        }
        return should_replan;
    }

    pub fn increaseVisibility(
        self: *@This(),
        environment: *maze.Maze,
        current_location: math.Vec2(usize),
    ) !bool {
        const neighbours = environment.getNeighbours(current_location);
        var should_replan: bool = false;

        if (try self.increaseVisibilityInDirection(
            environment,
            current_location,
            .East,
        )) should_replan = true;
        if (try self.increaseVisibilityInDirection(
            environment,
            current_location,
            .South,
        )) should_replan = true;

        if (try self.increaseVisibilityInDirection(
            environment,
            neighbours[2],
            .West,
        )) should_replan = true;

        if (try self.increaseVisibilityInDirection(
            environment,
            neighbours[3],
            .North,
        )) should_replan = true;
        return should_replan;
    }

    pub fn flipLever(self: *@This(), environment: *maze.Maze, location: math.Vec2(usize)) !bool {
        if (!environment.flipLever(location)) {
            return false;
        }
        var known_door_removed = false;
        const door_location = environment.levers_to_doors.get(location) orelse unreachable;
        if (self.doors_found.contains(door_location)) {
            const door_index = self.getIndex(door_location.x, door_location.y);
            known_door_removed = true;
            if (self.cells[door_index].south_door) {
                self.cells[door_index].south = false;
                self.cells[door_index].south_door = false;
            } else if (self.cells[door_index].east_door) {
                self.cells[door_index].east = false;
                self.cells[door_index].east_door = false;
            }
            _ = self.doors_found.swapRemove(door_location);

            try self.unexplored.put(self.allocator, door_location, .{});
            self.cells[door_index].path = true;
        }
        self.cells[self.getIndex(location.x, location.y)].lever = false;
        _ = self.levers_found.swapRemove(location);

        return known_door_removed;
    }

    pub fn visitCell(self: *@This(), location: math.Vec2(usize)) !void {
        const index = self.getIndex(location.x, location.y);
        self.cells[index].path = false;
        self.cells[index].corner = false;
        const explored = self.unexplored.fetchSwapRemove(location) orelse return;
        try self.explored.put(self.allocator, explored.key, {});
    }

    pub inline fn convert(self: *@This()) maze.Maze {
        return .{
            .cells = self.cells,
            .size = self.size,
            .rng = undefined,
            .doors_to_levers = self.doors_to_levers,
            .levers_to_doors = self.levers_to_doors,
            .randomizable_doors = .empty,
            .duration = 0,
        };
    }
};
