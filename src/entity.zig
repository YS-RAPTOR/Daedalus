const math = @import("math.zig");

pub const Entity = extern struct {
    position: math.Vec2(f32) = .Zero,
    radius: f32 = 0,
    entiy_type: enum(u32) {
        None,
        Player,
        Target,
    } = .None,
};
