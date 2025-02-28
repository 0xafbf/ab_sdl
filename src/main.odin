
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

	sdl_window := SDL.CreateWindow("My App", i32(window.size.x), i32(window.size.y), window_flags);
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

		pipeline = SDL.CreateGPUGraphicsPipeline(gpu_device, pipeline_info)
	}
	defer SDL.ReleaseGPUGraphicsPipeline(gpu_device, pipeline)


	mesh_pipeline: ^SDL.GPUGraphicsPipeline
	{
		fmt.println("loading vertex shader")
		fmt.println("loading vertex shader")
		fmt.println("loading vertex shader")
		shader_vert := LoadShader(gpu_device, "Content/Shaders/3d/basic.vert.spv", .VERTEX, 0, 0, 0, 2)
		fmt.println("loading frag shader")
		fmt.println("loading frag shader")
		fmt.println("loading frag shader")
		shader_frag := LoadShader(gpu_device, "Content/Shaders/3d/basic.frag.spv", .FRAGMENT, 1, 0, 0, 0)
		defer SDL.ReleaseGPUShader(gpu_device, shader_vert)
		defer SDL.ReleaseGPUShader(gpu_device, shader_frag)
		color_target_desc := []SDL.GPUColorTargetDescription{{
			format = window.format
		}}

		vertex_buffer_descriptions := []SDL.GPUVertexBufferDescription {
			{slot=0, pitch=12}, 
			{slot=1, pitch=8},
		}
		vertex_attributes := []SDL.GPUVertexAttribute {
			{location = 0, buffer_slot = 0, format = .FLOAT3},
			{location = 1, buffer_slot = 1, format = .FLOAT2},
		}

		depth_stencil_state := SDL.GPUDepthStencilState {
			compare_op = .LESS_OR_EQUAL,
			enable_depth_test = true,
			enable_depth_write = true,
		}


		pipeline_info := SDL.GPUGraphicsPipelineCreateInfo {
			vertex_shader = shader_vert,
			fragment_shader = shader_frag,
			// vertex_input_state:  GPUVertexInputState,            /**< The vertex layout of the graphics pipeline. */
			vertex_input_state = {
				&vertex_buffer_descriptions[0], u32(len(vertex_buffer_descriptions)),
				&vertex_attributes[0], u32(len(vertex_attributes)),
			},
			// primitive_type = .TRIANGLELIST,
			// rasterizer_state:    GPURasterizerState,             /**< The rasterizer state of the graphics pipeline. */
			// multisample_state:   GPUMultisampleState,            /**< The multisample state of the graphics pipeline. */
			depth_stencil_state = depth_stencil_state,
			// target_info:         GPUGraphicsPipelineTargetInfo,  /**< Formats and blend modes for the render targets of the graphics pipeline. */
			target_info = {
				num_color_targets = 1,
				color_target_descriptions = raw_data(color_target_desc),
				depth_stencil_format = .D32_FLOAT,
				has_depth_stencil_target = true,
			},
		}

		mesh_pipeline = SDL.CreateGPUGraphicsPipeline(gpu_device, pipeline_info)
	}
	defer SDL.ReleaseGPUGraphicsPipeline(gpu_device, mesh_pipeline)



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
	indices: []u32

	// positions = {
	// 	{-1, -1, -1},
	// 	{-1, -1,  1},
	// 	{-1,  1, -1},
	// 	{-1,  1,  1},
	// 	{ 1, -1, -1},
	// 	{ 1, -1,  1},
	// 	{ 1,  1, -1},
	// 	{ 1,  1,  1},
	// }
	// texcoords = {
	// 	{0,0},
	// 	{0,0},
	// 	{0,0},
	// 	{0,0},
	// 	{0,0},
	// 	{0,0},
	// 	{0,0},
	// 	{0,0},
	// }
	// indices = {
	// 	0, 1, 2, 2, 3, 1,
	// }


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

		indices = make([]u32, primitive.indices.count)
		num_indices := cgltf.accessor_unpack_indices(primitive.indices, nil, 4, 0)
		assert(len(indices) == int(num_indices))
		num_indices = cgltf.accessor_unpack_indices(primitive.indices, &indices[0], 4, num_indices)
	}

	MeshBuffer :: struct {
		size: u32,
		gpu_buffer: ^SDL.GPUBuffer,
		transfer_buffer: ^SDL.GPUTransferBuffer,
	}

	meshbuffer_create :: proc (gpu: ^SDL.GPUDevice, field: []$T, usage: SDL.GPUBufferUsageFlags) -> MeshBuffer {
		buf: MeshBuffer
		buf.size = u32(len(field) * size_of(T))
		buf.gpu_buffer = SDL.CreateGPUBuffer(gpu, {
			usage = usage,
			size = buf.size
		})
		buf.transfer_buffer = SDL.CreateGPUTransferBuffer(gpu, {
			usage = .UPLOAD,
			size = buf.size
		})

		transfer_buffer_mem := SDL.MapGPUTransferBuffer(gpu, buf.transfer_buffer, cycle = false)
		mem.copy_non_overlapping(transfer_buffer_mem, &field[0], int(buf.size))
		SDL.UnmapGPUTransferBuffer(gpu, buf.transfer_buffer)
		return buf
	}

	meshbuffer_upload :: proc(buf: MeshBuffer, copy_pass: ^SDL.GPUCopyPass) {
		SDL.UploadToGPUBuffer(copy_pass, 
			{buf.transfer_buffer, 0},
			{buf.gpu_buffer, 0, buf.size},
			cycle = false,
		)
	}

	meshbuffer_destroy :: proc(gpu: ^SDL.GPUDevice, buf: MeshBuffer) {
		SDL.ReleaseGPUBuffer(gpu, buf.gpu_buffer)
		SDL.ReleaseGPUTransferBuffer(gpu, buf.transfer_buffer)
	}

	buf_mesh_pos := meshbuffer_create(gpu_device, positions, {.VERTEX})
	buf_mesh_uv := meshbuffer_create(gpu_device, texcoords, {.VERTEX})
	buf_mesh_idx := meshbuffer_create(gpu_device, indices, {.INDEX})
	defer meshbuffer_destroy(gpu_device, buf_mesh_pos)
	defer meshbuffer_destroy(gpu_device, buf_mesh_uv)
	defer meshbuffer_destroy(gpu_device, buf_mesh_idx)

	copied := false

	// copy_cmd_buf := SDL.AcquireGPUCommandBuffer(gpu_device)
	// copy_pass := SDL.BeginGPUCopyPass(copy_cmd_buf)
	// meshbuffer_upload(buf_mesh_pos, copy_pass)
	// meshbuffer_upload(buf_mesh_uv, copy_pass)
	// meshbuffer_upload(buf_mesh_idx, copy_pass)
	// SDL.EndGPUCopyPass(copy_pass)
	// copy_submit_result := SDL.SubmitGPUCommandBuffer(copy_cmd_buf)


	pitch := f32(math.TAU / 12)
	yaw := f32(math.TAU / 8)
	distance := f32(5.0)
	f32m4 :: matrix[4, 4]f32


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

		}
		mui.end(window.mui_ctx)


		cmd_buf := SDL.AcquireGPUCommandBuffer(gpu_device)

		if !copied {
			copy_pass := SDL.BeginGPUCopyPass(cmd_buf)
			meshbuffer_upload(buf_mesh_pos, copy_pass)
			meshbuffer_upload(buf_mesh_uv, copy_pass)
			meshbuffer_upload(buf_mesh_idx, copy_pass)
			SDL.EndGPUCopyPass(copy_pass)
			copied = true
		}


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



		mesh_render_pass := SDL.BeginGPURenderPass(cmd_buf, &color_target_info_3d, 1, &depth_target_info)

		SDL.SetGPUViewport(mesh_render_pass, {0, 0, f32(window.size.x), f32(window.size.y), 0, 1})

		bindings := []SDL.GPUBufferBinding{
			{ buffer = buf_mesh_pos.gpu_buffer, offset = 0 },
			{ buffer = buf_mesh_uv.gpu_buffer, offset = 0 },
		}

		SDL.BindGPUGraphicsPipeline(mesh_render_pass, mesh_pipeline)
		SDL.BindGPUVertexBuffers(mesh_render_pass, 0, &bindings[0], u32(len(bindings)))
		SDL.BindGPUIndexBuffer(mesh_render_pass, {buf_mesh_idx.gpu_buffer, 0}, ._32BIT)



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

		model_scale : f32 = 1

		uniform0 := [2]f32m4 {cam_mat, proj_mat}
		model_mat : matrix[4,4]f32 = model_scale
		model_mat[3,3] = 1
		SDL.PushGPUVertexUniformData(cmd_buf, 0, &uniform0, size_of(uniform0))
		SDL.PushGPUVertexUniformData(cmd_buf, 1, &model_mat, size_of(model_mat))

		sampler_bindings := []SDL.GPUTextureSamplerBinding {
			{
				texture = window.ui_texture,
				sampler = window.ui_sampler,
			}
		}
		SDL.BindGPUFragmentSamplers(mesh_render_pass, 0, &sampler_bindings[0], u32(len(sampler_bindings)))

		// SDL.DrawGPUPrimitives(mesh_render_pass, u32(len(indices)), 1, 0, 0)
		SDL.DrawGPUIndexedPrimitives(mesh_render_pass, u32(len(indices)), 1, 0, 0, 0)
		// SDL.DrawGPUPrimitives(mesh_render_pass, 12, 1, 0, 0)
		SDL.EndGPURenderPass(mesh_render_pass)



		draw_ctx := DrawContext {gpu_device, cmd_buf, swapchain_tex, nil}
		draw_mui(&window, draw_ctx)


		submit_result := SDL.SubmitGPUCommandBuffer(cmd_buf)

	}

}
