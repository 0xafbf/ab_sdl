
package main

import SDL "vendor:sdl3"
import mui "vendor:microui"

import "core:fmt"

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

	fmt.println("loading rect shaders")
	ui_rect_shader_vert := LoadShader(gpu_device, "Content/Shaders/ui/rect.vert.spv", .VERTEX, 0, 0, 0, 1)
	ui_rect_shader_frag := LoadShader(gpu_device, "Content/Shaders/ui/rect.frag.spv", .FRAGMENT, 0, 0, 0, 1)

	fmt.println("creating pipeline")

	ui_rect_pipeline_info := SDL.GPUGraphicsPipelineCreateInfo {
		vertex_shader = ui_rect_shader_vert,
		fragment_shader = ui_rect_shader_frag,
		primitive_type = .TRIANGLESTRIP,
		target_info = {
			num_color_targets = 1,
			color_target_descriptions = raw_data(color_target_desc),
		}
	}

	window.ui_rect_pipeline = SDL.CreateGPUGraphicsPipeline(gpu_device, ui_rect_pipeline_info)
	defer SDL.ReleaseGPUGraphicsPipeline(gpu_device, window. ui_rect_pipeline)
	fmt.println("release shaders")

	SDL.ReleaseGPUShader(gpu_device, ui_rect_shader_vert)
	SDL.ReleaseGPUShader(gpu_device, ui_rect_shader_frag)

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
		}
		mui.end(window.mui_ctx)



		render_pass := SDL.BeginGPURenderPass(cmd_buf, &color_target_info, 1, nil)
		SDL.BindGPUGraphicsPipeline(render_pass, pipeline)
		SDL.DrawGPUPrimitives(render_pass, 3, 1, 0, 0)

		draw_mui(&window, cmd_buf, render_pass)


		SDL.EndGPURenderPass(render_pass)
		submit_result := SDL.SubmitGPUCommandBuffer(cmd_buf)

	}

}

WindowData :: struct {
	mui_ctx: ^mui.Context,
	size: [2]i32,
	ui_rect_pipeline: ^SDL.GPUGraphicsPipeline,
}

draw_mui :: proc(window: ^WindowData, cmd_buf: ^SDL.GPUCommandBuffer, render_pass: ^SDL.GPURenderPass) {

	mui_ctx: ^mui.Context = window.mui_ctx
	mui_cmd: ^mui.Command

	for mui.next_command(mui_ctx, &mui_cmd) {
		#partial switch e in mui_cmd.variant {
		case ^mui.Command_Jump: fmt.println("Command_Jump")
		case ^mui.Command_Clip: fmt.println("Command_Clip")
		case ^mui.Command_Rect: 
			rect := &e.rect
			VertexUniformData :: struct {
				vp_size: [4]f32,
				rect: [4]f32,
			}
			vert_uniform_data := VertexUniformData {
				vp_size = {f32 (window.size.x), f32 (window.size.y), 0, 0},
				rect = {f32(rect.x), f32(rect.y), f32(rect.w), f32(rect.h)},
			}
			SDL.PushGPUVertexUniformData(cmd_buf, 0, &vert_uniform_data, size_of(vert_uniform_data))
			
			color := &e.color
			frag_color := [4]f32 {f32(color.r)/255, f32(color.g)/255, f32(color.b)/255, f32(color.a) / 255}
			SDL.PushGPUFragmentUniformData(cmd_buf, 0, &frag_color, size_of(frag_color))

			SDL.BindGPUGraphicsPipeline(render_pass, window.ui_rect_pipeline)
			SDL.DrawGPUPrimitives(render_pass, 4, 1, 0, 0)
		// case ^mui.Command_Text: fmt.println("Command_Text")
		case ^mui.Command_Icon:

			rect := &e.rect
			VertexUniformData :: struct {
				vp_size: [4]f32,
				rect: [4]f32,
			}
			vert_uniform_data := VertexUniformData {
				vp_size = {f32 (window.size.x), f32 (window.size.y), 0, 0},
				rect = {f32(rect.x), f32(rect.y), f32(rect.w), f32(rect.h)},
			}
			SDL.PushGPUVertexUniformData(cmd_buf, 0, &vert_uniform_data, size_of(vert_uniform_data))
			
			color := &e.color
			frag_color := [4]f32 {f32(color.r)/255, f32(color.g)/255, f32(color.b)/255, f32(color.a) / 255}
			SDL.PushGPUFragmentUniformData(cmd_buf, 0, &frag_color, size_of(frag_color))

			SDL.BindGPUGraphicsPipeline(render_pass, window.ui_rect_pipeline)
			SDL.DrawGPUPrimitives(render_pass, 4, 1, 0, 0)
		}
	}
}