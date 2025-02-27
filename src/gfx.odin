
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