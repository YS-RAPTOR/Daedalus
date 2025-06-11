const builtins = @import("builtin");

const Config = struct {
    name: []const u8,
    window_width: u32,
    window_height: u32,
    is_debug: bool,
    clear_color: [4]f32 = .{ 0.0, 0.0, 0.0, 1.0 },
};

pub const config: Config = .{
    .name = "Daedalus",
    .window_width = 1000,
    .window_height = 1000,
    .is_debug = builtins.mode == .Debug,
};
