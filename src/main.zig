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

pub fn loadShader(
    allocator: std.mem.Allocator,
    device: *sdl.SDL_GPUDevice,
    stage: enum(c_uint) {
        vertex = sdl.SDL_GPU_SHADERSTAGE_VERTEX,
        fragment = sdl.SDL_GPU_SHADERSTAGE_FRAGMENT,
    },
    file: []const u8,
    sampler_count: u32,
    uniform_buffer_count: u32,
    storage_buffer_count: u32,
    storage_texture_count: u32,
) !*sdl.SDL_GPUShader {
    const format = sdl.SDL_GPU_SHADERFORMAT_SPIRV;
    const backend_formats = sdl.SDL_GetGPUShaderFormats(device);
    if ((backend_formats & format) == 0) {
        return error.NoSupportedShaderFormat;
    }
    const entrypoint = "main";
    const shader_file = try std.fs.openFileAbsolute(file, .{ .mode = .read_only });
    defer shader_file.close();

    const shader_size = try shader_file.getEndPos();
    const shader_content = try shader_file.readToEndAllocOptions(
        allocator,
        shader_size,
        shader_size,
        @alignOf(u8),
        null,
    );
    defer allocator.free(shader_content);

    const shader_info: sdl.SDL_GPUShaderCreateInfo = .{
        .code = shader_content.ptr,
        .code_size = shader_content.len,
        .entrypoint = entrypoint,
        .format = format,
        .stage = @intFromEnum(stage),
        .num_samplers = sampler_count,
        .num_uniform_buffers = uniform_buffer_count,
        .num_storage_buffers = storage_buffer_count,
        .num_storage_textures = storage_texture_count,
    };

    const gpuShader = sdl.SDL_CreateGPUShader(device, &shader_info);
    return gpuShader orelse try check(false, error.CouldNotCreateShader);
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

    const pipeline = blk: {
        const vertex = try loadShader(
            debug_allocator.allocator(),
            device,
            .vertex,
            shader.vertex,
            0,
            0,
            0,
            0,
        );
        defer sdl.SDL_ReleaseGPUShader(device, vertex);

        const fragment = try loadShader(
            debug_allocator.allocator(),
            device,
            .fragment,
            shader.fragment,
            0,
            0,
            0,
            0,
        );
        defer sdl.SDL_ReleaseGPUShader(device, fragment);

        const pipeline_create_info: sdl.SDL_GPUGraphicsPipelineCreateInfo = .{
            .vertex_shader = vertex,
            .fragment_shader = fragment,
            .primitive_type = sdl.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
            .target_info = .{
                .num_color_targets = color_targets.len,
                .color_target_descriptions = &[color_targets.len]sdl.SDL_GPUColorTargetDescription{
                    .{
                        .format = sdl.SDL_GetGPUSwapchainTextureFormat(
                            device,
                            window,
                        ),
                    },
                },
            },
            .rasterizer_state = .{
                .fill_mode = sdl.SDL_GPU_FILLMODE_FILL,
            },
        };
        break :blk sdl.SDL_CreateGPUGraphicsPipeline(
            device,
            &pipeline_create_info,
        ) orelse try check(false, error.CouldNotCreateGraphicsPipeline);
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
            sdl.SDL_BindGPUGraphicsPipeline(render_pass, pipeline);
            sdl.SDL_DrawGPUPrimitives(
                render_pass,
                3,
                1,
                0,
                0,
            );
        }
        try check(sdl.SDL_SubmitGPUCommandBuffer(command_buffer), error.CouldNotSubmitCommandBuffer);
    }
}
