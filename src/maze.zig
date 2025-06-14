const std = @import("std");
const math = @import("math.zig");
const random = std.Random;
const config = @import("config.zig").config;

pub const Cell = packed struct(u8) {
    south: bool,
    east: bool,
    lever: bool,
    south_door: bool,
    east_door: bool,
    path: bool,
    corner: bool,
    explored: bool,

    pub const Open: @This() = .{
        .south = false,
        .east = false,
        .lever = false,
        .south_door = false,
        .east_door = false,
        .path = false,
        .corner = false,
        .explored = false,
    };

    pub const Walled: @This() = .{
        .south = true,
        .east = true,
        .lever = false,
        .south_door = false,
        .east_door = false,
        .path = false,
        .corner = false,
        .explored = false,
    };
};

pub const Maze = struct {
    cells: []Cell,
    size: math.Vec2(usize),
    rng: random.Xoshiro256,
    levers_to_doors: std.AutoArrayHashMapUnmanaged(math.Vec2(usize), math.Vec2(usize)),
    doors_to_levers: std.AutoArrayHashMapUnmanaged(math.Vec2(usize), math.Vec2(usize)),
    randomizable_doors: std.ArrayListUnmanaged(usize),
    duration: f32,

    pub fn getIndex(self: *@This(), x: usize, y: usize) usize {
        return y * self.size.x + x;
    }

    pub fn init(allocator: std.mem.Allocator, seed: u64, size: math.Vec2(usize)) !@This() {
        const cells = try allocator.alloc(Cell, size.x * size.y);
        @memset(cells, Cell.Walled);
        var self: @This() = .{
            .cells = cells,
            .size = size,
            .rng = random.DefaultPrng.init(seed),
            .levers_to_doors = .empty,
            .doors_to_levers = .empty,
            .randomizable_doors = try .initCapacity(allocator, size.x * size.y),
            .duration = 0.0,
        };

        try self.eller(allocator);
        try self.initDoorsAndLevers(allocator);
        self.randomizeDoors();
        return self;
    }

    pub fn randomizeDoors(self: *@This()) void {
        for (self.randomizable_doors.items) |door_index| {
            // Random chance to open the door
            const closed = self.rng.random().boolean();
            if (self.cells[door_index].south_door) {
                self.cells[door_index].south = closed;
            } else if (self.cells[door_index].east_door) {
                self.cells[door_index].east = closed;
            } else {
                unreachable; // Should not happen
            }
        }
    }

    pub fn initDoorsAndLevers(self: *@This(), allocator: std.mem.Allocator) !void {
        const visited: []u8 = try allocator.alloc(u8, self.size.x * self.size.y);
        defer allocator.free(visited);

        const size_float = self.size.cast(f32);
        const minimum_coverage: usize = @intFromFloat(config.door_coverage_percentage * size_float.x * size_float.y);
        const maximum_coverage: usize = (self.size.x * self.size.y) - minimum_coverage;

        var doors_created: usize = 0;
        while (true) {
            if (doors_created >= config.no_of_doors) {
                break; // Stop when we have created enough doors
            }

            const door_location: math.Vec2(usize) = .init(
                self.rng.random().uintLessThan(usize, self.size.x),
                self.rng.random().uintLessThan(usize, self.size.y),
            );

            // No doors at the edges
            if (door_location.x == 0 or door_location.x == self.size.x - 1 or
                door_location.y == 0 or door_location.y == self.size.y - 1)
            {
                continue;
            }

            const door_index = self.getIndex(door_location.x, door_location.y);

            if (self.cells[door_index].south_door or self.cells[door_index].east_door) {
                continue;
            }

            if (self.cells[door_index].south and self.cells[door_index].east) {
                continue; // No door can be placed here if no empty wall is available
            }

            // Place a door at the location and close it
            if (!self.cells[door_index].south and !self.cells[door_index].east) {
                const r = self.rng.random().boolean();
                if (r) {
                    self.cells[door_index].south_door = true;
                    self.cells[door_index].south = true;
                } else {
                    self.cells[door_index].east_door = true;
                    self.cells[door_index].east = true;
                }
            } else if (!self.cells[door_index].south) {
                self.cells[door_index].south_door = true;
                self.cells[door_index].south = true;
            } else if (!self.cells[door_index].east) {
                self.cells[door_index].east_door = true;
                self.cells[door_index].east = true;
            }
            @memset(visited, 0);
            const found_target, const count = self.floodFill(
                door_location,
                1,
                visited,
                .init(0, 0),
                0,
            );

            if (count < minimum_coverage or count > maximum_coverage) {
                if (self.cells[door_index].south_door) {
                    self.cells[door_index].south = false;
                    self.cells[door_index].south_door = false;
                } else if (self.cells[door_index].east_door) {
                    self.cells[door_index].east = false;
                    self.cells[door_index].east_door = false;
                }
                continue; // Not enough coverage, try again
            }
            doors_created += 1;

            const id: u8 = @intFromBool(found_target);

            while (true) {
                const lever_location: math.Vec2(usize) = .init(
                    self.rng.random().uintLessThan(usize, self.size.x),
                    self.rng.random().uintLessThan(usize, self.size.y),
                );
                const lever_index = self.getIndex(lever_location.x, lever_location.y);
                if (visited[lever_index] != id) {
                    continue; // Lever must be placed on the reachable side
                }
                if (self.cells[lever_index].lever) {
                    continue; // Lever already placed here
                }

                try self.levers_to_doors.put(allocator, lever_location, door_location);
                try self.doors_to_levers.put(allocator, door_location, lever_location);
                self.randomizable_doors.appendAssumeCapacity(door_index);
                self.cells[lever_index].lever = true;
                break;
            }

            if (self.cells[door_index].south_door) {
                self.cells[door_index].south = false;
            } else if (self.cells[door_index].east_door) {
                self.cells[door_index].east = false;
            }
        }
    }

    pub fn update(self: *@This(), delta_time: f32) void {
        self.duration += delta_time;
        if (self.duration >= config.permutation_time_period) {
            self.randomizeDoors();
            self.duration = 0.0; // Reset the duration after randomizing doors
        }
    }

    pub fn floodFill(
        self: *@This(),
        start_location: math.Vec2(usize),
        id: u8,
        visited: []u8,
        target: math.Vec2(usize),
        count: usize,
    ) struct { bool, usize } {
        var found_target = start_location.equals(target);
        const index = self.getIndex(start_location.x, start_location.y);

        if (visited[index] == id) {
            return .{ found_target, count }; // Already visited
        }
        visited[index] = id;
        var new_count = count + 1;

        const neighbours = self.getNeighbours(start_location);
        for (neighbours) |null_neighbour| {
            if (null_neighbour) |neighbour| {
                const ft, new_count = self.floodFill(
                    neighbour,
                    id,
                    visited,
                    target,
                    new_count,
                );
                found_target = found_target or ft;
            }
        }
        return .{ found_target, new_count };
    }

    fn extendDown(self: *@This(), id: usize, cells: []Cell, ids: []usize) void {
        const cells_to_extend = self.rng.random().uintAtMost(
            usize,
            cells.len - 1,
        ) + 1;

        for (0..cells_to_extend) |_| {
            const random_index = self.rng.random().uintLessThan(
                usize,
                cells.len,
            );

            cells[random_index].south = false;
            ids[random_index] = id;
        }
    }

    fn join(from_id: usize, to_id: usize, ids: []usize) void {
        for (0..ids.len) |i| {
            if (ids[i] == from_id) {
                ids[i] = to_id;
            }
        }
    }

    pub fn eller(self: *@This(), allocator: std.mem.Allocator) !void {
        var current_set: std.ArrayListUnmanaged(usize) = try .initCapacity(allocator, self.size.x);
        defer current_set.deinit(allocator);

        for (0..self.size.x) |i| {
            current_set.appendAssumeCapacity(i + 1);
        }
        var next_set: std.ArrayListUnmanaged(usize) = try .initCapacity(allocator, self.size.x);
        defer next_set.deinit(allocator);

        for (0..self.size.y) |i| {
            next_set.clearRetainingCapacity();
            next_set.appendNTimesAssumeCapacity(0, self.size.x);

            const row_start = self.getIndex(0, i);
            const row_end = self.getIndex(self.size.x, i);
            const row = self.cells[row_start..row_end];

            // Randomly join the sets
            for (
                current_set.items[0 .. self.size.x - 1],
                current_set.items[1..self.size.x],
                row[0 .. self.size.x - 1],
            ) |
                curr_id,
                next_id,
                *cell,
            | {
                if (curr_id == next_id) {
                    continue;
                }

                // If this is the last row, we need to join the sets
                if (i == self.size.y - 1 or self.rng.random().boolean()) {
                    cell.east = false;
                    @This().join(next_id, curr_id, current_set.items);
                }
            }

            // If this is the last row
            if (i == self.size.y - 1) {
                break;
            }

            // Extend the sets down
            var id_start_index: usize = 0;
            var id_end_index: usize = 0;
            var check_id: usize = current_set.items[0];

            for (current_set.items, 0..) |id, index| {
                if (id == check_id) {
                    continue;
                }

                id_end_index = index;
                self.extendDown(
                    check_id,
                    row[id_start_index..id_end_index],
                    next_set.items[id_start_index..id_end_index],
                );
                id_start_index = index;
                check_id = id;
            }

            self.extendDown(
                current_set.getLast(),
                row[id_start_index..],
                next_set.items[id_start_index..],
            );

            // Unconnected cells get uniqe ids
            var new_id: usize = row_end + 1;
            for (next_set.items) |*id| {
                if (id.* != 0) {
                    continue;
                }

                id.* = new_id;
                new_id += 1;
            }

            const temp = current_set;
            current_set = next_set;
            next_set = temp;
        }
    }

    pub fn getNeighbours(self: *@This(), location: math.Vec2(usize)) [4]?math.Vec2(usize) {
        var result: [4]?math.Vec2(usize) = .{ null, null, null, null };
        const index = self.getIndex(location.x, location.y);
        const cell = self.cells[index];

        if (!cell.east) {
            result[0] = .init(location.x + 1, location.y);
        }

        if (!cell.south) {
            result[1] = .init(location.x, location.y + 1);
        }

        if (location.x > 0) {
            const left: math.Vec2(usize) = .init(location.x - 1, location.y);
            const left_index = self.getIndex(left.x, left.y);
            if (!self.cells[left_index].east) {
                result[2] = left;
            }
        }

        if (location.y > 0) {
            const up: math.Vec2(usize) = .init(location.x, location.y - 1);
            const up_index = self.getIndex(up.x, up.y);
            if (!self.cells[up_index].south) {
                result[3] = up;
            }
        }

        return result;
    }

    pub fn flipLever(self: *@This(), location: math.Vec2(usize)) bool {
        const location_index = self.getIndex(location.x, location.y);

        if (!self.cells[location_index].lever) {
            return false;
        }
        self.cells[location_index].lever = false;
        const door_location = self.levers_to_doors.get(location) orelse unreachable;
        const door_index = self.getIndex(door_location.x, door_location.y);

        if (self.cells[door_index].south_door) {
            self.cells[door_index].south = false;
        } else if (self.cells[door_index].east_door) {
            self.cells[door_index].east = false;
        } else {
            unreachable;
        }
        const index = std.mem.indexOfScalar(usize, self.randomizable_doors.items, door_index) orelse return true;
        _ = self.randomizable_doors.swapRemove(index);
        return true;
    }

    pub fn print(self: *@This()) void {
        std.debug.print("+", .{});
        for (0..self.size.x) |_| {
            std.debug.print("---+", .{});
        }

        for (0..self.size.y) |row| {
            std.debug.print("\n|", .{});
            for (0..self.size.x) |col| {
                const index = self.getIndex(col, row);
                if (self.cells.items[index].east) {
                    std.debug.print("   |", .{});
                } else {
                    std.debug.print("    ", .{});
                }
            }
            std.debug.print("\n+", .{});
            for (0..self.size.x) |col| {
                const index = self.getIndex(col, row);
                if (self.cells.items[index].south) {
                    std.debug.print("---+", .{});
                } else {
                    std.debug.print("   +", .{});
                }
            }
        }
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.cells);
        self.levers_to_doors.deinit(allocator);
        self.doors_to_levers.deinit(allocator);
        self.randomizable_doors.deinit(allocator);
    }
};
