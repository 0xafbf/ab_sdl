
package main

import SDL "vendor:sdl3"
import mui "vendor:microui"

import "core:fmt"
import "core:mem"

// import "core:runtime"

main :: proc () {
	fmt.println("SDL Init")
	init_success := SDL.Init(SDL.INIT_VIDEO)
	if (!init_success) {
		fmt.println("failed to initialize SDL")
		return
	}

	fmt.println("SDL CreateGPUDevice")
	gpu_device := SDL.CreateGPUDevice({.SPIRV}, true, nil)
	if gpu_device == nil {
		fmt.println("unable to get gpu device")
		return
	}
	defer SDL.DestroyGPUDevice(gpu_device)


	fmt.println("SDL CreateWindow")
	window := WindowData {
		size = {800, 600}
	}

	window_flags := SDL.WindowFlags{.VULKAN, .RESIZABLE}
	sdl_window := SDL.CreateWindow("My App", window.size.x, window.size.y, window_flags);
	if sdl_window == nil {
		fmt.println("failed to create sdl_window")
		return
	}
	defer SDL.DestroyWindow(sdl_window)

	success := SDL.ClaimWindowForGPUDevice(gpu_device, sdl_window)
	if !success {
		return
	}
	defer SDL.ReleaseWindowFromGPUDevice(gpu_device, sdl_window)

	LoadShader :: proc(
		gpu_device: ^SDL.GPUDevice, 
		in_path: cstring, 
		in_stage: SDL.GPUShaderStage, 
		in_num_samplers: u32 = 0, 
		in_num_storage_tex: u32 = 0, 
		in_num_storage_bufs: u32 = 0, 
		in_num_uniform_bufs: u32 = 0,
	) -> ^SDL.GPUShader {
		shader_size: uint = ---
		// path_cstr := cstring(in_path)
		shader_code := cast([^]u8) SDL.LoadFile(in_path, &shader_size)
		shader_info := SDL.GPUShaderCreateInfo {
			code_size = shader_size,
			code = shader_code,
			entrypoint = "main",
			format = {.SPIRV},
			stage = in_stage,
			num_samplers = in_num_samplers,
			num_storage_textures = in_num_storage_tex,
			num_storage_buffers = in_num_storage_bufs,
			num_uniform_buffers = in_num_uniform_bufs,
		}

		shader := SDL.CreateGPUShader(gpu_device, shader_info)
		SDL.free(shader_code)

		return shader
	}
	shader_vert := LoadShader(gpu_device, "Content/Shaders/Compiled/SPIRV/RawTriangle.vert.spv", .VERTEX)
	shader_frag := LoadShader(gpu_device, "Content/Shaders/Compiled/SPIRV/SolidColor.frag.spv", .FRAGMENT)
	assert(shader_vert != nil)
	assert(shader_frag != nil)

	color_target_desc := []SDL.GPUColorTargetDescription{{
		format = SDL.GetGPUSwapchainTextureFormat(gpu_device, sdl_window)
	}}

	pipeline_info := SDL.GPUGraphicsPipelineCreateInfo {
		vertex_shader = shader_vert,
		fragment_shader = shader_frag,
		// vertex_input_state:  GPUVertexInputState,            /**< The vertex layout of the graphics pipeline. */
		primitive_type = .TRIANGLELIST,
		// rasterizer_state:    GPURasterizerState,             /**< The rasterizer state of the graphics pipeline. */
		// multisample_state:   GPUMultisampleState,            /**< The multisample state of the graphics pipeline. */
		// depth_stencil_state: GPUDepthStencilState,           /**< The depth-stencil state of the graphics pipeline. */
		// target_info:         GPUGraphicsPipelineTargetInfo,  /**< Formats and blend modes for the render targets of the graphics pipeline. */
		target_info = {
			num_color_targets = 1,
			color_target_descriptions = raw_data(color_target_desc),
		},
	}

	pipeline_info.rasterizer_state.fill_mode = .FILL 
	// pipeline_info.rasterizer_state.fill_mode = .LINE

	pipeline := SDL.CreateGPUGraphicsPipeline(gpu_device, pipeline_info)
	defer SDL.ReleaseGPUGraphicsPipeline(gpu_device, pipeline)
	assert(pipeline != nil) 
	SDL.ReleaseGPUShader(gpu_device, shader_vert)
	SDL.ReleaseGPUShader(gpu_device, shader_frag)

	ui_rect_shader_vert := LoadShader(gpu_device, "Content/Shaders/ui/rect.vert.spv", .VERTEX, 0, 0, 0, 1)
	ui_rect_shader_frag := LoadShader(gpu_device, "Content/Shaders/ui/rect.frag.spv", .FRAGMENT, 0, 0, 0, 1)

	ui_rect_pipeline_info := SDL.GPUGraphicsPipelineCreateInfo {
		vertex_shader = ui_rect_shader_vert,
		fragment_shader = ui_rect_shader_frag,
		primitive_type = .TRIANGLESTRIP,
		target_info = {
			num_color_targets = 1,
			color_target_descriptions = raw_data(color_target_desc),
		}
	}

	ui_rect_pipeline := SDL.CreateGPUGraphicsPipeline(gpu_device, ui_rect_pipeline_info)
	defer SDL.ReleaseGPUGraphicsPipeline(gpu_device, ui_rect_pipeline)

	SDL.ReleaseGPUShader(gpu_device, ui_rect_shader_vert)
	SDL.ReleaseGPUShader(gpu_device, ui_rect_shader_frag)



	ui_rect_tex_shader_vert := LoadShader(gpu_device, "Content/Shaders/ui/rect_tex.vert.spv", .VERTEX, 0, 0, 0, 1)
	ui_rect_tex_shader_frag := LoadShader(gpu_device, "Content/Shaders/ui/rect_tex.frag.spv", .FRAGMENT, 1, 0, 0, 1)

	color_target_desc_tex := []SDL.GPUColorTargetDescription{{
		format = SDL.GetGPUSwapchainTextureFormat(gpu_device, sdl_window),
		blend_state = {
			src_color_blendfactor = .SRC_ALPHA,
			dst_color_blendfactor = .ONE_MINUS_SRC_ALPHA,
			color_blend_op = .ADD,
			src_alpha_blendfactor = .SRC_ALPHA,
			dst_alpha_blendfactor = .ONE_MINUS_SRC_ALPHA,
			alpha_blend_op = .ADD,
			enable_blend = true,
		}
	}}

	ui_rect_tex_pipeline_info := SDL.GPUGraphicsPipelineCreateInfo {
		vertex_shader = ui_rect_tex_shader_vert,
		fragment_shader = ui_rect_tex_shader_frag,
		primitive_type = .TRIANGLESTRIP,
		target_info = {
			num_color_targets = 1,
			color_target_descriptions = raw_data(color_target_desc_tex),
		}
	}

	ui_rect_tex_pipeline := SDL.CreateGPUGraphicsPipeline(gpu_device, ui_rect_tex_pipeline_info)
	defer SDL.ReleaseGPUGraphicsPipeline(gpu_device, ui_rect_tex_pipeline)
	fmt.println("release shaders")

	SDL.ReleaseGPUShader(gpu_device, ui_rect_tex_shader_vert)
	SDL.ReleaseGPUShader(gpu_device, ui_rect_tex_shader_frag)

// GPUTextureCreateInfo :: struct {
// 	type:                 GPUTextureType,        /**< The base dimensionality of the texture. */
// 	format:               GPUTextureFormat,      /**< The pixel format of the texture. */
// 	usage:                GPUTextureUsageFlags,  /**< How the texture is intended to be used by the client. */
// 	width:                Uint32,                /**< The width of the texture. */
// 	height:               Uint32,                /**< The height of the texture. */
// 	layer_count_or_depth: Uint32,                /**< The layer count or depth of the texture. This value is treated as a layer count on 2D array textures, and as a depth value on 3D textures. */
// 	num_levels:           Uint32,                /**< The number of mip levels in the texture. */
// 	sample_count:         GPUSampleCount,        /**< The number of samples per texel. Only applies if the texture is used as a render target. */

// 	props:                PropertiesID,          /**< A properties ID for extensions. Should be 0 if no extensions are needed. */
// }

	ui_texture := SDL.CreateGPUTexture(gpu_device, SDL.GPUTextureCreateInfo{
		type = .D2,
		format = .A8_UNORM,
		usage = {.SAMPLER},
		width = mui.DEFAULT_ATLAS_WIDTH,
		height = mui.DEFAULT_ATLAS_HEIGHT,
		layer_count_or_depth = 1,
		num_levels = 1,
	})
	defer SDL.ReleaseGPUTexture(gpu_device, ui_texture)

	ui_sampler := SDL.CreateGPUSampler(gpu_device, SDL.GPUSamplerCreateInfo{
	})
	defer SDL.ReleaseGPUSampler(gpu_device, ui_sampler)

	ui_sampler_binding := SDL.GPUTextureSamplerBinding {
		texture = ui_texture,
		sampler = ui_sampler,
	}

	buffer_size: int = mui.DEFAULT_ATLAS_WIDTH * mui.DEFAULT_ATLAS_HEIGHT
	transfer_buffer := SDL.CreateGPUTransferBuffer(gpu_device, SDL.GPUTransferBufferCreateInfo{
		usage = .UPLOAD,
		size = u32(buffer_size),
	})
	defer SDL.ReleaseGPUTransferBuffer(gpu_device, transfer_buffer)

	transfer_buffer_mem := SDL.MapGPUTransferBuffer(gpu_device, transfer_buffer, false)
	mem.copy_non_overlapping(transfer_buffer_mem, &mui.default_atlas_alpha[0], buffer_size);
	SDL.UnmapGPUTransferBuffer(gpu_device, transfer_buffer)

	uploaded := false


	window.mui_ctx = new(mui.Context)
	mui.init(window.mui_ctx)
	window.mui_ctx.text_width = mui.default_atlas_text_width
	window.mui_ctx.text_height = mui.default_atlas_text_height

	sdl_to_microui_btn :: proc(sdl_button: u8) -> mui.Mouse {
		switch sdl_button {
			case 1: return mui.Mouse.LEFT
			case 2: return mui.Mouse.MIDDLE
			case 3: return mui.Mouse.RIGHT
			case: return mui.Mouse(4)
		}
	}

	process_sdl_event :: proc(mui_ctx: ^mui.Context, event: SDL.Event) {
		#partial switch event.type {
		case .MOUSE_MOTION:
			motion := event.motion
			mui.input_mouse_move(mui_ctx, i32(motion.x), i32(motion.y))
		case .MOUSE_BUTTON_DOWN:
			button := event.button
			mui.input_mouse_down(mui_ctx, i32(button.x), i32(button.y), sdl_to_microui_btn(button.button))
		case .MOUSE_BUTTON_UP:
			button := event.button
			mui.input_mouse_up(mui_ctx, i32(button.x), i32(button.y), sdl_to_microui_btn(button.button))
		case .MOUSE_WHEEL:
			wheel := event.wheel
			mui.input_scroll(mui_ctx, i32(wheel.x), i32(wheel.y))
		case .KEY_DOWN:
			key := event.key
			switch key.key {
				case SDL.K_LCTRL: mui.input_key_down(mui_ctx, .CTRL)
				case SDL.K_LSHIFT: mui.input_key_down(mui_ctx, .SHIFT)
				case SDL.K_LALT: mui.input_key_down(mui_ctx, .ALT)
				case SDL.K_RETURN: mui.input_key_down(mui_ctx, .RETURN)
				case SDL.K_DELETE: mui.input_key_down(mui_ctx, .DELETE)
				case SDL.K_BACKSPACE: mui.input_key_down(mui_ctx, .BACKSPACE)
				case SDL.K_LEFT: mui.input_key_down(mui_ctx, .LEFT)
				case SDL.K_RIGHT: mui.input_key_down(mui_ctx, .RIGHT)
				case SDL.K_HOME: mui.input_key_down(mui_ctx, .HOME)
				case SDL.K_END: mui.input_key_down(mui_ctx, .END)
				case 'A': mui.input_key_down(mui_ctx, .A)
				case 'X': mui.input_key_down(mui_ctx, .X)
				case 'C': mui.input_key_down(mui_ctx, .C)
				case 'V': mui.input_key_down(mui_ctx, .V)
			}
		case .KEY_UP:
			key := event.key
			switch key.key {
				case SDL.K_LCTRL: mui.input_key_up(mui_ctx, .CTRL)
				case SDL.K_LSHIFT: mui.input_key_up(mui_ctx, .SHIFT)
				case SDL.K_LALT: mui.input_key_up(mui_ctx, .ALT)
				case SDL.K_RETURN: mui.input_key_up(mui_ctx, .RETURN)
				case SDL.K_DELETE: mui.input_key_up(mui_ctx, .DELETE)
				case SDL.K_BACKSPACE: mui.input_key_up(mui_ctx, .BACKSPACE)
				case SDL.K_LEFT: mui.input_key_up(mui_ctx, .LEFT)
				case SDL.K_RIGHT: mui.input_key_up(mui_ctx, .RIGHT)
				case SDL.K_HOME: mui.input_key_up(mui_ctx, .HOME)
				case SDL.K_END: mui.input_key_up(mui_ctx, .END)
				case 'A': mui.input_key_up(mui_ctx, .A)
				case 'X': mui.input_key_up(mui_ctx, .X)
				case 'C': mui.input_key_up(mui_ctx, .C)
				case 'V': mui.input_key_up(mui_ctx, .V)
			}
		case:
			fmt.println(event.type)
		}
	}


	t: f64 = 0
	dt: f64 = 0
	last_ticks: u64 = SDL.GetTicksNS()
	// surface := SDL.GetWindowSurface(window)

	bool_value: bool = false
	my_color := [4]f32{1, 0.5, 0.2, 1}
	keep_running := true
	for keep_running {
		sdl_event: SDL.Event = ---
		for SDL.PollEvent(&sdl_event) {
			event_type := sdl_event.type
			if sdl_event.type == .QUIT {
				keep_running = false
				continue
			} else if sdl_event.type == .WINDOW_RESIZED {
				window_event := sdl_event.window
				window.size = {window_event.data1, window_event.data2}
				continue
			}
			process_sdl_event(window.mui_ctx, sdl_event)
		}

		ticks := SDL.GetTicksNS()
		delta_ticks := ticks - last_ticks
		dt = f64(delta_ticks) * 1e-9
		t += dt
		last_ticks = ticks

		cmd_buf := SDL.AcquireGPUCommandBuffer(gpu_device)
		swapchain_tex: ^SDL.GPUTexture
		gotit := SDL.WaitAndAcquireGPUSwapchainTexture(cmd_buf, sdl_window, &swapchain_tex, nil, nil)
		assert(gotit)
		assert(swapchain_tex != nil)

		color_target_info := SDL.GPUColorTargetInfo {
			texture = swapchain_tex,
			clear_color = {0, 0, 0, 1},
			load_op = .CLEAR,
			store_op = .STORE,
		}



		mui.begin(window.mui_ctx)

		if mui.window(window.mui_ctx, "window", {100, 100, 400, 300}) {
			mui.label(window.mui_ctx, "My Label")
			mui.checkbox(window.mui_ctx, "My Checkbox", &bool_value)
			mui.number(window.mui_ctx, &my_color.x, 1.0/255)
		}
		mui.end(window.mui_ctx)


		if !uploaded {
			uploaded = true
			copy_pass := SDL.BeginGPUCopyPass(cmd_buf)
			SDL.UploadToGPUTexture(copy_pass, SDL.GPUTextureTransferInfo {
				transfer_buffer = transfer_buffer,
				pixels_per_row = mui.DEFAULT_ATLAS_WIDTH,
				rows_per_layer = mui.DEFAULT_ATLAS_HEIGHT,
			}, SDL.GPUTextureRegion {
				texture = ui_texture, 
				x = 0, y = 0, 
				w = mui.DEFAULT_ATLAS_WIDTH, h = mui.DEFAULT_ATLAS_HEIGHT, d = 1,
			}, false)
			SDL.EndGPUCopyPass(copy_pass)
		}


		render_pass := SDL.BeginGPURenderPass(cmd_buf, &color_target_info, 1, nil)
		SDL.BindGPUGraphicsPipeline(render_pass, pipeline)
		SDL.DrawGPUPrimitives(render_pass, 3, 1, 0, 0)

		draw_ctx := DrawContext {cmd_buf, render_pass, {ui_sampler_binding}, ui_rect_pipeline, ui_rect_tex_pipeline}
		draw_mui(&window, &draw_ctx)


		SDL.EndGPURenderPass(render_pass)
		submit_result := SDL.SubmitGPUCommandBuffer(cmd_buf)

	}

}

WindowData :: struct {
	mui_ctx: ^mui.Context,
	size: [2]i32,
}

DrawContext :: struct {
	cmd_buf: ^SDL.GPUCommandBuffer,
	render_pass: ^SDL.GPURenderPass,
	sampler_bindings: [1]SDL.GPUTextureSamplerBinding,
	ui_rect_pipeline: ^SDL.GPUGraphicsPipeline,
	ui_rect_tex_pipeline: ^SDL.GPUGraphicsPipeline,
}

draw_mui :: proc(window: ^WindowData, draw_ctx: ^DrawContext) {

	mui_ctx: ^mui.Context = window.mui_ctx
	mui_cmd: ^mui.Command


	VertexUniformData :: struct {
		vp_size: [4]f32,
		rect: [4]f32,
		region: [4]f32
	}

	window_draw_rect :: proc (window: ^WindowData, draw_ctx: ^DrawContext, in_rect: mui.Rect, in_color: mui.Color) {

		rect := [4]f32{f32(in_rect.x), f32(in_rect.y), f32(in_rect.w), f32(in_rect.h)}
		color := [4]f32{f32(in_color.r)/255, f32(in_color.g)/255, f32(in_color.b)/255, f32(in_color.a) / 255}

		vert_uniform_data := VertexUniformData {
			vp_size = {f32 (window.size.x), f32 (window.size.y), 0, 0},
			rect = rect,
		}
		SDL.PushGPUVertexUniformData(draw_ctx.cmd_buf, 0, &vert_uniform_data, size_of(vert_uniform_data))
		
		SDL.PushGPUFragmentUniformData(draw_ctx.cmd_buf, 0, &color, size_of(color))

		SDL.BindGPUGraphicsPipeline(draw_ctx.render_pass, draw_ctx.ui_rect_pipeline)
		SDL.DrawGPUPrimitives(draw_ctx.render_pass, 4, 1, 0, 0)
	}

	
	window_draw_textured_rect :: proc (window: ^WindowData, draw_ctx: ^DrawContext, in_rect: mui.Rect, in_color: mui.Color, atlas_region: mui.Rect) {

		rect := [4]f32{f32(in_rect.x), f32(in_rect.y), f32(in_rect.w), f32(in_rect.h)}
		color := [4]f32{f32(in_color.r)/255, f32(in_color.g)/255, f32(in_color.b)/255, f32(in_color.a) / 255}
		region := [4]f32{f32(atlas_region.x)/128, f32(atlas_region.y)/128, f32(atlas_region.w)/128, f32(atlas_region.h) / 128}
		// region := [4]f32{0, 0, 1, 1}

		vert_uniform_data := VertexUniformData {
			vp_size = {f32 (window.size.x), f32 (window.size.y), 0, 0},
			rect = rect,
			region = region,
		}
		SDL.PushGPUVertexUniformData(draw_ctx.cmd_buf, 0, &vert_uniform_data, size_of(vert_uniform_data))
		
		SDL.PushGPUFragmentUniformData(draw_ctx.cmd_buf, 0, &color, size_of(color))

		SDL.BindGPUGraphicsPipeline(draw_ctx.render_pass, draw_ctx.ui_rect_tex_pipeline)
		SDL.BindGPUFragmentSamplers(draw_ctx.render_pass, 0, &draw_ctx.sampler_bindings[0], len(draw_ctx.sampler_bindings))

		SDL.DrawGPUPrimitives(draw_ctx.render_pass, 4, 1, 0, 0)
	}

	for mui.next_command(mui_ctx, &mui_cmd) {
		switch e in mui_cmd.variant {
		case ^mui.Command_Jump: fmt.println("Command_Jump")
		case ^mui.Command_Clip:
			sdl_rect := SDL.Rect {e.rect.x, e.rect.y, e.rect.w, e.rect.h}
			SDL.SetGPUScissor(draw_ctx.render_pass, sdl_rect)
		case ^mui.Command_Rect: 
			window_draw_rect(window, draw_ctx, e.rect, e.color)
		case ^mui.Command_Icon:
			icon := e.id
			atlas_rect := mui.default_atlas[icon]
			window_draw_textured_rect(window, draw_ctx, e.rect, e.color, atlas_rect)


		case ^mui.Command_Text: 
			// Command_Text :: struct { 
			// 	using command: Command, 
			// 	font:  Font, 
			// 	pos:   Vec2, 
			// 	color: Color, 
			// 	str:   string, /* + string data (VLA) */ 
			// }
			text := e.str
			current_pos := e.pos
			atlas := mui.default_atlas
			for idx in 0 ..< len(text) {
				char := text[idx]
				atlas_rect := atlas[u8(mui.DEFAULT_ATLAS_FONT) + char]
				rect: mui.Rect = {current_pos.x, current_pos.y, atlas_rect.w, atlas_rect.h}
				current_pos.x += atlas_rect.w
				window_draw_textured_rect(window, draw_ctx, rect, e.color, atlas_rect)
			}
		}
	}
}