pub fn Vec2(T: type) type {
    const type_info = @typeInfo(T);

    const float_type = switch (type_info) {
        .float => T,
        .int => |i| blk: {
            if (i.bits <= 32) {
                break :blk f32;
            } else if (i.bits <= 64) {
                break :blk f64;
            } else {
                @compileError("Vec2 only supports float or int types");
            }
        },
        else => {
            @compileError("Vec2 only supports float or int types");
        },
    };

    return extern struct {
        x: T,
        y: T,

        pub const Zero: @This() = .{
            .x = 0,
            .y = 0,
        };

        pub const One: @This() = .{
            .x = 1,
            .y = 1,
        };

        pub inline fn init(x: T, y: T) @This() {
            return .{
                .x = x,
                .y = y,
            };
        }

        pub inline fn add(self: @This(), other: @This()) @This() {
            return .{
                .x = self.x + other.x,
                .y = self.y + other.y,
            };
        }

        pub inline fn subtract(self: @This(), other: @This()) @This() {
            return .{
                .x = self.x - other.x,
                .y = self.y - other.y,
            };
        }

        pub inline fn multiply(self: @This(), scalar: T) @This() {
            return .{
                .x = self.x * scalar,
                .y = self.y * scalar,
            };
        }

        pub inline fn divide(self: @This(), scalar: float_type) Vec2(float_type) {
            if (type_info == .int) {
                const x: float_type = @floatFromInt(self.x);
                const y: float_type = @floatFromInt(self.y);

                return .{
                    .x = x / scalar,
                    .y = y / scalar,
                };
            }

            return .{
                .x = self.x / scalar,
                .y = self.y / scalar,
            };
        }

        pub inline fn intDivide(self: @This(), scalar: T) @This() {
            if (type_info != .int) {
                @compileError("Vec2 intDivide only supports int types");
            }
            return .{
                .x = self.x / scalar,
                .y = self.y / scalar,
            };
        }

        pub inline fn length(self: @This()) T {
            return (self.x * self.x + self.y * self.y);
        }

        pub inline fn trueLength(self: @This()) float_type {
            return @sqrt(self.length());
        }

        pub inline fn normalize(self: @This()) Vec2(float_type) {
            const len = self.trueLength();
            if (len == 0) {
                return .Zero;
            }
            return self.divide(len);
        }

        pub inline fn dot(self: @This(), other: @This()) T {
            return self.x * other.x + self.y * other.y;
        }

        pub inline fn cross(self: @This(), other: @This()) T {
            return self.x * other.y - self.y * other.x;
        }

        pub inline fn equals(self: @This(), other: @This()) bool {
            return self.x == other.x and self.y == other.y;
        }
    };
}

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
};
