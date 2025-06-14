const builtins = @import("builtin");

const Config = struct {
    name: []const u8 = "Daedalus",
    window_width: u32 = 1000,
    window_height: u32 = 1000,
    is_debug: bool = builtins.mode == .Debug,
    clear_color: [4]f32 = .{ 0.0, 0.0, 0.0, 1.0 },
    max_entities: u32 = 100,

    // Maze Generation
    seed: u64 = 0,
    maze_size: u32 = 25,
    no_of_doors: u32 = 10,
    permutation_time_period: f32 = 5,
    door_coverage_percentage: f32 = 0.15,

    // Render
    cell_size: u32 = 50,
    min_cell_size: u32 = 9,
    max_cell_size: u32 = 256,
    wall_thickness_percentage: f32 = 0.1,
    player_radius_percentage: f32 = 0.25,
    lever_radius_percentage: f32 = 0.25,

    // Player
    mass: f32 = 0.9,
    friction: f32 = 0.10,
    corner_reached_distance: f32 = 0.4,
    corner_lerp_distance: f32 = 0.5,
    slow_down_distance: f32 = 3,
    slow_down_speed: f32 = 0.5,
};

pub const config: Config = .{};
