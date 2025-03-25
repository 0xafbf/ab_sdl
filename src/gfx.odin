
package main

import "vendor/shaderc"

import SDL "vendor:sdl3"
import mui "vendor:microui"
import "vendor:cgltf"

import "core:math"
import "core:math/linalg"
import hlm "core:math/linalg/hlsl"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"


Gfx :: struct {
	gpu: ^SDL.GPUDevice,
	compiler: shaderc.compiler_t,

	format: SDL.GPUTextureFormat,

	mesh_shader: Shader2,
	line_shader: Shader2,
	env_shader: Shader2,
}

Shader2 :: struct {
	pipeline: ^SDL.GPUGraphicsPipeline,
}


gfx_create :: proc(
	gpu: ^SDL.GPUDevice, window: WindowData
) -> (gfx: Gfx) {

	gfx.gpu = gpu
	gfx.compiler = shaderc.compiler_initialize()
	gfx.format = window.format

	gfx.mesh_shader = gfx_make_mesh_shader(gfx)
	gfx.line_shader = gfx_make_line_shader(gfx)
	gfx.env_shader = gfx_make_env_shader(gfx)
	return gfx
}

gfx_destroy :: proc(gfx: Gfx) {
	shaderc.compiler_release(gfx.compiler)
	SDL.ReleaseGPUGraphicsPipeline(gfx.gpu, gfx.mesh_shader.pipeline)
	SDL.ReleaseGPUGraphicsPipeline(gfx.gpu, gfx.line_shader.pipeline)
	SDL.ReleaseGPUGraphicsPipeline(gfx.gpu, gfx.env_shader.pipeline)
}


path_has_prefix :: proc(file_path, prefix: string) -> bool {
	for idx in 0..<len(prefix) {
		c1 := file_path[idx]
		c2 := prefix[idx]
		if file_path[idx] == prefix[idx] {
			continue
		}
		when ODIN_OS == .Windows {
		if os.is_path_separator(c1) && os.is_path_separator(c2) {
			continue
		}
		}
		return false
	}
	return true
}


gfx_on_file_changed :: proc(gfx: ^Gfx, file_path: string) {
	if path_has_prefix(file_path, "Content/Shaders/3d/basic") {
		gfx_release_shader(gfx^, gfx^.mesh_shader)
		gfx.mesh_shader = gfx_make_mesh_shader(gfx^)
	}
	if path_has_prefix(file_path, "Content/Shaders/3d/line") {
		gfx_release_shader(gfx^, gfx^.mesh_shader)
		gfx.line_shader = gfx_make_mesh_shader(gfx^)
	}
}


gfx_release_shader :: proc(gfx: Gfx, shader: Shader2) {
	SDL.ReleaseGPUGraphicsPipeline(gfx.gpu, shader.pipeline)
}


gfx_make_mesh_shader :: proc(gfx: Gfx) -> Shader2 {
	base_path := "Content/Shaders/3d/basic"
	shader_vert, shader_frag := LoadShader(gfx, base_path, {0, 0, 0, 2}, {4, 0, 0, 1})
	defer SDL.ReleaseGPUShader(gfx.gpu, shader_vert)
	defer SDL.ReleaseGPUShader(gfx.gpu, shader_frag)
	color_target_desc := []SDL.GPUColorTargetDescription{
		{ format = gfx.format },
	}

	vertex_buffer_descriptions := []SDL.GPUVertexBufferDescription {
		{slot=0, pitch=12},
		{slot=1, pitch=8},
		{slot=2, pitch=12},
		{slot=3, pitch=16},
	}
	vertex_attributes := []SDL.GPUVertexAttribute {
		{location = 0, buffer_slot = 0, format = .FLOAT3},
		{location = 1, buffer_slot = 1, format = .FLOAT2},
		{location = 2, buffer_slot = 2, format = .FLOAT3},
		{location = 3, buffer_slot = 3, format = .FLOAT4},
	}

	shader: Shader2
	shader.pipeline = SDL.CreateGPUGraphicsPipeline(gfx.gpu, SDL.GPUGraphicsPipelineCreateInfo {
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
	})
	return shader
}

gfx_make_line_shader :: proc(gfx: Gfx) -> Shader2 {
	base_path := "Content/Shaders/3d/line"
	shader_vert, shader_frag := LoadShader(gfx, base_path, {0, 0, 0, 3}, {1, 0, 0, 0})
	defer SDL.ReleaseGPUShader(gfx.gpu, shader_vert)
	defer SDL.ReleaseGPUShader(gfx.gpu, shader_frag)
	color_target_desc := []SDL.GPUColorTargetDescription{
		{ format = gfx.format },
	}

	vertex_buffer_descriptions := []SDL.GPUVertexBufferDescription {
		{slot=0, pitch=12},
		{slot=1, pitch=8},
		{slot=2, pitch=16},
		{slot=3, pitch=12},
		{slot=4, pitch=12},
	}
	vertex_attributes := []SDL.GPUVertexAttribute {
		{location = 0, buffer_slot = 0, format = .FLOAT3},
		{location = 1, buffer_slot = 1, format = .FLOAT2},
		{location = 2, buffer_slot = 2, format = .FLOAT4},
		{location = 3, buffer_slot = 3, format = .FLOAT3},
		{location = 4, buffer_slot = 4, format = .FLOAT3},
	}

	shader: Shader2
	shader.pipeline = SDL.CreateGPUGraphicsPipeline(gfx.gpu, SDL.GPUGraphicsPipelineCreateInfo {
		vertex_shader = shader_vert,
		fragment_shader = shader_frag,
		primitive_type = .TRIANGLESTRIP,
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
	})
	return shader;
}

gfx_make_env_shader :: proc(gfx: Gfx) -> Shader2 {
	base_path := "Content/Shaders/3d/env"
	shader_vert, shader_frag := LoadShader(gfx, base_path, {0, 0, 0, 1}, {1, 0, 0, 0})
	defer SDL.ReleaseGPUShader(gfx.gpu, shader_vert)
	defer SDL.ReleaseGPUShader(gfx.gpu, shader_frag)
	color_target_desc := []SDL.GPUColorTargetDescription{{
		format = gfx.format
	}}
	shader: Shader2
	shader.pipeline = SDL.CreateGPUGraphicsPipeline(gfx.gpu, SDL.GPUGraphicsPipelineCreateInfo {
		vertex_shader = shader_vert,
		fragment_shader = shader_frag,
		primitive_type = .TRIANGLESTRIP,
		target_info = SDL.GPUGraphicsPipelineTargetInfo {
			num_color_targets = 1,
			color_target_descriptions = raw_data(color_target_desc),
		},
	})
	return shader
}



ShaderStageInput :: struct {
	num_samplers: u32,
	num_storage_textures: u32,
	num_storage_buffers: u32,
	num_uniform_buffers: u32,
}

LoadShader :: proc(
	gfx: Gfx, base_path: string, vertex_inputs, fragment_inputs: ShaderStageInput
) -> (
	vert, frag: ^SDL.GPUShader
) {
	log.info("loading shader:", base_path)
	vert = CompLoadShader(gfx, fmt.ctprintf("%s.vert.glsl", base_path), .VERTEX, vertex_inputs)
	frag = CompLoadShader(gfx, fmt.ctprintf("%s.frag.glsl", base_path), .FRAGMENT, fragment_inputs)
	return vert, frag
}

CompLoadShader :: proc(
	gfx: Gfx,
	in_path: cstring,
	in_stage: SDL.GPUShaderStage,
	inputs: ShaderStageInput,
) -> ^SDL.GPUShader {

	shader_size: uint = ---
	shader_code := SDL.LoadFile(in_path, &shader_size)

	compile_options := shaderc.compile_options_initialize()
	shaderc.compile_options_set_source_language(compile_options, shaderc.source_language.glsl)

	log.info("compiling shader:", in_path)
	shader_kind := shaderc.shader_kind.vertex_shader
	if in_stage == .FRAGMENT {
		shader_kind = .fragment_shader
	}
	entry_point_name := "main"

	compile_result := shaderc.compile_into_spv(
		gfx.compiler,
		cstring(shader_code),
		shader_size,
		shader_kind,
		in_path,
		"main",
		compile_options
	)

	num_errors := shaderc.result_get_num_errors(compile_result)
	for error_idx in 0..<num_errors {
		error := shaderc.result_get_error_message(compile_result)
		log.error("Error while compiling shader:\n", error)
	}


	SDL.free(shader_code)

	log.info("create gpushader:", in_path)
	shader_info := SDL.GPUShaderCreateInfo {
		code_size = shaderc.result_get_length(compile_result),
		code = shaderc.result_get_bytes(compile_result),
		entrypoint = "main",
		format = {.SPIRV},
		stage = in_stage,
		num_samplers = inputs.num_samplers,
		num_storage_textures = inputs.num_storage_textures,
		num_storage_buffers = inputs.num_storage_buffers,
		num_uniform_buffers = inputs.num_uniform_buffers,
	}

	shader := SDL.CreateGPUShader(gfx.gpu, shader_info)

	shaderc.result_release(compile_result)

	return shader
}


Texture :: struct {
	size: [2]u32,
	surface: ^SDL.Surface,
	texture: ^SDL.GPUTexture,
	transfer_buffer: ^SDL.GPUTransferBuffer,
}

ab_create_texture_raw :: proc(gpu: ^SDL.GPUDevice, size: [2]u32, data_rgba: [][4]f32) -> (result: Texture) {
	result.size = size
	log.info("A")
	texture_format: SDL.GPUTextureFormat = .R32G32B32A32_FLOAT
	result.texture = SDL.CreateGPUTexture(gpu, SDL.GPUTextureCreateInfo{
		type = .D2,
		format = texture_format,
		usage = {.SAMPLER},
		width = size.x,
		height = size.y,
		layer_count_or_depth = 1,
		num_levels = 1,
	})
	buffer_size: u32 = size.x * size.y * 4 * 4
	result.transfer_buffer = SDL.CreateGPUTransferBuffer(gpu, SDL.GPUTransferBufferCreateInfo {
		usage = .UPLOAD,
		size = buffer_size,
	})

	log.info("B")
	transfer_mem := SDL.MapGPUTransferBuffer(gpu, result.transfer_buffer, false)
	mem.copy_non_overlapping(transfer_mem, &data_rgba[0][0], int(buffer_size))
	SDL.UnmapGPUTransferBuffer(gpu, result.transfer_buffer)
	log.info("C")
	return result
}

ab_create_texture :: proc(gpu: ^SDL.GPUDevice, surface: ^SDL.Surface, format: SDL.GPUTextureFormat) -> Texture {
	assert(surface != nil)
	texture_format: SDL.GPUTextureFormat
	exact_match: bool = false
	bytes_per_pixel: u32 = 0
	if surface.format == .RGB24 {
		texture_format = .R8G8B8A8_UNORM
		exact_match = false
		bytes_per_pixel = 4
	} else if surface.format == .ABGR8888 {
		texture_format = .R8G8B8A8_UNORM
		exact_match = false
		bytes_per_pixel = 4
	}

	assert(texture_format != .INVALID)
	result: Texture
	result.size = {u32(surface.w), u32(surface.h)}
	result.surface = surface
	result.texture = SDL.CreateGPUTexture(gpu, SDL.GPUTextureCreateInfo{
		type = .D2,
		format = format,
		usage = {.SAMPLER},
		width = result.size.x,
		height = result.size.y,
		layer_count_or_depth = 1,
		num_levels = 1,
	})

	num_pixels := result.size.x * result.size.y
	buffer_size: u32 = num_pixels * bytes_per_pixel
	result.transfer_buffer = SDL.CreateGPUTransferBuffer(gpu, SDL.GPUTransferBufferCreateInfo{
		usage = .UPLOAD,
		size = buffer_size,
	})

	transfer_buffer_mem := SDL.MapGPUTransferBuffer(gpu, result.transfer_buffer, false)
	if exact_match {
		mem.copy_non_overlapping(transfer_buffer_mem, &mui.default_atlas_alpha[0], int(buffer_size));
	} else {
		if surface.format == .RGB24 {
			rgb :: [3]u8
			rgba :: [4]u8
			tgt_mem := ([^]rgba)(transfer_buffer_mem)
			src_mem := ([^]rgb)(surface.pixels)
			for idx in 0 ..< num_pixels {
				tgt_mem[idx].xyz = src_mem[idx]
			}
		} else if surface.format == .ABGR8888 {
			vec4u8 :: [4]u8
			tgt_mem := ([^]vec4u8)(transfer_buffer_mem)
			src_mem := ([^]vec4u8)(surface.pixels)
			for idx in 0 ..< num_pixels {
				//tgt_mem[idx].xyzw = src_mem[idx].wzyx
				tgt_mem[idx] = src_mem[idx]
			}
		}
	}
	SDL.UnmapGPUTransferBuffer(gpu, result.transfer_buffer)
	return result
}

ab_texture_upload :: proc(tex: Texture, copy_pass: ^SDL.GPUCopyPass) {
	SDL.UploadToGPUTexture(copy_pass, SDL.GPUTextureTransferInfo {
		transfer_buffer = tex.transfer_buffer,
		pixels_per_row = tex.size.x,
		rows_per_layer = tex.size.y,
	}, SDL.GPUTextureRegion {
		texture = tex.texture, 
		x = 0, y = 0, 
		w = tex.size.x, h = tex.size.y, d = 1,
	}, false)
}



MeshBuffer :: struct {
	size: u32,
	gpu_buffer: ^SDL.GPUBuffer,
	transfer_buffer: ^SDL.GPUTransferBuffer,
	data: union {[]f32, []u32}
}

meshbuffer_create :: proc (gpu: ^SDL.GPUDevice, field: []$T, usage: SDL.GPUBufferUsageFlags) -> MeshBuffer {
	fmt.println("meshbuffer_create")
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

meshbuffer_destroy :: proc(gpu: ^SDL.GPUDevice, buf: ^MeshBuffer) {
	SDL.ReleaseGPUBuffer(gpu, buf.gpu_buffer)
	SDL.ReleaseGPUTransferBuffer(gpu, buf.transfer_buffer)
	buf.gpu_buffer = nil
	buf.transfer_buffer = nil
}
