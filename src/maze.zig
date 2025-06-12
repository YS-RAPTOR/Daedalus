const std = @import("std");
const math = @import("math.zig");
const random = std.Random;

pub const Cell = packed struct(u8) {
    south: bool,
    east: bool,
    energy: bool,
    path: bool,
    corner: bool,
    padding: u3 = 0,

    pub const Open: @This() = .{
        .south = false,
        .east = false,
        .energy = false,
        .path = false,
        .corner = false,
    };

    pub const Walled: @This() = .{
        .south = true,
        .east = true,
        .energy = false,
        .path = false,
        .corner = false,
    };
};

pub const Maze = struct {
    cells: std.ArrayListUnmanaged(Cell),
    size: math.Vec2(usize),
    rng: random.Xoshiro256,
    updated: bool = false,

    pub fn getIndex(self: *@This(), x: usize, y: usize) usize {
        return y * self.size.x + x;
    }

    pub fn init(allocator: std.mem.Allocator, seed: u64, size: math.Vec2(usize)) !@This() {
        var cells: std.ArrayListUnmanaged(Cell) = .empty;
        try cells.appendNTimes(allocator, Cell.Walled, size.x * size.y);

        return .{
            .cells = cells,
            .size = size,
            .rng = random.DefaultPrng.init(seed),
        };
    }

    pub fn initLocations(self: *@This(), min_cells: usize, max_cells: usize) void {
        const no_of_cells = self.rng.random().intRangeAtMost(usize, min_cells, max_cells);

        for (0..no_of_cells) |_| {
            const random_index = self.rng.random().uintLessThan(usize, self.size.x * self.size.y);
            self.cells.items[random_index].energy = true;
        }
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
        self.updated = true;
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
            const row = self.cells.items[row_start..row_end];

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
        const cell = self.cells.items[index];

        if (!cell.east) {
            result[0] = .init(location.x + 1, location.y);
        }

        if (!cell.south) {
            result[1] = .init(location.x, location.y + 1);
        }

        if (location.x > 0) {
            const left: math.Vec2(usize) = .init(location.x - 1, location.y);
            const left_index = self.getIndex(left.x, left.y);
            if (!self.cells.items[left_index].east) {
                result[2] = left;
            }
        }

        if (location.y > 0) {
            const up: math.Vec2(usize) = .init(location.x, location.y - 1);
            const up_index = self.getIndex(up.x, up.y);
            if (!self.cells.items[up_index].south) {
                result[3] = up;
            }
        }

        return result;
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
        self.cells.deinit(allocator);
    }
};
