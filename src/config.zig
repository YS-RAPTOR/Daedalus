const builtins = @import("builtin");

const Config = struct {
    name: []const u8 = "Daedalus",
    window_width: u32 = 1000,
    window_height: u32 = 1000,
    is_debug: bool = builtins.mode == .Debug,
    clear_color: [4]f32 = .{ 0.0, 0.0, 0.0, 1.0 },
    max_entities: u32 = 100,

    // Maze Generation
    maze_size: u32 = 100,
    seed: u64 = 0,
    min_no_of_energy_cells: u32 = 25,
    max_no_of_energy_cells: u32 = 100,

    // Render
    cell_size: u32 = 50,
    min_cell_size: u32 = 9,
    max_cell_size: u32 = 256,
    wall_thickness_percentage: f32 = 0.1,
    player_radius_percentage: f32 = 0.25,
    energy_radius_percentage: f32 = 0.40,

    // Player
    mass: f32 = 1.0,
    friction: f32 = 0.15,
    energy_multiplier: f32 = 0.01,
};

pub const config: Config = .{};
