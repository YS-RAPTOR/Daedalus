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
    folks: std.AutoArrayHashMapUnmanaged(math.Vec2(usize), Unexplored),
    size: math.Vec2(usize),

    doors_found: std.AutoArrayHashMapUnmanaged(math.Vec2(usize), void),
    levers_found: std.AutoArrayHashMapUnmanaged(math.Vec2(usize), void),
    allocator: std.mem.Allocator,

    pub fn getIndex(self: *@This(), x: usize, y: usize) usize {
        return y * self.size.x + x;
    }

    pub fn init(allocator: std.mem.Allocator, size: math.Vec2(usize)) !@This() {
        const self: @This() = .{
            .cells = try allocator.alloc(Cell, size.x * size.y),
            .folks = .empty,
            .size = size,
            .doors_found = .empty,
            .levers_found = .empty,
            .allocator = allocator,
        };

        @memset(self.cells, .Walled);
        return self;
    }

    pub fn deinit(self: *@This()) void {
        self.allocator.free(self.cells);
        self.folks.deinit(self.allocator);
        self.doors_found.deinit(self.allocator);
        self.levers_found.deinit(self.allocator);
    }

    pub inline fn getNeighboutInDirection(
        self: *@This(),
        location: math.Vec2(usize),
        direction: Direction,
    ) ?math.Vec2(usize) {
        const index = self.getIndex(location.x, location.y);
        const cell = self.cells.items[index];
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
                    if (!self.cells.items[left_index].east) {
                        return left;
                    }
                }
            },
            .North => {
                if (location.y > 0) {
                    const up: math.Vec2(usize) = .init(location.x, location.y - 1);
                    const up_index = self.getIndex(up.x, up.y);
                    if (!self.cells.items[up_index].south) {
                        return up;
                    }
                }
            },
        }
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
            // TODO: Invalidation code
            const neighbours = environment.getNeighbours(location);

            const index = self.getIndex(location.x, location.y);
            self.cells[index] = environment.cells[index];
            self.cells[index].path = false;
            self.cells[index].corner = false;

            if (self.cells[index].lever) {
                try self.levers_found.put(self.allocator, location, {});
                should_replan = true;
            }
            // TODO: Has error when finding closed doors when facing north and west
            if (self.cells[index].south_door or self.cells[index].east_door) {
                try self.doors_found.put(self.allocator, location, {});
                should_replan = true;
            }

            if (getUnexplored(direction, neighbours)) |unexplored| {
                try self.folks.put(self.allocator, location, unexplored);
                self.cells[index].path = true;
            }

            if (neighbours[@intFromEnum(direction)]) |new| {
                location = new;
            } else {
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

        should_replan = should_replan or try self.increaseVisibilityInDirection(
            environment,
            current_location,
            .East,
        );
        should_replan = should_replan or try self.increaseVisibilityInDirection(
            environment,
            current_location,
            .South,
        );
        should_replan = should_replan or try self.increaseVisibilityInDirection(
            environment,
            neighbours[2],
            .West,
        );
        should_replan = should_replan or try self.increaseVisibilityInDirection(
            environment,
            neighbours[3],
            .North,
        );
        return should_replan;
    }

    pub fn flipLever(self: *@This(), environment: *maze.Maze, location: math.Vec2(usize)) !void {
        if (!environment.flipLever(location)) {
            return;
        }
        const door_location = environment.levers_to_doors.get(location) orelse unreachable;
        if (self.doors_found.contains(door_location)) {
            const door_index = self.getIndex(door_location.x, door_location.y);

            if (self.cells[door_index].south_door) {
                self.cells[door_index].south = false;
            } else if (self.cells[door_index].east_door) {
                self.cells[door_index].east = false;
            }
        }
        self.cells[self.getIndex(location.x, location.y)].lever = false;
    }
};
