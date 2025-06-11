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
    color_targets: [1]sdl.SDL_GPUColorTargetInfo,
    pipeline: *sdl.SDL_GPUGraphicsPipeline,
    last_count: u64,
    frequency: u64,

    pub fn init(allocator: std.mem.Allocator) !@This() {
        // Initialize SDL
        var self: @This() = undefined;
        self.allocator = allocator;

        try check(sdl.SDL_Init(sdl.SDL_INIT_VIDEO), error.CouldNotInitializeSDL);

        // Create a window
        self.window = sdl.SDL_CreateWindow(
            config.name.ptr,
            config.staring_window_width,
            config.staring_window_height,
            sdl.SDL_WINDOW_RESIZABLE | sdl.SDL_WINDOW_HIDDEN,
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

        // Color Targets
        self.color_targets = [1]sdl.SDL_GPUColorTargetInfo{
            .{
                .clear_color = .{
                    .r = config.clear_color[0],
                    .g = config.clear_color[1],
                    .b = config.clear_color[2],
                    .a = config.clear_color[3],
                },
                .load_op = sdl.SDL_GPU_LOADOP_CLEAR,
                .store_op = sdl.SDL_GPU_STOREOP_STORE,
            },
        };

        // Create Pipeline
        self.pipeline = try self.createPipeline();
        errdefer sdl.SDL_ReleaseGPUGraphicsPipeline(self.device, self.pipeline);

        self.last_count = sdl.SDL_GetPerformanceCounter();
        self.frequency = sdl.SDL_GetPerformanceFrequency();
        return self;
    }

    pub fn deinit(self: *@This()) void {
        sdl.SDL_ReleaseGPUGraphicsPipeline(self.device, self.pipeline);
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
        _ = self;
        _ = delta_time;
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
            self.color_targets[0].texture = tex;
            const render_pass = sdl.SDL_BeginGPURenderPass(
                command_buffer,
                @ptrCast(&self.color_targets),
                self.color_targets.len,
                null,
            ) orelse try check(false, error.CouldNotBeginRenderPass);
            defer sdl.SDL_EndGPURenderPass(render_pass);
            sdl.SDL_BindGPUGraphicsPipeline(render_pass, self.pipeline);
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

    fn createPipeline(self: *@This()) !*sdl.SDL_GPUGraphicsPipeline {
        const vertex = try self.loadShader(
            .vertex,
            shader.vertex,
            0,
            0,
            0,
            0,
        );
        defer sdl.SDL_ReleaseGPUShader(self.device, vertex);

        const fragment = try self.loadShader(
            .fragment,
            shader.fragment,
            0,
            0,
            0,
            0,
        );
        defer sdl.SDL_ReleaseGPUShader(self.device, fragment);

        const target_info: sdl.SDL_GPUGraphicsPipelineTargetInfo = .{
            .num_color_targets = self.color_targets.len,
            .color_target_descriptions = &[self.color_targets.len]sdl.SDL_GPUColorTargetDescription{
                .{
                    .format = sdl.SDL_GetGPUSwapchainTextureFormat(
                        self.device,
                        self.window,
                    ),
                },
            },
        };
        const pipeline_create_info: sdl.SDL_GPUGraphicsPipelineCreateInfo = .{
            .vertex_shader = vertex,
            .fragment_shader = fragment,
            .primitive_type = sdl.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
            .target_info = target_info,
            .rasterizer_state = .{
                .fill_mode = sdl.SDL_GPU_FILLMODE_FILL,
            },
        };
        return sdl.SDL_CreateGPUGraphicsPipeline(
            self.device,
            &pipeline_create_info,
        ) orelse try check(false, error.CouldNotCreateGraphicsPipeline);
    }

    fn loadShader(
        self: *@This(),
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
        const backend_formats = sdl.SDL_GetGPUShaderFormats(self.device);
        if ((backend_formats & format) == 0) {
            return error.NoSupportedShaderFormat;
        }
        const entrypoint = "main";
        const shader_file = try std.fs.openFileAbsolute(file, .{ .mode = .read_only });
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

        const gpuShader = sdl.SDL_CreateGPUShader(self.device, &shader_info);
        return gpuShader orelse try check(false, error.CouldNotCreateShader);
    }
};
