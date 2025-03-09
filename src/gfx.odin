
package main

import SDL "vendor:sdl3"
import mui "vendor:microui"
import "vendor:cgltf"

import "core:math"
import "core:math/linalg"
import hlm "core:math/linalg/hlsl"
import "core:fmt"
import "core:log"
import "core:mem"

// import "core:runtime"

LoadShader :: proc(
	gpu: ^SDL.GPUDevice, 
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

	shader := SDL.CreateGPUShader(gpu, shader_info)
	SDL.free(shader_code)

	return shader
}

Texture :: struct {
	surface: ^SDL.Surface,
	texture: ^SDL.GPUTexture,
	transfer_buffer: ^SDL.GPUTransferBuffer,
}

ab_create_texture :: proc(gpu: ^SDL.GPUDevice, surface: ^SDL.Surface) -> Texture {
	texture_format: SDL.GPUTextureFormat
	exact_match: bool = false
	bytes_per_pixel: i32 = 0
	if surface.format == .RGB24 {
		texture_format = .R8G8B8A8_UNORM
		exact_match = false
		bytes_per_pixel = 4
	}

	assert(texture_format != .INVALID)
	result: Texture
	result.surface = surface
	result.texture = SDL.CreateGPUTexture(gpu, SDL.GPUTextureCreateInfo{
		type = .D2,
		format = texture_format,
		usage = {.SAMPLER},
		width = u32(surface.w),
		height = u32(surface.h),
		layer_count_or_depth = 1,
		num_levels = 1,
	})

	buffer_size: i32 = surface.w * surface.h * bytes_per_pixel
	result.transfer_buffer = SDL.CreateGPUTransferBuffer(gpu, SDL.GPUTransferBufferCreateInfo{
		usage = .UPLOAD,
		size = u32(buffer_size),
	})

	transfer_buffer_mem := SDL.MapGPUTransferBuffer(gpu, result.transfer_buffer, false)
	if exact_match {
		mem.copy_non_overlapping(transfer_buffer_mem, &mui.default_atlas_alpha[0], int(buffer_size));
	} else {
		rgb :: [3]u8
		rgba :: [4]u8
		num_pixels := surface.w * surface.h
		tgt_mem := ([^]rgba)(transfer_buffer_mem)
		src_mem := ([^]rgb)(surface.pixels)
		for idx in 0..<(num_pixels) {
			tgt_mem[idx].xyz = src_mem[idx]
		}
	}
	SDL.UnmapGPUTransferBuffer(gpu, result.transfer_buffer)
	return result
}

ab_texture_upload :: proc(tex: Texture, copy_pass: ^SDL.GPUCopyPass) {
	SDL.UploadToGPUTexture(copy_pass, SDL.GPUTextureTransferInfo {
		transfer_buffer = tex.transfer_buffer,
		pixels_per_row = u32(tex.surface.w),
		rows_per_layer = u32(tex.surface.h),
	}, SDL.GPUTextureRegion {
		texture = tex.texture, 
		x = 0, y = 0, 
		w = u32(tex.surface.w), h = u32(tex.surface.h), d = 1,
	}, false)
}



MeshBuffer :: struct {
	size: u32,
	gpu_buffer: ^SDL.GPUBuffer,
	transfer_buffer: ^SDL.GPUTransferBuffer,
	data: union {[]f32, []u32}
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

meshbuffer_destroy :: proc(gpu: ^SDL.GPUDevice, buf: ^MeshBuffer) {
	SDL.ReleaseGPUBuffer(gpu, buf.gpu_buffer)
	SDL.ReleaseGPUTransferBuffer(gpu, buf.transfer_buffer)
	buf.gpu_buffer = nil
	buf.transfer_buffer = nil
}
