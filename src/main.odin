
package main

import SDL "vendor:sdl3"
import IMG "vendor:sdl3/image"
import mui "vendor:microui"
import exr "vendor:OpenEXRCore"

import "core:fmt"
import "core:log"
import "core:math"
import "core:math/linalg"
import "core:math/linalg/hlsl"


// import "core:runtime"

main :: proc () {
	context.logger = log.create_console_logger()

	log.info("hello")

	log.info("SDL Init")
	init_success := SDL.Init(SDL.INIT_VIDEO)
	if (!init_success) {
		log.info("failed to initialize SDL")
		return
	}

	log.info("SDL CreateGPUDevice")
	gpu_device := SDL.CreateGPUDevice({.SPIRV}, true, nil)
	if gpu_device == nil {
		log.info("unable to get gpu device")
		return
	}
	defer SDL.DestroyGPUDevice(gpu_device)


	log.info("SDL CreateWindow")

	window_flags := SDL.WindowFlags{.VULKAN, .RESIZABLE}

	window := WindowData {
		size = {800, 600},
	}

	sdl_window := SDL.CreateWindow("My App", i32(window.size.x), i32(window.size.y), window_flags);
	if sdl_window == nil {
		log.info("failed to create sdl_window")
		return
	}
	defer SDL.DestroyWindow(sdl_window)

	log.info("SDL ClaimWindowForGPUDevice")
	success := SDL.ClaimWindowForGPUDevice(gpu_device, sdl_window)
	if !success {
		return
	}
	defer SDL.ReleaseWindowFromGPUDevice(gpu_device, sdl_window)

	log.info("SDL GetGPUSwapchainTextureFormat")
	window.format = SDL.GetGPUSwapchainTextureFormat(gpu_device, sdl_window)
	log.info("ui_load_pipelines")
	ui_load_pipelines(&window, gpu_device)
	defer ui_unload_pipelines(&window, gpu_device)

	pipeline: ^SDL.GPUGraphicsPipeline
	{
		shader_vert := LoadShader(gpu_device, "Content/Shaders/Compiled/SPIRV/RawTriangle.vert.spv", .VERTEX)

		shader_frag := LoadShader(gpu_device, "Content/Shaders/Compiled/SPIRV/SolidColor.frag.spv", .FRAGMENT)
		defer SDL.ReleaseGPUShader(gpu_device, shader_vert)
		defer SDL.ReleaseGPUShader(gpu_device, shader_frag)
		color_target_desc := []SDL.GPUColorTargetDescription{{
			format = window.format
		}}

		pipeline_info := SDL.GPUGraphicsPipelineCreateInfo {
			vertex_shader = shader_vert,
			fragment_shader = shader_frag,
			target_info = {
				num_color_targets = 1,
				color_target_descriptions = raw_data(color_target_desc),
			},
		}

		pipeline = SDL.CreateGPUGraphicsPipeline(gpu_device, pipeline_info)
	}
	defer SDL.ReleaseGPUGraphicsPipeline(gpu_device, pipeline)


	mesh_pipeline: ^SDL.GPUGraphicsPipeline
	{
		shader_vert := LoadShader(gpu_device, "Content/Shaders/3d/basic.vert.spv", .VERTEX, 0, 0, 0, 2)
		shader_frag := LoadShader(gpu_device, "Content/Shaders/3d/basic.frag.spv", .FRAGMENT, 4, 0, 0, 1)
		defer SDL.ReleaseGPUShader(gpu_device, shader_vert)
		defer SDL.ReleaseGPUShader(gpu_device, shader_frag)
		color_target_desc := []SDL.GPUColorTargetDescription{{
			format = window.format
		}}

		vertex_buffer_descriptions := []SDL.GPUVertexBufferDescription {
			{slot=0, pitch=12}, 
			{slot=1, pitch=8},
			{slot=2, pitch=12},
			{slot=3, pitch=12},
		}
		vertex_attributes := []SDL.GPUVertexAttribute {
			{location = 0, buffer_slot = 0, format = .FLOAT3},
			{location = 1, buffer_slot = 1, format = .FLOAT2},
			{location = 2, buffer_slot = 2, format = .FLOAT3},
			{location = 3, buffer_slot = 3, format = .FLOAT3},
		}

		pipeline_info := SDL.GPUGraphicsPipelineCreateInfo {
			vertex_shader = shader_vert,
			fragment_shader = shader_frag,
			vertex_input_state = {
				&vertex_buffer_descriptions[0], u32(len(vertex_buffer_descriptions)),
				&vertex_attributes[0], u32(len(vertex_attributes)),
			},
			depth_stencil_state = SDL.GPUDepthStencilState {
				compare_op = .LESS_OR_EQUAL,
				enable_depth_test = true,
				enable_depth_write = true,
			},
			target_info = SDL.GPUGraphicsPipelineTargetInfo {
				num_color_targets = 1,
				color_target_descriptions = raw_data(color_target_desc),
				depth_stencil_format = .D32_FLOAT,
				has_depth_stencil_target = true,
			},
		}

		mesh_pipeline = SDL.CreateGPUGraphicsPipeline(gpu_device, pipeline_info)
	}
	defer SDL.ReleaseGPUGraphicsPipeline(gpu_device, mesh_pipeline)


	env_pipeline: ^SDL.GPUGraphicsPipeline
	{
		shader_vert := LoadShader(gpu_device, "Content/Shaders/3d/env.vert.spv", .VERTEX, 0, 0, 0, 1)
		shader_frag := LoadShader(gpu_device, "Content/Shaders/3d/env.frag.spv", .FRAGMENT, 1, 0, 0, 0)
		defer SDL.ReleaseGPUShader(gpu_device, shader_vert)
		defer SDL.ReleaseGPUShader(gpu_device, shader_frag)
		color_target_desc := []SDL.GPUColorTargetDescription{{
			format = window.format
		}}

		pipeline_info := SDL.GPUGraphicsPipelineCreateInfo {
			vertex_shader = shader_vert,
			fragment_shader = shader_frag,
			primitive_type = .TRIANGLESTRIP,
			target_info = SDL.GPUGraphicsPipelineTargetInfo {
				num_color_targets = 1,
				color_target_descriptions = raw_data(color_target_desc),
			},
		}

		env_pipeline = SDL.CreateGPUGraphicsPipeline(gpu_device, pipeline_info)
	}
	defer SDL.ReleaseGPUGraphicsPipeline(gpu_device, env_pipeline)


	window.mui_ctx = new(mui.Context)
	mui.init(window.mui_ctx)
	window.mui_ctx.text_width = mui.default_atlas_text_width
	window.mui_ctx.text_height = mui.default_atlas_text_height


	t: f64 = 0
	dt: f64 = 0
	last_ticks: u64 = SDL.GetTicksNS()


	hdr_path: cstring = "Content/sample/empty_play_room_4k.exr"
	log.info("hdr IMG.Load")
	exr_ctx: exr.context_t
	result := exr.start_read(&exr_ctx, hdr_path, nil)
	assert(result == .SUCCESS)

	num_parts: i32
	exr.get_count(exr_ctx, &num_parts)
	assert(num_parts == 1)

	part_name: cstring
	exr.get_name(exr_ctx, 0, &part_name)
	log.info("got part:", part_name)

	channels: ^exr.attr_chlist_t
	channel_r, channel_g, channel_b: i32
	exr.get_channels(exr_ctx, 0, &channels)
	for idx in 0..<channels.num_channels {
		channel := channels.entries[idx]
		log.info("  channel: ", channel)
		if channel.name.str == "R" { channel_r = idx }
		else if channel.name.str == "G" { channel_g = idx }
		else if channel.name.str == "B" { channel_b = idx }
	}

	log.info("  channel_r: ", channel_r)
	log.info("  channel_g: ", channel_g)
	log.info("  channel_b: ", channel_b)

	data_window: exr.attr_box2i_t
	exr.get_data_window(exr_ctx, 0, &data_window)
	log.info("  data_window: ", data_window)

	exr_size := [2]i32 {
		data_window.max.x - data_window.min.x + 1,
		data_window.max.y - data_window.min.y + 1,
	}
	exr_num_pixels := exr_size.x * exr_size.y
	exr_pixels := make([]hlsl.float4, exr_num_pixels)


	// ensure our image isn't tile based as we don't support that yet
	exr_tile_levels_x, exr_tile_levels_y: i32
	tile_levels_result := exr.get_tile_levels(exr_ctx, 0, &exr_tile_levels_x, &exr_tile_levels_y)
	assert(tile_levels_result != .SUCCESS)

	chunk_count: i32
	exr.get_chunk_count(exr_ctx, 0, &chunk_count)
	log.info("chunk count:", chunk_count)
	log.info("start decoding")

	scanline: i32 = 0
	for scanline < exr_size.y {
		chunk_info: exr.chunk_info_t
		exr.read_scanline_chunk_info(exr_ctx, 0, scanline, &chunk_info)
		//bytes := make([]u8, chunk_info.packed_size)
		//exr.read_chunk(exr_ctx, 0, chunk_info, &bytes[0])
		decoder: exr.decode_pipeline_t
		exr.decoding_initialize(exr_ctx, 0, &chunk_info, &decoder)

		start_idx := chunk_info.start_x + (chunk_info.start_y * exr_size.x)
		log.info("loading chunk ", chunk_info)
		scanline = chunk_info.start_y + chunk_info.height

		decode_r := &decoder.channels[channel_r]
		decode_r.user_bytes_per_element = 4
		decode_r.user_data_type = u16(exr.pixel_type_t.FLOAT)
		decode_r.user_pixel_stride = 16
		decode_r.user_line_stride = 16 * exr_size.x
		decode_r.decode_to_ptr = (^u8)(&exr_pixels[start_idx][0])
		
		decode_g := &decoder.channels[channel_g]
		decode_g.user_bytes_per_element = 4
		decode_g.user_data_type = u16(exr.pixel_type_t.FLOAT)
		decode_g.user_pixel_stride = 16
		decode_g.user_line_stride = 16 * exr_size.x
		decode_g.decode_to_ptr = (^u8)(&exr_pixels[start_idx][1])
		
		decode_b := &decoder.channels[channel_b]
		decode_b.user_bytes_per_element = 4
		decode_b.user_data_type = u16(exr.pixel_type_t.FLOAT)
		decode_b.user_pixel_stride = 16
		decode_b.user_line_stride = 16 * exr_size.x
		decode_b.decode_to_ptr = (^u8)(&exr_pixels[start_idx][2])

		exr.decoding_choose_default_routines(exr_ctx, 0, &decoder)
		exr.decoding_run(exr_ctx, 0, &decoder)

		exr.decoding_destroy(exr_ctx, &decoder)
	}	
	log.info("finished decoding")

	environment := ab_create_texture_raw(gpu_device, {u32(exr_size.x), u32(exr_size.y)}, exr_pixels)
	
	/*
	Hdr_img := IMG.Load(hdr_path)
	if hdr_img == nil {
		error := SDL.GetError()
		log.info("error loading file, ", error)
		return
	}
	log.info("hdr create_texture hdr")
	hdr_tex := ab_create_texture(gpu_device, hdr_img)
*/
	log.info("copy to gpu")
	copy_cmd_buf := SDL.AcquireGPUCommandBuffer(gpu_device)
	copy_pass := SDL.BeginGPUCopyPass(copy_cmd_buf)
	ab_texture_upload(environment, copy_pass)
	SDL.EndGPUCopyPass(copy_pass)
	log.info("submitting copy")
	copy_submit_result := SDL.SubmitGPUCommandBuffer(copy_cmd_buf)
	log.info("submitted copy")

	helmet_path :cstring= "Content/sample/damaged_helmet.glb"
	helmet := mesh_load(helmet_path, gpu_device)
	defer mesh_free(&helmet, gpu_device)

	instances := []MeshInstance3D {
		{
			mesh = &helmet,
			transform = PosRotScale{
				position = {0, 0, 0},
				scale = {1,1,1},
			},
		},
		{
			mesh = &helmet,
			transform = PosRotScale{
				position = {4, 0, 0},
				scale = {1,1,1},
			},
		},
	}

	log.info("instances")

	for &instance in instances {
		instance_trs : PosRotScale = instance.transform.(PosRotScale)
		instance_rot := instance_trs.rotation
		quat := linalg.quaternion_from_pitch_yaw_roll(instance_rot.y, instance_rot.z, instance_rot.x)

		instance.global_transform = linalg.matrix4_from_trs(instance_trs.position, quat, instance_trs.scale)

	}


	pitch := f32(math.TAU / 12)
	yaw := f32(math.TAU / 8)
	distance := f32(5.0)
	f32m4 :: matrix[4, 4]f32

	light_pitch := f32(math.TAU / 4 * 0.7)
	light_yaw := f32(math.TAU / 8)

	tex_depth := SDL.CreateGPUTexture(gpu_device, {
		type = .D2,
		format = .D32_FLOAT,
		usage = {.DEPTH_STENCIL_TARGET},
		width = window.size.x,
		height = window.size.y,
		layer_count_or_depth = 1,
		num_levels = 1,
		//sample_count = ._1 GPUSampleCount,  /**< The number of samples per texel. Only applies if the texture is used as a render target. */
		//props:                PropertiesID,          /**< A properties ID for extensions. Should be 0 if no extensions are needed. */
	})
	defer SDL.ReleaseGPUTexture(gpu_device, tex_depth)


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
				window.size = {u32(window_event.data1), u32(window_event.data2)}

				SDL.ReleaseGPUTexture(gpu_device, tex_depth)
				tex_depth = SDL.CreateGPUTexture(gpu_device, {
					type = .D2,
					format = .D32_FLOAT,
					usage = {.DEPTH_STENCIL_TARGET},
					width = window.size.x,
					height = window.size.y,
					layer_count_or_depth = 1,
					num_levels = 1,
					//sample_count = ._1 GPUSampleCount,  /**< The number of samples per texel. Only applies if the texture is used as a render target. */
					//props:                PropertiesID,          /**< A properties ID for extensions. Should be 0 if no extensions are needed. */
				})

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
			mui.checkbox(window.mui_ctx, "My Checkbox", &bool_value)
			mui.label(window.mui_ctx, "Distance")
			mui.number(window.mui_ctx, &distance, 1.0/255)
			mui.label(window.mui_ctx, "Pitch")
			mui.number(window.mui_ctx, &pitch, 1.0/255)
			mui.label(window.mui_ctx, "Yaw")
			mui.number(window.mui_ctx, &yaw, 1.0/255)
			mui.label(window.mui_ctx, "Light Pitch")
			mui.number(window.mui_ctx, &light_pitch, 1.0/255)
			mui.label(window.mui_ctx, "Light Yaw")
			mui.number(window.mui_ctx, &light_yaw, 1.0/255)

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

		color_target_info_3d := SDL.GPUColorTargetInfo {
			texture = swapchain_tex,
			load_op = .LOAD,
			store_op = .STORE,
		}

		depth_target_info := SDL.GPUDepthStencilTargetInfo {
			texture = tex_depth,
			// texture:          ^GPUTexture,  /**< The texture that will be used as the depth stencil target by the render pass. */
			clear_depth = 1,
			// clear_depth:      f32,          /**< The value to clear the depth component to at the beginning of the render pass. Ignored if GPU_LOADOP_CLEAR is not used. */
			load_op = .CLEAR,
			// load_op:          GPULoadOp,    /**< What is done with the depth contents at the beginning of the render pass. */
			store_op = .STORE,
			// store_op:         GPUStoreOp,   /**< What is done with the depth results of the render pass. */
			// stencil_load_op = .CLEAR,
			// stencil_store_op = .STORE,
			cycle = false,
			// clear_stencil = 0
		}


		cam_pos := [3]f32 {
			math.cos(pitch) * math.cos(yaw),
			math.sin(pitch),
			math.cos(pitch) * math.sin(yaw),
		}
		cam_fwd := linalg.normalize(-cam_pos)
		cam_pos *= distance
		cam_up := [3]f32{0, 0, 1}
		cam_left := linalg.normalize(linalg.cross(cam_up, cam_fwd))
		cam_up = linalg.cross(cam_fwd, cam_left)

		cam_mat := linalg.matrix4_look_at(cam_pos, [3]f32{}, [3]f32{0, 1, 0})

		fovy := math.to_radians(f64(90.0))
		aspect := f32(window.size.x) / f32(window.size.y)
		near := 0.1
		far := 100.0
		proj_mat := linalg.matrix4_perspective_f32(f32(fovy), f32(aspect), f32(near), f32(far))
		uniform0 := [2]f32m4 {cam_mat, proj_mat}

		global_sampler_bindings := []SDL.GPUTextureSamplerBinding {
			{
				texture = environment.texture,
				sampler = window.ui_sampler,
			},
		}

		mesh_render_pass := SDL.BeginGPURenderPass(cmd_buf, &color_target_info_3d, 1, &depth_target_info)

		SDL.SetGPUViewport(mesh_render_pass, {0, 0, f32(window.size.x), f32(window.size.y), 0, 1})

		// draw environment
		SDL.BindGPUGraphicsPipeline(mesh_render_pass, env_pipeline)
		SDL.PushGPUVertexUniformData(cmd_buf, 0, &uniform0, size_of(uniform0))

		SDL.BindGPUFragmentSamplers(mesh_render_pass, 0, &global_sampler_bindings[0], u32(len(global_sampler_bindings)))
		SDL.DrawGPUPrimitives(mesh_render_pass, 4, 1, 0, 0)

		// draw meshes
		SDL.BindGPUGraphicsPipeline(mesh_render_pass, mesh_pipeline)
		SDL.PushGPUVertexUniformData(cmd_buf, 0, &uniform0, size_of(uniform0))

		light_yaw += f32(dt)
		light_data := [4]f32 {
			math.cos(light_pitch) * math.cos(light_yaw),
			math.sin(light_pitch),
			math.cos(light_pitch) * math.sin(light_yaw),
			0,
		}

		SDL.PushGPUFragmentUniformData(cmd_buf, 0, &light_data, size_of(light_data))

		SDL.BindGPUFragmentSamplers(mesh_render_pass, 3, &global_sampler_bindings[0], u32(len(global_sampler_bindings)))


		for &instance in instances {
			SDL.PushGPUVertexUniformData(cmd_buf, 1, &instance.global_transform, size_of(instance.global_transform))
			SDL.PushGPUFragmentUniformData(cmd_buf, 0, &light_data, size_of(light_data))
			mesh_draw(mesh_render_pass, instance.mesh^)
		}

		SDL.EndGPURenderPass(mesh_render_pass)



		draw_ctx := DrawContext {gpu_device, cmd_buf, swapchain_tex, nil}
		draw_mui(&window, draw_ctx)


		submit_result := SDL.SubmitGPUCommandBuffer(cmd_buf)

	}

}
