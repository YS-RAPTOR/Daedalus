const builtins = @import("builtin");

const Config = struct {
    name: []const u8 = "Daedalus",
    window_width: u32 = 1000,
    window_height: u32 = 1000,
    is_debug: bool = builtins.mode == .Debug,
    clear_color: [4]f32 = .{ 0.0, 0.0, 0.0, 1.0 },
    max_entities: u32 = 100,

    // Maze Generation
    maze_size: u32 = 50,
    seed: u64 = 0,
    no_of_energy_cells: u32 = 100,

    // Render
    cell_size: u32 = 50,
    min_cell_size: u32 = 9,
    max_cell_size: u32 = 256,
    wall_thickness_percentage: f32 = 0.1,
    player_radius_percentage: f32 = 0.25,
    energy_radius_percentage: f32 = 0.25,

    // Player
    mass: f32 = 0.9,
    friction: f32 = 0.10,
    max_energy_level: f32 = 100.0,
    energy_multiplier: f32 = 0.05,
    energy_mistake_multiplier: f32 = 0.015,
    corner_reached_distance: f32 = 0.4,
    corner_lerp_distance: f32 = 0.5,
    slow_down_distance: f32 = 3,
    slow_down_speed: f32 = 0.5,
};

// CONFIGURATION 1:
// energy_multiplier = 0.01
// no_of_energy_cells = 20
// max_energy_level = 100
//
// CONFIGURATION 2:
// energy_multiplier = 0.05
// no_of_energy_cells = 50
// max_energy_level = 100

pub const config: Config = .{};
