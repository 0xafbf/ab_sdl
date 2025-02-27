
package main

import SDL "vendor:sdl3"
import mui "vendor:microui"
import "vendor:cgltf"

import "core:math"
import "core:math/linalg"
import hlm "core:math/linalg/hlsl"
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

	window_flags := SDL.WindowFlags{.VULKAN, .RESIZABLE}

	window := WindowData {
		size = {800, 600},
	}

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

	window.format = SDL.GetGPUSwapchainTextureFormat(gpu_device, sdl_window)
	ui_load_pipelines(&window, gpu_device)
	defer ui_unload_pipelines(&window, gpu_device)

	shader_vert := LoadShader(gpu_device, "Content/Shaders/Compiled/SPIRV/RawTriangle.vert.spv", .VERTEX)
	shader_frag := LoadShader(gpu_device, "Content/Shaders/Compiled/SPIRV/SolidColor.frag.spv", .FRAGMENT)
	assert(shader_vert != nil)
	assert(shader_frag != nil)

	color_target_desc := []SDL.GPUColorTargetDescription{{
		format = window.format
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


	window.mui_ctx = new(mui.Context)
	mui.init(window.mui_ctx)
	window.mui_ctx.text_width = mui.default_atlas_text_width
	window.mui_ctx.text_height = mui.default_atlas_text_height


	t: f64 = 0
	dt: f64 = 0
	last_ticks: u64 = SDL.GetTicksNS()


	helmet: ^cgltf.data
	result: cgltf.result
	helmet_path :cstring= "Content/sample/damaged_helmet.glb"
	helmet, result = cgltf.parse_file({}, helmet_path)
	assert(result == .success)
	load_result := cgltf.load_buffers({}, helmet, helmet_path)
	assert(load_result == .success)
	defer cgltf.free(helmet)

	positions: []hlm.float3
	texcoords: []hlm.float2

	scene := helmet.scene
	fmt.println("nodes ", len(scene.nodes))
	root := scene.nodes[0]
	root_mesh := root.mesh
	fmt.println("  mesh primitives:", len(root_mesh.primitives))
	for primitive in root_mesh.primitives {
		fmt.println("  primitive type:", primitive.type)
		for attribute in primitive.attributes {
			fmt.println("    attribute type:", attribute.type)
			fmt.println("    attribute data:", attribute.data)
			if attribute.type == .position {
				assert(attribute.data.type == .vec3)
				positions = make([]hlm.float3, attribute.data.count)
				num_floats := cgltf.accessor_unpack_floats(attribute.data, nil, 0)
				assert(num_floats == attribute.data.count * 3)
				num_floats = cgltf.accessor_unpack_floats(attribute.data, &positions[0][0], num_floats)
			} else if attribute.type == .texcoord {
				assert(attribute.data.type == .vec2)
				texcoords = make([]hlm.float2, attribute.data.count)
				num_floats := cgltf.accessor_unpack_floats(attribute.data, nil, 0)
				assert(num_floats == attribute.data.count * 2)
				num_floats = cgltf.accessor_unpack_floats(attribute.data, &texcoords[0][0], num_floats)
				fmt.println("unpack floats ", num_floats)
			}
		}
	}

	pitch := f32(math.TAU / 12)
	yaw := f32(math.TAU / 8)
	distance := f32(5.0)

	cam_pos := [3]f32 {
		math.cos(pitch) * math.cos(yaw),
		math.cos(pitch) * math.sin(yaw),
		math.sin(pitch),
	}
	cam_fwd := linalg.normalize(-cam_pos)
	cam_pos *= distance
	cam_up := [3]f32{0, 0, 1}
	cam_left := linalg.normalize(linalg.cross(cam_up, cam_fwd))
	cam_up = linalg.cross(cam_fwd, cam_left)

	f32m4 :: matrix[4, 4]f32

	cam_mat := linalg.matrix4_look_at(cam_pos, [3]f32{}, [3]f32{0, 1, 0})

	fovy := math.to_radians(f64(90.0))
	aspect := 16.0/9.0
	near := 0.1
	far := 100.0
	view_mat := linalg.matrix4_perspective_f64(fovy, aspect, near, far)

	model_mat : matrix[4,4]f32 = 1


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
			mui_process_sdl_event(window.mui_ctx, sdl_event)
		}

		ticks := SDL.GetTicksNS()
		delta_ticks := ticks - last_ticks
		dt = f64(delta_ticks) * 1e-9
		t += dt
		last_ticks = ticks


		mui.begin(window.mui_ctx)

		if mui.window(window.mui_ctx, "window", {100, 100, 400, 300}) {
			mui.label(window.mui_ctx, "My Label")
			mui.checkbox(window.mui_ctx, "My Checkbox", &bool_value)
			mui.number(window.mui_ctx, &my_color.x, 1.0/255)
		}
		mui.end(window.mui_ctx)


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

		render_pass := SDL.BeginGPURenderPass(cmd_buf, &color_target_info, 1, nil)
		SDL.BindGPUGraphicsPipeline(render_pass, pipeline)
		SDL.DrawGPUPrimitives(render_pass, 3, 1, 0, 0)
		SDL.EndGPURenderPass(render_pass)


		draw_ctx := DrawContext {gpu_device, cmd_buf, swapchain_tex, nil}
		draw_mui(&window, draw_ctx)


		submit_result := SDL.SubmitGPUCommandBuffer(cmd_buf)

	}

}
