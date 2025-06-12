const std = @import("std");
const math = @import("math.zig");
const maze = @import("maze.zig");
const heap = @import("heap.zig");

const AStarElem = struct {
    value: usize,
    location: math.Vec2(usize),
    heap: heap.IntrusiveHeapField(@This()),
};

const Heap = heap.IntrusiveHeap(AStarElem, void, struct {
    pub fn less(ctx: void, a: *AStarElem, b: *AStarElem) bool {
        _ = ctx;
        return a.value < b.value;
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

pub fn find(root: ?*AStarElem, v: *const AStarElem) ?*AStarElem {
    const current = root orelse return null;

    if (current.location.equals(v.location)) {
        return current;
    }

    if (find(current.heap.child, v)) |found| {
        return found;
    }

    return find(current.heap.next, v);
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
    var open: Heap = .{ .context = {} };

    var elem: *AStarElem = try arena_allocator.create(AStarElem);
    elem.* = .{
        .value = heuristic(start, target),
        .location = start,
        .heap = .{},
    };
    open.insert(elem);
    try route.put(arena_allocator, start, start);

    while (open.deleteMin()) |e| {
        try closed.put(arena_allocator, e.location, {});
        if (e.location.equals(target)) {
            var path: std.ArrayListUnmanaged(math.Vec2(usize)) = .empty;
            var current = e.location;

            while (!current.equals(route.get(current).?)) {
                try path.append(allocator, current);
                current = route.get(current).?;
            }
            return path;
        }

        const cost = e.value - heuristic(e.location, target);
        const neighbours = environment.getNeighbours(e.location);

        for (neighbours) |null_neighbour| {
            if (null_neighbour == null) continue;
            const neighbour = null_neighbour.?;
            const cost_g = cost + 1;
            const cost_h = heuristic(neighbour, target);
            const total_cost = cost_g + cost_h;

            const found = find(
                open.root,
                &.{ .location = neighbour, .value = 0, .heap = .{} },
            );

            if (found) |f| {
                if (f.value > total_cost) {
                    open.remove(f);
                } else {
                    continue;
                }
            }
            try route.put(arena_allocator, neighbour, e.location);
            elem = try arena_allocator.create(AStarElem);
            elem.* = .{
                .value = total_cost,
                .location = neighbour,
                .heap = .{},
            };
            open.insert(elem);
        }
    }
    std.debug.print("No path found from {any} to {any}\n", .{ start, target });
    return error.NoPathFound;
}
