
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
	window_size := [2] i32 {800, 600}
	window_flags := SDL.WINDOW_VULKAN
	window := SDL.CreateWindow("My App", window_size.x, window_size.y, window_flags);
	if window == nil {
		fmt.println("failed to create window")
		return
	}
	defer SDL.DestroyWindow(window)

	success := SDL.ClaimWindowForGPUDevice(gpu_device, window)
	if !success {
		return
	}
	defer SDL.ReleaseWindowFromGPUDevice(gpu_device, window)

	LoadShader :: proc(gpu_device: ^SDL.GPUDevice, in_path: cstring, in_stage: SDL.GPUShaderStage) -> ^SDL.GPUShader {
		shader_size: uint = ---
		// path_cstr := cstring(in_path)
		shader_code := cast([^]u8) SDL.LoadFile(in_path, &shader_size)
		shader_info := SDL.GPUShaderCreateInfo {
			code_size = shader_size,
			code = shader_code,
			entrypoint = "main",
			format = {.SPIRV},
			stage = in_stage,
			num_samplers = 0,
			num_storage_textures = 0,
			num_storage_buffers = 0,
			num_uniform_buffers = 0,
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
		format = SDL.GetGPUSwapchainTextureFormat(gpu_device, window)
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

	assert(pipeline != nil) 
	SDL.ReleaseGPUShader(gpu_device, shader_vert)
	SDL.ReleaseGPUShader(gpu_device, shader_frag)


	mui_ctx := new(mui.Context)
	mui.init(mui_ctx)

	process_sdl_event :: proc(mui_ctx: ^mui.Context, event: SDL.Event) {
		#partial switch event.type {
		case .MOUSE_MOTION:
			motion := event.motion
			mui.input_mouse_move(mui_ctx, i32(motion.x), i32(motion.y))
		case .MOUSE_BUTTON_DOWN:
			button := event.button
			mui.input_mouse_down(mui_ctx, i32(button.x), i32(button.y), mui.Mouse(button.button))
		case .MOUSE_BUTTON_UP:
			button := event.button
			mui.input_mouse_up(mui_ctx, i32(button.x), i32(button.y), mui.Mouse(button.button))
		case .MOUSE_WHEEL:
			wheel := event.wheel
			fmt.println(wheel.y)
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




	// surface := SDL.GetWindowSurface(window)

	keep_running := true
	for keep_running {
		sdl_event: SDL.Event = ---
		for SDL.PollEvent(&sdl_event) {
			event_type := sdl_event.type
			if sdl_event.type == .QUIT {
				keep_running = false
				continue
			}
			process_sdl_event(mui_ctx, sdl_event)
		}

		cmd_buf := SDL.AcquireGPUCommandBuffer(gpu_device)
		swapchain_tex: ^SDL.GPUTexture
		gotit := SDL.WaitAndAcquireGPUSwapchainTexture(cmd_buf, window, &swapchain_tex, nil, nil)
		assert(gotit)
		assert(swapchain_tex != nil)

		color_target_info := SDL.GPUColorTargetInfo {
			texture = swapchain_tex,
			clear_color = {0, 0, 0, 1},
			load_op = .CLEAR,
			store_op = .STORE,
		}


		render_pass := SDL.BeginGPURenderPass(cmd_buf, &color_target_info, 1, nil)
		SDL.BindGPUGraphicsPipeline(render_pass, pipeline)
		SDL.DrawGPUPrimitives(render_pass, 3, 1, 0, 0)
		SDL.EndGPURenderPass(render_pass)
		submit_result := SDL.SubmitGPUCommandBuffer(cmd_buf)


		mui.begin(mui_ctx)

		mui.end(mui_ctx)

		mui_cmd: ^mui.Command

		for mui.next_command(mui_ctx, &mui_cmd) {
			switch e in mui_cmd.variant {
			case ^mui.Command_Jump: fmt.println("Command_Jump")
			case ^mui.Command_Clip: fmt.println("Command_Clip")
			case ^mui.Command_Rect: fmt.println("Command_Rect")
			case ^mui.Command_Text: fmt.println("Command_Text")
			case ^mui.Command_Icon: fmt.println("Command_Icon")
			}
		}


	}


}