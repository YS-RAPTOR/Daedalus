const std = @import("std");
const sdl = @import("sdl");

pub inline fn check(val: bool, err: anytype) !void {
    if (!val) {
        std.debug.print("SDL Error: {s}\n", .{sdl.SDL_GetError()});
        return err;
    }
}

const Application = struct {
    window: *sdl.SDL_Window,
    renderer: *sdl.SDL_Renderer,
    last_count: u64,
    frequency: u64,

    pub fn init() !@This() {
        try check(sdl.SDL_Init(sdl.SDL_INIT_VIDEO), error.CouldNotInitializeSDL);
        const window = sdl.SDL_CreateWindow(
            "Daedalus",
            800,
            600,
            sdl.SDL_WINDOW_RESIZABLE | sdl.SDL_WINDOW_OPENGL,
        ) orelse try check(false, error.CouldNotCreateWindow);
        const renderer = sdl.SDL_CreateRenderer(window, null) orelse {
            try check(false, error.CouldNotCreateRenderer);
        };

        return .{
            .window = window,
            .renderer = renderer,
            .last_count = sdl.SDL_GetPerformanceCounter(),
            .frequency = sdl.SDL_GetPerformanceFrequency(),
        };
    }

    pub fn run(self: *@This()) !void {
        while (true) {
            const current_count = sdl.SDL_GetPerformanceCounter();
            const delta_time: f32 = @as(
                f32,
                @floatFromInt(current_count - self.last_count),
            ) / @as(
                f32,
                @floatFromInt(self.frequency),
            );
            self.last_count = current_count;

            if (try self.handle_events()) {
                break;
            }

            try self.update(delta_time);
            try self.render();
        }
    }
    pub fn handle_events(self: *@This()) !bool {
        _ = self;

        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event)) {
            switch (event.type) {
                sdl.SDL_EVENT_QUIT => return true,
                sdl.SDL_EVENT_WINDOW_RESIZED => {
                    // Handle window resize
                    const width = event.window.data1;
                    const height = event.window.data2;

                    // TODO: Resize window and height
                    _ = width;
                    _ = height;
                },
                sdl.SDL_EVENT_KEY_DOWN => {
                    switch (event.key.key) {
                        sdl.SDLK_ESCAPE, sdl.SDLK_Q => {
                            return true; // Exit on ESC or Q key press
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }

        return false;
    }

    pub fn update(self: *@This(), delta_time: f32) !void {
        // Update game state here
        _ = self;
        _ = delta_time;
    }

    pub fn render(self: *@This()) !void {
        try check(
            sdl.SDL_SetRenderDrawColor(self.renderer, 0, 0, 0, 255),
            error.CouldNotSetDrawColor,
        );

        try check(
            sdl.SDL_RenderClear(self.renderer),
            error.CouldNotRenderClear,
        );
        // TODO: Render game objects here
        try check(
            sdl.SDL_RenderPresent(self.renderer),
            error.CouldNotRenderPresent,
        );
    }

    pub fn deinit(self: *@This()) void {
        sdl.SDL_DestroyRenderer(self.renderer);
        sdl.SDL_DestroyWindow(self.window);
    }
};

pub fn main() !void {
    var app = try Application.init();
    defer app.deinit();
    try app.run();
}
