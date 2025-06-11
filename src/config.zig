const builtins = @import("builtin");

const Config = struct {
    name: []const u8,
    staring_window_width: u32,
    staring_window_height: u32,
    is_debug: bool,
    clear_color: [4]f32 = .{ 0.0, 0.0, 0.0, 1.0 },
};

pub const config: Config = .{
    .name = "Daedalus",
    .staring_window_width = 800,
    .staring_window_height = 600,
    .is_debug = builtins.mode == .Debug,
};
