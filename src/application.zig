const std = @import("std");
const sdl = @import("sdl");
const config = @import("config.zig").config;
const shader = @import("shader");

pub inline fn check(val: bool, err: anytype) !void {
    if (!val) {
        std.debug.print("SDL Error: {s}\n", .{sdl.SDL_GetError()});
        return err;
    }
}

pub const Application = struct {
    allocator: std.mem.Allocator,
    window: *sdl.SDL_Window,
    device: *sdl.SDL_GPUDevice,
    last_count: u64,
    frequency: u64,

    pipeline: *sdl.SDL_GPUComputePipeline,
    texture: *sdl.SDL_GPUTexture,
    uniforms: struct {
        time: f32,
    },

    pub fn init(allocator: std.mem.Allocator) !@This() {
        // Initialize SDL
        var self: @This() = undefined;
        self.allocator = allocator;

        try check(sdl.SDL_Init(sdl.SDL_INIT_VIDEO), error.CouldNotInitializeSDL);

        // Create a window
        self.window = sdl.SDL_CreateWindow(
            config.name.ptr,
            config.window_width,
            config.window_height,
            sdl.SDL_WINDOW_HIDDEN,
        ) orelse try check(false, error.CouldNotCreateWindow);
        errdefer sdl.SDL_DestroyWindow(self.window);

        // Create a GPU device
        self.device = sdl.SDL_CreateGPUDevice(
            sdl.SDL_GPU_SHADERFORMAT_SPIRV,
            config.is_debug,
            null,
        ) orelse try check(false, error.CouldNotCreateGPUDevice);
        errdefer sdl.SDL_DestroyGPUDevice(self.device);

        // Connect the GPU device to the window
        try check(
            sdl.SDL_ClaimWindowForGPUDevice(self.device, self.window),
            error.CouldNotClaimWindowForGPUDevice,
        );

        // Show the window
        try check(sdl.SDL_ShowWindow(self.window), error.CouldNotShowWindow);

        self.last_count = sdl.SDL_GetPerformanceCounter();
        self.frequency = sdl.SDL_GetPerformanceFrequency();

        self.pipeline = try self.createPipeline();
        errdefer sdl.SDL_ReleaseGPUComputePipeline(self.device, self.pipeline);

        self.texture = sdl.SDL_CreateGPUTexture(
            self.device,
            &.{
                .format = sdl.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
                .type = sdl.SDL_GPU_TEXTURETYPE_2D,
                .width = config.window_width,
                .height = config.window_height,
                .layer_count_or_depth = 1,
                .num_levels = 1,
                .usage = sdl.SDL_GPU_TEXTUREUSAGE_SAMPLER | sdl.SDL_GPU_TEXTUREUSAGE_COMPUTE_STORAGE_WRITE,
            },
        ) orelse try check(false, error.CouldNotCreateTexture);
        errdefer sdl.SDL_ReleaseGPUTexture(self.device, self.texture);

        self.uniforms = .{ .time = 0.0 };

        return self;
    }

    pub fn deinit(self: *@This()) void {
        sdl.SDL_ReleaseGPUTexture(self.device, self.texture);
        sdl.SDL_ReleaseGPUComputePipeline(self.device, self.pipeline);
        sdl.SDL_DestroyGPUDevice(self.device);
        sdl.SDL_DestroyWindow(self.window);
        sdl.SDL_Quit();
    }

    pub fn run(self: *@This()) !void {
        var event: sdl.SDL_Event = undefined;
        main_loop: while (true) {
            const current_count = sdl.SDL_GetPerformanceCounter();
            const delta_time: f32 = @as(
                f32,
                @floatFromInt(current_count - self.last_count),
            ) / @as(
                f32,
                @floatFromInt(self.frequency),
            );
            self.last_count = current_count;

            while (sdl.SDL_PollEvent(&event)) {
                switch (event.type) {
                    sdl.SDL_EVENT_QUIT => break :main_loop,
                    sdl.SDL_EVENT_KEY_DOWN => {
                        switch (event.key.key) {
                            sdl.SDLK_ESCAPE, sdl.SDLK_Q => {
                                break :main_loop;
                            },
                            else => {
                                self.handleKeyboardInput(event.key.key);
                            },
                        }
                    },
                    else => {},
                }
            }

            self.update(delta_time);
            try self.render();
        }
    }

    fn handleKeyboardInput(self: *@This(), keycode: u32) void {
        _ = self;
        _ = keycode;
    }
    fn handleMouseInput(self: *@This()) void {
        _ = self;
    }

    fn update(self: *@This(), delta_time: f32) void {
        self.uniforms.time += delta_time;
    }

    fn render(self: *@This()) !void {
        const command_buffer = sdl.SDL_AcquireGPUCommandBuffer(self.device) orelse {
            try check(false, error.CouldNotAcquireCommandBuffer);
        };

        var texture: ?*sdl.SDL_GPUTexture = null;
        try check(sdl.SDL_WaitAndAcquireGPUSwapchainTexture(
            command_buffer,
            self.window,
            @ptrCast(&texture),
            null,
            null,
        ), error.CouldNotAcquireSwapchainTexture);
        errdefer sdl.SDL_ReleaseGPUTexture(self.device, texture);

        if (texture) |tex| {
            {
                const texture_bindings = [_]sdl.SDL_GPUStorageTextureReadWriteBinding{
                    .{
                        .texture = self.texture,
                        .cycle = true,
                    },
                };

                const compute_pass = sdl.SDL_BeginGPUComputePass(
                    command_buffer,
                    &texture_bindings,
                    texture_bindings.len,
                    null,
                    0,
                ) orelse try check(false, error.CouldNotBeginComputePass);
                defer sdl.SDL_EndGPUComputePass(compute_pass);

                sdl.SDL_BindGPUComputePipeline(compute_pass, self.pipeline);
                sdl.SDL_PushGPUComputeUniformData(
                    command_buffer,
                    0,
                    &self.uniforms,
                    @sizeOf(@TypeOf(self.uniforms)),
                );
                sdl.SDL_DispatchGPUCompute(
                    compute_pass,
                    config.window_width / 8,
                    config.window_height / 8,
                    1,
                );
            }

            sdl.SDL_BlitGPUTexture(command_buffer, &.{
                .source = .{
                    .texture = self.texture,
                    .w = config.window_width,
                    .h = config.window_height,
                },
                .destination = .{
                    .texture = tex,
                    .w = config.window_width,
                    .h = config.window_height,
                },
                .load_op = sdl.SDL_GPU_LOADOP_DONT_CARE,
                .filter = sdl.SDL_GPU_FILTER_NEAREST,
            });
        }
        try check(sdl.SDL_SubmitGPUCommandBuffer(command_buffer), error.CouldNotSubmitCommandBuffer);
    }

    fn createPipeline(self: *@This()) !*sdl.SDL_GPUComputePipeline {
        const format = sdl.SDL_GPU_SHADERFORMAT_SPIRV;
        const backend_formats = sdl.SDL_GetGPUShaderFormats(self.device);
        if ((backend_formats & format) == 0) {
            return error.NoSupportedShaderFormat;
        }
        const entrypoint = "main";
        const shader_file = try std.fs.openFileAbsolute(shader.compute, .{ .mode = .read_only });
        defer shader_file.close();

        const shader_size = try shader_file.getEndPos();
        const shader_content = try shader_file.readToEndAllocOptions(
            self.allocator,
            shader_size,
            shader_size,
            @alignOf(u8),
            null,
        );
        defer self.allocator.free(shader_content);

        const pipeline_info: sdl.SDL_GPUComputePipelineCreateInfo = .{
            .code = shader_content.ptr,
            .code_size = shader_content.len,
            .entrypoint = entrypoint,
            .format = format,

            .num_readwrite_storage_textures = 1,
            .num_uniform_buffers = 1,
            .threadcount_x = 8,
            .threadcount_y = 8,
            .threadcount_z = 1,
        };

        return sdl.SDL_CreateGPUComputePipeline(self.device, &pipeline_info) orelse {
            try check(false, error.CouldNotCreateComputePipeline);
        };
    }
};
