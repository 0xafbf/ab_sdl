
package main

import SDL "vendor:sdl3"
import IMG "vendor:sdl3/image"
import "vendor:cgltf"

import "core:math/linalg/hlsl"
import "core:fmt"


vec2 :: [2]f32
vec3 :: [3]f32
vec4 :: [4]f32

Basis :: matrix[3,3]f32
Matrix3D :: matrix[4, 3]f32

PosRotScale :: struct {
	position: vec3,
	rotation: vec3,
	scale: vec3,
}

Transform3D :: union { PosRotScale, Matrix3D }


Node3D :: struct {
	transform: Transform3D,
	global_transform: Matrix3D,
}

MeshInstance3D :: struct {
	using node_3d: Node3D,
	mesh: ^Mesh,
}

Asset :: struct {
	path: string,
	derived: any,
}

Shader :: struct {
	using asset: Asset,
	code: []u8,
}


MaterialParameter :: struct {
	name: string,
	value: union { f32, [2]f32, [3]f32, [4]f32 },
}

Material :: struct {
	using asset: Asset,
	shader: ^Shader,
	parameters: [dynamic]MaterialParameter,
}


Mesh :: struct {
	using asset: Asset,
	materials: [dynamic]^Material,
	vert_positions: []vec3,
	vert_normals: []vec3,
	vert_texcoords: []vec2,
	indices: []u32,
	buf_mesh_pos: MeshBuffer,
	buf_mesh_uv: MeshBuffer,
	buf_mesh_idx: MeshBuffer,
	base_color_tex: Texture,
	sampler: ^SDL.GPUSampler,
}



mesh_free :: proc(mesh: ^Mesh, gpu: ^SDL.GPUDevice) {
	meshbuffer_destroy(gpu, &mesh.buf_mesh_pos)
	meshbuffer_destroy(gpu, &mesh.buf_mesh_uv)
	meshbuffer_destroy(gpu, &mesh.buf_mesh_idx)
}

mesh_load :: proc(path: cstring, gpu_device: ^SDL.GPUDevice) -> Mesh {
	data: ^cgltf.data
	result: cgltf.result

	data, result = cgltf.parse_file({}, path)
	assert(result == .success)
	load_result := cgltf.load_buffers({}, data, path)
	assert(load_result == .success)
	defer cgltf.free(data)


	positions: []hlsl.float3
	texcoords: []hlsl.float2
	indices: []u32

	rgba_u8 :: [4]u8
	rgb_u8 :: [3]u8
	rg_u8 :: [2]u8
	base_color: ^SDL.Surface

	scene := data.scene
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
				positions = make([]hlsl.float3, attribute.data.count)
				num_floats := cgltf.accessor_unpack_floats(attribute.data, nil, 0)
				assert(num_floats == attribute.data.count * 3)
				num_floats = cgltf.accessor_unpack_floats(attribute.data, &positions[0][0], num_floats)
			} else if attribute.type == .texcoord {
				assert(attribute.data.type == .vec2)
				texcoords = make([]hlsl.float2, attribute.data.count)
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

		mat := primitive.material
		fmt.println("material: ", mat)
		if mat.has_pbr_metallic_roughness {
			pbr := mat.pbr_metallic_roughness
			tex_base_color_view: cgltf.texture_view = pbr.base_color_texture
			tex_base_color :=  tex_base_color_view.texture
			img_base_color := tex_base_color.image_
			fmt.println(img_base_color.mime_type)
			img_buffer_view := img_base_color.buffer_view
			img_buffer := img_buffer_view.buffer
			fmt.println(img_buffer)

			data_ptr := ([^]u8)(img_buffer.data)
			img_io := SDL.IOFromConstMem(&data_ptr[img_buffer_view.offset], img_buffer_view.size)
			base_color = IMG.Load_IO(img_io, false)
		}
	}

	mesh: Mesh
	mesh.base_color_tex = ab_create_texture(gpu_device, base_color)
 	mesh.sampler = SDL.CreateGPUSampler(gpu_device, SDL.GPUSamplerCreateInfo{})
	mesh.buf_mesh_pos = meshbuffer_create(gpu_device, positions, {.VERTEX})
	mesh.buf_mesh_uv = meshbuffer_create(gpu_device, texcoords, {.VERTEX})
	mesh.buf_mesh_idx = meshbuffer_create(gpu_device, indices, {.INDEX})


	copy_cmd_buf := SDL.AcquireGPUCommandBuffer(gpu_device)
	copy_pass := SDL.BeginGPUCopyPass(copy_cmd_buf)
	ab_texture_upload(mesh.base_color_tex, copy_pass)
	meshbuffer_upload(mesh.buf_mesh_pos, copy_pass)
	meshbuffer_upload(mesh.buf_mesh_uv, copy_pass)
	meshbuffer_upload(mesh.buf_mesh_idx, copy_pass)
	SDL.EndGPUCopyPass(copy_pass)
	copy_submit_result := SDL.SubmitGPUCommandBuffer(copy_cmd_buf)

	return mesh
}

mesh_draw :: proc(render_pass: ^SDL.GPURenderPass, mesh: Mesh) {

	bindings := []SDL.GPUBufferBinding{
		{ buffer = mesh.buf_mesh_pos.gpu_buffer, offset = 0 },
		{ buffer = mesh.buf_mesh_uv.gpu_buffer, offset = 0 },
	}

	SDL.BindGPUVertexBuffers(render_pass, 0, &bindings[0], u32(len(bindings)))
	SDL.BindGPUIndexBuffer(render_pass, {mesh.buf_mesh_idx.gpu_buffer, 0}, ._32BIT)

	sampler_bindings := []SDL.GPUTextureSamplerBinding {
		{
			texture = mesh.base_color_tex.texture,
			sampler = mesh.sampler,
		}
	}
	SDL.BindGPUFragmentSamplers(render_pass, 0, &sampler_bindings[0], u32(len(sampler_bindings)))

	// SDL.DrawGPUPrimitives(render_pass, u32(len(indices)), 1, 0, 0)
	SDL.DrawGPUIndexedPrimitives(render_pass, mesh.buf_mesh_idx.size, 1, 0, 0, 0)
	// SDL.DrawGPUPrimitives(render_pass, 12, 1, 0, 0)
}