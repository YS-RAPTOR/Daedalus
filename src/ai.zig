const std = @import("std");
const math = @import("math.zig");
const maze = @import("maze.zig");

const AStarElem = struct {
    value: usize,
    location: math.Vec2(usize),
};

const Heap = std.PriorityQueue(AStarElem, void, struct {
    pub fn less(ctx: void, a: AStarElem, b: AStarElem) std.math.Order {
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
}.less);

fn heuristic(a: math.Vec2(usize), b: math.Vec2(usize)) usize {
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
    environment: *maze.Maze,
    start: math.Vec2(usize),
    target: math.Vec2(usize),
) !std.ArrayListUnmanaged(math.Vec2(usize)) {
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
        if (e.location.equals(target)) {
            var path: std.ArrayListUnmanaged(math.Vec2(usize)) = .empty;
            var current = e.location;

            std.debug.print("Path found from {any} to {any}\n", .{ start, target });
            while (!current.equals(route.get(current).?)) {
                try path.append(allocator, current);
                current = route.get(current).?;
            }
            try path.append(allocator, start);
            return path;
        }

        const cost = e.value - heuristic(e.location, target);
        const neighbours = environment.getNeighbours(e.location);

        for (neighbours) |null_neighbour| {
            if (null_neighbour == null) continue;
            const neighbour = null_neighbour.?;
            if (closed.contains(neighbour)) continue;

            const cost_g = cost + 1;
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
    std.debug.print("No path found from {any} to {any}\n", .{ start, target });
    return error.NoPathFound;
}
