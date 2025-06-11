const std = @import("std");
const builtins = @import("builtin");
const sdl = @import("sdl");
const shader = @import("shader");

pub inline fn check(val: bool, err: anytype) !void {
    if (!val) {
        std.debug.print("SDL Error: {s}\n", .{sdl.SDL_GetError()});
        return err;
    }
}

pub fn main() !void {
    // Initialize allocator
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    _, const is_debug = gpa: {
        break :gpa switch (builtins.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    // Initialize SDL
    try check(sdl.SDL_Init(sdl.SDL_INIT_VIDEO), error.CouldNotInitializeSDL);

    // Create a window
    const window = sdl.SDL_CreateWindow(
        "Daedalus",
        800,
        600,
        sdl.SDL_WINDOW_RESIZABLE | sdl.SDL_WINDOW_HIDDEN,
    ) orelse try check(false, error.CouldNotCreateWindow);
    errdefer sdl.SDL_DestroyWindow(window);

    // Create a GPU device
    const device = sdl.SDL_CreateGPUDevice(
        sdl.SDL_GPU_SHADERFORMAT_SPIRV,
        is_debug,
        null,
    ) orelse try check(false, error.CouldNotCreateGPUDevice);
    errdefer sdl.SDL_DestroyGPUDevice(device);

    // Connect the GPU device to the window
    try check(
        sdl.SDL_ClaimWindowForGPUDevice(device, window),
        error.CouldNotClaimWindowForGPUDevice,
    );

    // Show the window
    try check(sdl.SDL_ShowWindow(window), error.CouldNotShowWindow);

    // Color Targets
    var color_targets = [_]sdl.SDL_GPUColorTargetInfo{
        .{
            .clear_color = .{ .r = 1.0, .g = 0.0, .b = 0.0, .a = 1.0 },
            .load_op = sdl.SDL_GPU_LOADOP_CLEAR,
            .store_op = sdl.SDL_GPU_STOREOP_STORE,
        },
    };

    var event: sdl.SDL_Event = undefined;
    main_loop: while (true) {
        while (sdl.SDL_PollEvent(&event)) {
            switch (event.type) {
                sdl.SDL_EVENT_QUIT => break :main_loop,
                else => {},
            }
        }

        const command_buffer = sdl.SDL_AcquireGPUCommandBuffer(device) orelse {
            try check(false, error.CouldNotAcquireCommandBuffer);
        };

        var texture: ?*sdl.SDL_GPUTexture = null;
        try check(sdl.SDL_WaitAndAcquireGPUSwapchainTexture(
            command_buffer,
            window,
            @ptrCast(&texture),
            null,
            null,
        ), error.CouldNotAcquireSwapchainTexture);
        errdefer sdl.SDL_ReleaseGPUTexture(device, texture);

        if (texture) |tex| {
            color_targets[0].texture = tex;
            const render_pass = sdl.SDL_BeginGPURenderPass(
                command_buffer,
                @ptrCast(&color_targets),
                color_targets.len,
                null,
            ) orelse try check(false, error.CouldNotBeginRenderPass);
            defer sdl.SDL_EndGPURenderPass(render_pass);
        }
        try check(sdl.SDL_SubmitGPUCommandBuffer(command_buffer), error.CouldNotSubmitCommandBuffer);
    }
}
