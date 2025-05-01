const std = @import("std");
const math = @import("math.zig");
const random = std.Random;

pub const Cell = packed struct(u2) {
    south: bool,
    east: bool,

    pub const Open: @This() = .{
        .south = false,
        .east = false,
    };

    pub const Walled: @This() = .{
        .south = true,
        .east = true,
    };
};

pub const Maze = struct {
    cells: std.ArrayListUnmanaged(Cell),
    allocator: std.mem.Allocator,
    size: math.Vec2(usize),
    rng: random.Xoshiro256,

    pub fn get_index(self: *@This(), x: usize, y: usize) usize {
        return y * self.size.x + x;
    }

    pub fn init(allocator: std.mem.Allocator, size: math.Vec2(usize), seed: u64) !@This() {
        var cells: std.ArrayListUnmanaged(Cell) = .empty;
        try cells.appendNTimes(allocator, Cell.Walled, size.x * size.y);

        return .{
            .cells = cells,
            .allocator = allocator,
            .size = size,
            .rng = random.DefaultPrng.init(seed),
        };
    }

    fn run(self: *@This()) void {
        while (true) {
            const cells_to_extend = self.rnf.random().uintAtMost(
                usize,
                3,
            ) + 1;
            std.debug.print("Cells to extend: {}\n", .{cells_to_extend});
            if (cells_to_extend > 1) {
                break;
            }
        }
    }

    fn extend_down(self: *@This(), id: usize, cells: []Cell, ids: []usize) void {
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

    pub fn eller(self: *@This()) !void {
        var current_set: std.ArrayListUnmanaged(usize) = try .initCapacity(self.allocator, self.size.x);
        defer current_set.deinit(self.allocator);

        for (0..self.size.x) |i| {
            current_set.appendAssumeCapacity(i + 1);
        }
        var next_set: std.ArrayListUnmanaged(usize) = try .initCapacity(self.allocator, self.size.x);
        defer next_set.deinit(self.allocator);

        for (0..self.size.y) |i| {
            next_set.clearRetainingCapacity();
            next_set.appendNTimesAssumeCapacity(0, self.size.x);

            const row_start = self.get_index(0, i);
            const row_end = self.get_index(self.size.x, i);
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
                self.extend_down(
                    check_id,
                    row[id_start_index..id_end_index],
                    next_set.items[id_start_index..id_end_index],
                );
                id_start_index = index;
                check_id = id;
            }

            self.extend_down(
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
        self.print();
    }

    pub fn print(self: *@This()) void {
        std.debug.print("+", .{});
        for (0..self.size.x) |_| {
            std.debug.print("---+", .{});
        }

        for (0..self.size.y) |row| {
            std.debug.print("\n|", .{});
            for (0..self.size.x) |col| {
                const index = self.get_index(col, row);
                if (self.cells.items[index].east) {
                    std.debug.print("   |", .{});
                } else {
                    std.debug.print("    ", .{});
                }
            }
            std.debug.print("\n+", .{});
            for (0..self.size.x) |col| {
                const index = self.get_index(col, row);
                if (self.cells.items[index].south) {
                    std.debug.print("---+", .{});
                } else {
                    std.debug.print("   +", .{});
                }
            }
        }
    }

    pub fn deinit(self: *@This()) void {
        self.cells.deinit(self.allocator);
    }
};
