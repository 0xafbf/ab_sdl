
package main

import SDL "vendor:sdl3"
import IMG "vendor:sdl3/image"
import "vendor:cgltf"

import "core:math/linalg/hlsl"
import "core:fmt"
import "core:log"
import "core:slice"


vec2 :: [2]f32
vec3 :: [3]f32
vec4 :: [4]f32

Basis :: matrix[3,3]f32
Matrix3D :: matrix[4, 4]f32

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
	buf_mesh_normal: MeshBuffer,
	buf_mesh_tangent: MeshBuffer,
	buf_mesh_uv: MeshBuffer,
	buf_mesh_idx: MeshBuffer,
	base_color_tex: Texture,
	metal_rough_tex: Texture,
	normal_tex: Texture,
	sampler: ^SDL.GPUSampler,
}



mesh_free :: proc(mesh: ^Mesh, gpu: ^SDL.GPUDevice) {
	meshbuffer_destroy(gpu, &mesh.buf_mesh_pos)
	meshbuffer_destroy(gpu, &mesh.buf_mesh_uv)
	meshbuffer_destroy(gpu, &mesh.buf_mesh_idx)
}

mesh_load :: proc(path: cstring, gpu_device: ^SDL.GPUDevice) -> (mesh: Mesh) {

	data: ^cgltf.data
	result: cgltf.result

	data, result = cgltf.parse_file({}, path)
	assert(result == .success)
	load_result := cgltf.load_buffers({}, data, path)
	assert(load_result == .success)
	defer cgltf.free(data)

	scene := data.scene
	fmt.println("nodes ", len(scene.nodes))
	root := scene.nodes[0]
	root_mesh := root.mesh
	fmt.println("  mesh primitives:", len(root_mesh.primitives))
	for primitive in root_mesh.primitives {
		fmt.println("  primitive type:", primitive.type)
		for attribute in primitive.attributes {
			fmt.println("    attribute type:", attribute.type)

			num_floats := cgltf.accessor_unpack_floats(attribute.data, nil, 0)
			buffer := make([]f32, num_floats)
			num_floats = cgltf.accessor_unpack_floats(attribute.data, &buffer[0], num_floats)
			meshbuf := meshbuffer_create(gpu_device, buffer, {.VERTEX})
			meshbuf.data = buffer

			if attribute.type == .position {
				mesh.buf_mesh_pos = meshbuf
			} else if attribute.type == .normal {
				mesh.buf_mesh_normal = meshbuf
			} else if attribute.type == .tangent {
				mesh.buf_mesh_tangent = meshbuf
			} else if attribute.type == .texcoord {
				mesh.buf_mesh_uv = meshbuf
			} else {
				log.warn("unhandled buffer in mesh")
			}
		}


		num_indices := cgltf.accessor_unpack_indices(primitive.indices, nil, 4, 0)
		indices := make([]u32, num_indices)
		num_indices = cgltf.accessor_unpack_indices(primitive.indices, &indices[0], 4, num_indices)
		mesh.buf_mesh_idx = meshbuffer_create(gpu_device, indices, {.INDEX})
		mesh.buf_mesh_idx.data = indices

		if mesh.buf_mesh_tangent.size == 0 {
			make_tangents :: proc(vertices: MeshBuffer, uvs: MeshBuffer, indices: MeshBuffer) -> []hlsl.float3 {
				log.info("making tangents")
				data_pos := slice.reinterpret([]hlsl.float3, vertices.data.([]f32))
				data_tex := slice.reinterpret([]hlsl.float2, uvs.data.([]f32))
				log.info("   data_pos ", len(data_pos))
				data_idx := indices.data.([]u32)
				num_indices := len(data_idx)
				log.info("   num indices ", num_indices)
				buf_tangents := make([]hlsl.float3, len(data_pos))
				for idx := 0; idx < num_indices; idx += 3 {
					idx_0 := data_idx[idx]
					idx_1 := data_idx[idx + 1]
					idx_2 := data_idx[idx + 2]

					pos_0 := data_pos[idx_0]
					pos_1 := data_pos[idx_1]
					pos_2 := data_pos[idx_2]

					tex_0 := data_tex[idx_0]
					tex_1 := data_tex[idx_1]
					tex_2 := data_tex[idx_2]

					dpos_1 := pos_1 - pos_0
					dpos_2 := pos_2 - pos_0
					dtex_1 := tex_1 - tex_0
					dtex_2 := tex_2 - tex_0

					tex_det := (dtex_1.x * dtex_2.y - dtex_2.x * dtex_1.y)
					tangent := (dpos_1 * dtex_2.y - dpos_2 * dtex_1.y) / tex_det
					buf_tangents[idx_0] = tangent
					buf_tangents[idx_1] = tangent
					buf_tangents[idx_2] = tangent
				}
				return buf_tangents
			}
			buf_tangents := make_tangents(mesh.buf_mesh_pos, mesh.buf_mesh_uv, mesh.buf_mesh_idx)
			mesh.buf_mesh_tangent = meshbuffer_create(gpu_device, buf_tangents, {.VERTEX})
		}


		mat := primitive.material
		fmt.println("material: ", mat)
		if mat.has_pbr_metallic_roughness {
			pbr := mat.pbr_metallic_roughness

			base_color := load_cgltf_texture(pbr.base_color_texture)
			mesh.base_color_tex = ab_create_texture(gpu_device, base_color)

			metallic_roughness_texture := load_cgltf_texture(pbr.metallic_roughness_texture)
			mesh.metal_rough_tex = ab_create_texture(gpu_device,  metallic_roughness_texture)

			log.info("normal texture", mat.normal_texture)
			normal_texture := load_cgltf_texture(mat.normal_texture)
			mesh.normal_tex = ab_create_texture(gpu_device,  normal_texture)

			load_cgltf_texture :: proc(tex_view: cgltf.texture_view) -> ^SDL.Surface {

				image := tex_view.texture.image_
				log.info("image:", image)
				buffer_view := image.buffer_view
				buffer := buffer_view.buffer

				data_ptr := ([^]u8)(buffer.data)
				img_io := SDL.IOFromConstMem(&data_ptr[buffer_view.offset], buffer_view.size)
				img_surface := IMG.Load_IO(img_io, false)
				return img_surface
			}
		}
	}

 	mesh.sampler = SDL.CreateGPUSampler(gpu_device, SDL.GPUSamplerCreateInfo{})


	copy_cmd_buf := SDL.AcquireGPUCommandBuffer(gpu_device)
	copy_pass := SDL.BeginGPUCopyPass(copy_cmd_buf)
	ab_texture_upload(mesh.base_color_tex, copy_pass)
	ab_texture_upload(mesh.metal_rough_tex, copy_pass)
	ab_texture_upload(mesh.normal_tex, copy_pass)
	meshbuffer_upload(mesh.buf_mesh_pos, copy_pass)
	meshbuffer_upload(mesh.buf_mesh_normal, copy_pass)
	meshbuffer_upload(mesh.buf_mesh_tangent, copy_pass)
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
		{ buffer = mesh.buf_mesh_normal.gpu_buffer, offset = 0 },
		{ buffer = mesh.buf_mesh_tangent.gpu_buffer, offset = 0 },
	}

	SDL.BindGPUVertexBuffers(render_pass, 0, &bindings[0], u32(len(bindings)))
	SDL.BindGPUIndexBuffer(render_pass, {mesh.buf_mesh_idx.gpu_buffer, 0}, ._32BIT)

	sampler_bindings := []SDL.GPUTextureSamplerBinding {
		{
			texture = mesh.base_color_tex.texture,
			sampler = mesh.sampler,
		},
		{
			texture = mesh.metal_rough_tex.texture,
			sampler = mesh.sampler,
		},
		{
			texture = mesh.normal_tex.texture,
			sampler = mesh.sampler,
		},
	}
	SDL.BindGPUFragmentSamplers(render_pass, 0, &sampler_bindings[0], u32(len(sampler_bindings)))

	// SDL.DrawGPUPrimitives(render_pass, u32(len(indices)), 1, 0, 0)
	SDL.DrawGPUIndexedPrimitives(render_pass, mesh.buf_mesh_idx.size, 1, 0, 0, 0)
	// SDL.DrawGPUPrimitives(render_pass, 12, 1, 0, 0)
}
