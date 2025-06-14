const std = @import("std");
const sdl = @import("sdl");
const config = @import("config.zig").config;
const shader = @import("shader");
const Maze = @import("maze.zig").Maze;
const Cell = @import("maze.zig").Cell;
const math = @import("math.zig");
const ai = @import("ai.zig");
const Entity = @import("entity.zig").Entity;

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

    maze_buffer: *sdl.SDL_GPUBuffer,
    maze_transfer: *sdl.SDL_GPUTransferBuffer,
    entity_buffer: *sdl.SDL_GPUBuffer,
    entity_transfer: *sdl.SDL_GPUTransferBuffer,

    uniforms: extern struct {
        offset: math.Vec2(f32) = .init(100, 100),
        highlighted_cell: math.Vec2(u32) = .init(0, 0),
        time: f32,
        maze_size: u32,
        cell_size: u32,
        wall_thickness: u32 = 0,
        energy_radius: u32 = 0,
    },

    maze: Maze,
    entities: [config.max_entities]Entity,

    game_data: struct {
        paused: bool = true,
        limited_visibility: bool = false,
        cell_size: f32,
        ai_player: ai.AI,
        drag: struct {
            is_holding_mouse: bool = false,
            held_mouse_position: math.Vec2(f32) = .Zero,
            held_offset: math.Vec2(f32) = .Zero,
        } = .{},
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

        // Create the compute pipeline
        self.pipeline = try self.createPipeline();
        errdefer sdl.SDL_ReleaseGPUComputePipeline(self.device, self.pipeline);

        // Create the output texture
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

        // Setup the uniforms
        self.uniforms = .{
            .time = 0.0,
            .maze_size = config.maze_size,
            .cell_size = config.cell_size,
        };

        self.maze = try Maze.init(
            self.allocator,
            config.seed,
            .{ .x = config.maze_size, .y = config.maze_size },
        );
        try self.maze.eller(self.allocator);
        self.maze.initLocations(config.no_of_doors);
        errdefer self.maze.deinit(self.allocator);

        // Create the maze buffer and transfer buffer
        self.maze_buffer = sdl.SDL_CreateGPUBuffer(
            self.device,
            &.{
                .usage = sdl.SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_READ,
                .size = @as(u32, @intCast(self.maze.cells.items.len)) * @sizeOf(Cell),
            },
        ) orelse try check(false, error.CouldNotCreateMazeBuffer);
        errdefer sdl.SDL_ReleaseGPUBuffer(self.device, self.maze_buffer);

        self.maze_transfer = sdl.SDL_CreateGPUTransferBuffer(self.device, &.{
            .usage = sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
            .size = @as(u32, @intCast(self.maze.cells.items.len)) * @sizeOf(Cell),
        }) orelse try check(false, error.CouldNotCreateMazeTransferBuffer);
        errdefer sdl.SDL_ReleaseGPUTransferBuffer(self.device, self.maze_transfer);

        // Create the entity buffer and transfer buffer
        self.entity_buffer = sdl.SDL_CreateGPUBuffer(
            self.device,
            &.{
                .usage = sdl.SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_READ,
                .size = config.max_entities * @sizeOf(Entity),
            },
        ) orelse try check(false, error.CouldNotCreateEntityBuffer);
        errdefer sdl.SDL_ReleaseGPUBuffer(self.device, self.entity_buffer);

        self.entity_transfer = sdl.SDL_CreateGPUTransferBuffer(self.device, &.{
            .usage = sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
            .size = config.max_entities * @sizeOf(Entity),
        }) orelse try check(false, error.CouldNotCreateEntityTransferBuffer);
        errdefer sdl.SDL_ReleaseGPUTransferBuffer(self.device, self.entity_transfer);

        // Initialize Game Data and Player
        self.game_data = .{
            .cell_size = @floatFromInt(config.cell_size),
            .ai_player = try .init(
                self.allocator,
                .init(0, 0),
                .init(config.maze_size - 1, config.maze_size - 1),
                &self.maze,
            ),
        };

        for (0..config.max_entities) |i| {
            self.entities[i] = .{
                .position = math.Vec2(f32).Zero,
                .radius = 0.0,
                .entiy_type = .None,
            };
        }
        _ = self.game_data.ai_player.submitEntities(
            self.entities[0..config.max_entities],
            0,
            config.cell_size,
        );

        self.last_count = sdl.SDL_GetPerformanceCounter();
        self.frequency = sdl.SDL_GetPerformanceFrequency();

        return self;
    }

    pub fn deinit(self: *@This()) void {
        self.game_data.ai_player.deinit(self.allocator);
        self.maze.deinit(self.allocator);

        sdl.SDL_ReleaseGPUTransferBuffer(self.device, self.maze_transfer);
        sdl.SDL_ReleaseGPUBuffer(self.device, self.maze_buffer);

        sdl.SDL_ReleaseGPUTransferBuffer(self.device, self.entity_transfer);
        sdl.SDL_ReleaseGPUBuffer(self.device, self.entity_buffer);

        sdl.SDL_ReleaseGPUTexture(self.device, self.texture);
        sdl.SDL_ReleaseGPUComputePipeline(self.device, self.pipeline);
        sdl.SDL_DestroyGPUDevice(self.device);
        sdl.SDL_DestroyWindow(self.window);
        sdl.SDL_Quit();
    }

    pub fn run(self: *@This()) !void {
        var event: sdl.SDL_Event = undefined;
        main_loop: while (true) {
            if (self.game_data.ai_player.dead) {
                std.debug.print("AI Player is dead. Exiting...\n", .{});
                break :main_loop;
            }

            if (self.game_data.ai_player.win) {
                std.debug.print("AI Player won! Exiting...\n", .{});
                break :main_loop;
            }

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
                    sdl.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                        // check if the mouse button 1 is pressed
                        if (event.button.button == sdl.SDL_BUTTON_LEFT) {
                            self.handleMouseDrag(true, event.button.x, event.button.y);
                        }
                    },
                    sdl.SDL_EVENT_MOUSE_BUTTON_UP => {
                        // check if the mouse button 1 is released
                        if (event.button.button == sdl.SDL_BUTTON_LEFT) {
                            self.handleMouseDrag(false, event.button.x, event.button.y);
                        }
                    },
                    sdl.SDL_EVENT_MOUSE_MOTION => {
                        // Update held mouse position if dragging
                        if (self.game_data.drag.is_holding_mouse) {
                            self.handleMouseDrag(true, event.motion.x, event.motion.y);
                        }
                    },
                    sdl.SDL_EVENT_MOUSE_WHEEL => {
                        // Check if the mouse wheel is scrolled up or down
                        if (event.wheel.y > 0) {
                            self.handleMouseScroll(true);
                        } else if (event.wheel.y < 0) {
                            self.handleMouseScroll(false);
                        }
                    },
                    else => {},
                }
            }

            try self.update(delta_time);
            try self.render();
        }
    }

    fn handleKeyboardInput(self: *@This(), keycode: u32) void {
        switch (keycode) {
            // sdl.SDLK_W, sdl.SDLK_UP => {
            //     self.game_data.player.force.y = -1.0;
            // },
            // sdl.SDLK_S, sdl.SDLK_DOWN => {
            //     self.game_data.player.force.y = 1.0;
            // },
            // sdl.SDLK_A, sdl.SDLK_LEFT => {
            //     self.game_data.player.force.x = -1.0;
            // },
            // sdl.SDLK_D, sdl.SDLK_RIGHT => {
            //     self.game_data.player.force.x = 1.0;
            // },
            sdl.SDLK_SPACE => {
                // Toggle pause state
                self.game_data.paused = !self.game_data.paused;
            },
            sdl.SDLK_C => {
                // Toggle limited visibility
                self.game_data.limited_visibility = !self.game_data.limited_visibility;
            },
            else => {},
        }
    }
    fn handleMouseDrag(self: *@This(), is_down: bool, x: f32, y: f32) void {
        if (is_down and !self.game_data.drag.is_holding_mouse) {
            self.game_data.drag.is_holding_mouse = true;
            self.game_data.drag.held_mouse_position = .init(x, y);
            self.game_data.drag.held_offset = self.uniforms.offset;
        } else if (is_down) {
            // Update held mouse position
            const current_mouse_position: math.Vec2(f32) = .init(x, y);
            const offset = current_mouse_position.subtract(self.game_data.drag.held_mouse_position);
            self.uniforms.offset = self.game_data.drag.held_offset.add(offset);
        } else {
            self.game_data.drag.is_holding_mouse = false;
        }
    }

    fn handleMouseScroll(self: *@This(), is_up: bool) void {
        // Either scroll towards player or cursor
        const towards = blk: {
            var x: f32 = 0;
            var y: f32 = 0;
            _ = sdl.SDL_GetMouseState(&x, &y);

            break :blk math.Vec2(f32).init(x, y);
        };

        if (self.uniforms.cell_size == config.min_cell_size and !is_up) {
            return; // Do not zoom out if already at minimum size
        } else if (self.uniforms.cell_size == config.max_cell_size and is_up) {
            return; // Do not zoom in if already at maximum size
        }

        const old_cell_size = self.game_data.cell_size;
        if (is_up) {
            self.game_data.cell_size *= 1.1;
        } else {
            self.game_data.cell_size *= 0.9;
        }
        const scale_factor = self.game_data.cell_size / old_cell_size;
        self.uniforms.offset.x = towards.x + (self.uniforms.offset.x - towards.x) * scale_factor;
        self.uniforms.offset.y = towards.y + (self.uniforms.offset.y - towards.y) * scale_factor;
    }

    fn update(self: *@This(), delta_time: f32) !void {
        self.uniforms.time += delta_time;

        self.game_data.cell_size = @min(
            @max(config.min_cell_size, self.game_data.cell_size),
            config.max_cell_size,
        );

        self.uniforms.wall_thickness = @intFromFloat(
            @round(self.game_data.cell_size * config.wall_thickness_percentage),
        );
        self.uniforms.energy_radius = @intFromFloat(
            @round(self.game_data.cell_size * config.lever_radius_percentage),
        );
        self.uniforms.cell_size = @intFromFloat(self.game_data.cell_size);
        self.uniforms.highlighted_cell = self.game_data.ai_player.cell_position.cast(u32);

        if (self.game_data.paused) {
            return;
        }

        try self.game_data.ai_player.update(delta_time, &self.maze);

        const entities = self.entities[0..config.max_entities];
        var offset: usize = 0;
        offset = self.game_data.ai_player.submitEntities(
            entities,
            offset,
            self.game_data.cell_size,
        );
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
            // Copy Pass
            {
                defer self.maze.updated = false;

                // Copy Data to transfer buffer
                if (self.game_data.limited_visibility) {
                    try self.copyToTransferBuffer(
                        self.maze_transfer,
                        @ptrCast(self.game_data.ai_player.environment.cells.items),
                        true,
                    );
                } else {
                    try self.copyToTransferBuffer(
                        self.maze_transfer,
                        @ptrCast(self.maze.cells.items),
                        true,
                    );
                }
                try self.copyToTransferBuffer(
                    self.entity_transfer,
                    @ptrCast(&self.entities),
                    true,
                );

                const copy_pass = sdl.SDL_BeginGPUCopyPass(command_buffer) orelse {
                    try check(false, error.CouldNotBeginCopyPass);
                };
                defer sdl.SDL_EndGPUCopyPass(copy_pass);

                // Copy Data to GPU Buffers
                sdl.SDL_UploadToGPUBuffer(
                    copy_pass,
                    &.{
                        .offset = 0,
                        .transfer_buffer = self.maze_transfer,
                    },
                    &.{
                        .buffer = self.maze_buffer,
                        .size = @as(u32, @intCast(self.maze.cells.items.len)) * @sizeOf(Cell),
                        .offset = 0,
                    },
                    true,
                );
                sdl.SDL_UploadToGPUBuffer(
                    copy_pass,
                    &.{
                        .offset = 0,
                        .transfer_buffer = self.entity_transfer,
                    },
                    &.{
                        .buffer = self.entity_buffer,
                        .size = config.max_entities * @sizeOf(Entity),
                        .offset = 0,
                    },
                    true,
                );
            }

            // Compute Pass
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

                sdl.SDL_BindGPUComputeStorageBuffers(
                    compute_pass,
                    0,
                    &[_]*sdl.SDL_GPUBuffer{ self.maze_buffer, self.entity_buffer },
                    2,
                );

                sdl.SDL_DispatchGPUCompute(
                    compute_pass,
                    config.window_width / 8,
                    config.window_height / 8,
                    1,
                );
            }

            // Render
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

    fn copyToTransferBuffer(
        self: *@This(),
        transfer_buffer: *sdl.SDL_GPUTransferBuffer,
        buffer: []u8,
        cycle: bool,
    ) !void {
        const data = sdl.SDL_MapGPUTransferBuffer(
            self.device,
            transfer_buffer,
            cycle,
        ) orelse try check(false, error.CouldNotMapTransferBuffer);

        var slice: []u8 = undefined;
        slice.ptr = @ptrCast(data);
        slice.len = buffer.len;

        @memcpy(slice, buffer);

        sdl.SDL_UnmapGPUTransferBuffer(self.device, transfer_buffer);
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
            .num_readonly_storage_buffers = 2,
            .threadcount_x = 8,
            .threadcount_y = 8,
            .threadcount_z = 1,
        };

        return sdl.SDL_CreateGPUComputePipeline(self.device, &pipeline_info) orelse {
            try check(false, error.CouldNotCreateComputePipeline);
        };
    }
};
