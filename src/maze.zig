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
    random: random,

    pub fn get_index(self: *@This(), x: usize, y: usize) usize {
        return y * self.size.x + x;
    }

    pub fn init(allocator: std.mem.Allocator, size: math.Vec2(usize), seed: u64) !@This() {
        var cells: std.ArrayListUnmanaged(Cell) = .empty;
        try cells.appendNTimes(allocator, Cell.Walled, size.x * size.y);

        var prng = random.DefaultPrng.init(seed);

        return .{
            .cells = cells,
            .allocator = allocator,
            .size = size,
            .random = prng.random(),
        };
    }

    pub fn eller(self: *@This()) !void {
        var current_set: std.ArrayListUnmanaged(usize) = try .initCapacity(self.allocator, self.size.y);
        defer current_set.deinit(self.allocator);

        for (0..self.size.y) |i| {
            current_set.appendAssumeCapacity(i + 1);
        }
        var next_set: std.ArrayListUnmanaged(usize) = try .initCapacity(self.allocator, self.size.y);
        defer next_set.deinit(self.allocator);

        for (0..self.size.y - 1) |i| {
            next_set.clearRetainingCapacity();
            next_set.appendNTimesAssumeCapacity(0, self.size.y);

            const row_start = self.get_index(0, i);
            const row_end = self.get_index(self.size.x, i);
            const row = self.cells.items[row_start..row_end];

            // Randomly join the sets
            var join_id: usize = current_set.items[0];
            for (row, current_set.items, 0..) |*cell, *id, index| {

                // Stop Joining Process
                if (self.random.boolean()) {
                    id.* = join_id;
                    join_id = current_set.items[@min(index + 1, row.len - 1)];
                    continue;
                }

                id.* = join_id;
                cell.*.east = index == row.len - 1;
            }

            // Print the information

            std.debug.print("|", .{});
            for (current_set.items, row) |id, cell| {
                if (cell.east) {
                    std.debug.print(" {} |", .{id});
                } else {
                    std.debug.print(" {}  ", .{id});
                }
            }
            std.debug.print("\n", .{});
            std.debug.print("\n", .{});

            current_set.clearRetainingCapacity();
            for (0..self.size.y) |j| {
                current_set.appendAssumeCapacity(j + 1);
            }
            // const temp = current_set;
            // current_set = next_set;
            // next_set = temp;
        }
    }

    pub fn deinit(self: *@This()) void {
        self.cells.deinit(self.allocator);
    }
};
