const std = @import("std");
const math = @import("math.zig");
const maze = @import("limited_maze.zig");

const AStarElem = struct {
    value: usize,
    location: math.Vec2(usize),
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
            const heuristic_a = heuristic(a.location, b.location);
            const heuristic_b = heuristic(b.location, a.location);
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

pub fn heuristic(a: math.Vec2(usize), b: math.Vec2(usize)) usize {
    const x = blk: {
        if (a.x > b.x) {
            break :blk a.x - b.x;
        } else {
            break :blk b.x - a.x;
        }
    };

    const y = blk: {
        if (a.y > b.y) {
            break :blk a.y - b.y;
        } else {
            break :blk b.y - a.y;
        }
    };

    return x + y;
}

pub fn aStar(
    allocator: std.mem.Allocator,
    environment: *maze.LimitedMaze,
    start: math.Vec2(usize),
    target: math.Vec2(usize),
    max_cost: ?usize,
) !struct { std.ArrayListUnmanaged(math.Vec2(usize)), usize } {
    var arena = std.heap.ArenaAllocator.init(allocator);
    const arena_allocator = arena.allocator();
    defer arena.deinit();

    var closed: std.AutoArrayHashMapUnmanaged(math.Vec2(usize), void) = .empty;
    var route: std.AutoArrayHashMapUnmanaged(math.Vec2(usize), math.Vec2(usize)) = .empty;
    var open: Heap = .init(arena_allocator, {});
    try open.add(.{
        .value = heuristic(start, target),
        .location = start,
    });
    try route.put(arena_allocator, start, start);

    while (open.removeOrNull()) |e| {
        try closed.put(arena_allocator, e.location, {});
        const cost = e.value - heuristic(e.location, target);
        if (e.location.equals(target)) {
            var path: std.ArrayListUnmanaged(math.Vec2(usize)) = .empty;
            var current = e.location;

            while (!current.equals(route.get(current).?)) {
                try path.append(allocator, current);
                current = route.get(current).?;
            }
            return .{ path, cost };
        }

        if (max_cost) |mc| {
            if (cost > mc) {
                continue;
            }
        }
        const neighbours = environment.getNeighbours(e.location);

        for (neighbours) |null_neighbour| {
            if (null_neighbour == null) continue;
            const neighbour = null_neighbour.?;
            if (closed.contains(neighbour)) continue;

            const cost_g = cost + environment.movementCost(
                e.location,
                neighbour,
            );
            const cost_h = heuristic(neighbour, target);
            const total_cost = cost_g + cost_h;

            var found: ?AStarElem = null;
            var iter = open.iterator();
            var index: usize = 0;

            while (iter.next()) |f| {
                if (f.location.equals(neighbour)) {
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
            try route.put(arena_allocator, neighbour, e.location);
            try open.add(.{
                .value = total_cost,
                .location = neighbour,
            });
        }
    }
    return error.NoPathFound;
}

pub const Corner = struct {
    direction: math.Vec2(i8),
    location: math.Vec2(usize),
};

pub fn findCorners(allocator: std.mem.Allocator, path: []const math.Vec2(usize), corners: *std.ArrayListUnmanaged(Corner)) !void {
    if (path.len < 2) {
        return;
    }

    var point0: math.Vec2(isize) = path[0].cast(isize);
    var point1: math.Vec2(isize) = path[1].cast(isize);

    var direction: math.Vec2(i8) = point0.subtract(point1).cast(i8);

    for (0..path.len - 1) |i| {
        point0 = path[i].cast(isize);
        point1 = path[i + 1].cast(isize);

        const next_direction: math.Vec2(i8) = point0.subtract(point1).cast(i8);
        if (!direction.equals(next_direction)) {
            // Found a corner
            const corner: Corner = .{
                .direction = direction,
                .location = path[i],
            };

            try corners.append(allocator, corner);
            direction = next_direction;
        }
    }
    return;
}
