const math = @import("math.zig");

pub const Entity = extern struct {
    position: math.Vec2(f32) = .Zero,
    radius: f32 = 0,
    entiy_type: enum(u32) {
        None,
        Player10,
        Player9,
        Player8,
        Player7,
        Player6,
        Player5,
        Player4,
        Player3,
        Player2,
        Player1,
        Target,
    } = .None,
};
