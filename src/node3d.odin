
package main

import mikk "mikktspace"

import SDL "vendor:sdl3"
import IMG "vendor:sdl3/image"
import "vendor:cgltf"

import "core:math/linalg"
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
	buf_mesh_color: MeshBuffer,
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
			make_tangents :: proc(vertices: MeshBuffer, uvs: MeshBuffer, indices: MeshBuffer, normals: MeshBuffer) -> []hlsl.float4 {
				log.info("making tangents")
				data_pos := slice.reinterpret([]hlsl.float3, vertices.data.([]f32))
				data_tex := slice.reinterpret([]hlsl.float2, uvs.data.([]f32))
				data_normal := slice.reinterpret([]hlsl.float3, normals.data.([]f32))
				log.info("   data_pos ", len(data_pos))
				data_idx := indices.data.([]u32)
				num_indices := len(data_idx)
				log.info("   num indices ", num_indices)
				buf_tangents := make([]hlsl.float4, len(data_pos))

				MeshDataForTangents :: struct {
					num_faces: int,
					vertices: []hlsl.float3,
					normals: []hlsl.float3,
					indices: []u32,
					uvs: []hlsl.float2,
					tangents: []hlsl.float4,
				}

				mesh_data := MeshDataForTangents {
					num_faces = len(data_idx) / 3,
					vertices = data_pos,
					normals = data_normal,
					indices = data_idx,
					uvs = data_tex,
					tangents = buf_tangents,
				}


				get_num_faces ::            proc(pContext: ^mikk.Context) -> int {
					mesh_data := (^MeshDataForTangents)(pContext.user_data)
					return mesh_data.num_faces
				}
				get_num_vertices_of_face :: proc(pContext: ^mikk.Context, iFace: int) -> int {
					return 3
				}
				get_position ::             proc(pContext: ^mikk.Context, iFace: int, iVert: int) -> [3]f32 {
					mesh_data := (^MeshDataForTangents)(pContext.user_data)
					return mesh_data.vertices[mesh_data.indices[(iFace*3)+iVert]]
				}
				get_normal ::               proc(pContext: ^mikk.Context, iFace: int, iVert: int) -> [3]f32 {
					mesh_data := (^MeshDataForTangents)(pContext.user_data)
					return mesh_data.normals[mesh_data.indices[(iFace*3)+iVert]]
				}
				get_tex_coord ::            proc(pContext: ^mikk.Context, iFace: int, iVert: int) -> [2]f32 {
					mesh_data := (^MeshDataForTangents)(pContext.user_data)
					return mesh_data.uvs[mesh_data.indices[(iFace*3)+iVert]]
				}
				set_t_space_basic ::        proc(pContext: ^mikk.Context, fvTangent: [3]f32, fSign: f32, iFace: int, iVert: int) {
					mesh_data := (^MeshDataForTangents)(pContext.user_data)
					mesh_data.tangents[mesh_data.indices[(iFace*3)+iVert]] = {fvTangent.x, fvTangent.y, fvTangent.z, fSign}
				}

				interface := mikk.Interface {
					get_num_faces = get_num_faces,
					get_num_vertices_of_face = get_num_vertices_of_face,
					get_position = get_position,
					get_normal = get_normal,
					get_tex_coord = get_tex_coord,
					set_t_space_basic = set_t_space_basic,
				}

				ctx := mikk.Context {
					interface = &interface,
					user_data = &mesh_data,
				}

				ok := mikk.generate_tangents(&ctx)

				return buf_tangents
			}
			buf_tangents := make_tangents(mesh.buf_mesh_pos, mesh.buf_mesh_uv, mesh.buf_mesh_idx, mesh.buf_mesh_normal)
			mesh.buf_mesh_tangent = meshbuffer_create(gpu_device, buf_tangents, {.VERTEX})
		}


		mat := primitive.material
		if mat.has_pbr_metallic_roughness {
			pbr := mat.pbr_metallic_roughness

			base_color := load_cgltf_texture(pbr.base_color_texture)
			mesh.base_color_tex = ab_create_texture(gpu_device, base_color)

			metallic_roughness_texture := load_cgltf_texture(pbr.metallic_roughness_texture)
			mesh.metal_rough_tex = ab_create_texture(gpu_device,  metallic_roughness_texture)

			normal_texture := load_cgltf_texture(mat.normal_texture)
			mesh.normal_tex = ab_create_texture(gpu_device,  normal_texture)

			load_cgltf_texture :: proc(tex_view: cgltf.texture_view) -> ^SDL.Surface {

				image := tex_view.texture.image_
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
	SDL.DrawGPUIndexedPrimitives(render_pass, mesh.buf_mesh_idx.size/4, 1, 0, 0, 0)
	// SDL.DrawGPUPrimitives(render_pass, 12, 1, 0, 0)
}

mesh_draw_verts :: proc(render_pass: ^SDL.GPURenderPass, mesh: Mesh) {

	bindings := []SDL.GPUBufferBinding{
		{ buffer = mesh.buf_mesh_pos.gpu_buffer, offset = 0 },
		{ buffer = mesh.buf_mesh_uv.gpu_buffer, offset = 0 },
		{ buffer = mesh.buf_mesh_color.gpu_buffer, offset = 0 },
		{ buffer = mesh.buf_mesh_normal.gpu_buffer, offset = 0 },
		{ buffer = mesh.buf_mesh_tangent.gpu_buffer, offset = 0 },
	}

	SDL.BindGPUVertexBuffers(render_pass, 0, &bindings[0], u32(len(bindings)))
	SDL.DrawGPUPrimitives(render_pass, mesh.buf_mesh_pos.size/4, 1, 0, 0)
}

mesh_from_line :: proc(gpu_device: ^SDL.GPUDevice, line: LinePrimitive) -> Mesh {
	mesh: Mesh

	mesh.buf_mesh_pos = meshbuffer_create(gpu_device, line.positions[:], {.VERTEX})
	mesh.buf_mesh_normal = meshbuffer_create(gpu_device, line.normals[:], {.VERTEX})
	mesh.buf_mesh_tangent = meshbuffer_create(gpu_device, line.tangents[:], {.VERTEX})
	mesh.buf_mesh_uv = meshbuffer_create(gpu_device, line.texcoords[:], {.VERTEX})
	mesh.buf_mesh_color = meshbuffer_create(gpu_device, line.colors[:], {.VERTEX})

	copy_cmd_buf := SDL.AcquireGPUCommandBuffer(gpu_device)
	copy_pass := SDL.BeginGPUCopyPass(copy_cmd_buf)
	meshbuffer_upload(mesh.buf_mesh_pos, copy_pass)
	meshbuffer_upload(mesh.buf_mesh_normal, copy_pass)
	meshbuffer_upload(mesh.buf_mesh_tangent, copy_pass)
	meshbuffer_upload(mesh.buf_mesh_uv, copy_pass)
	meshbuffer_upload(mesh.buf_mesh_color, copy_pass)
	log.info("positions", line.positions)
	log.info("tangents ", line.tangents)
	log.info("colors   ", line.colors)
	SDL.EndGPUCopyPass(copy_pass)
	copy_submit_result := SDL.SubmitGPUCommandBuffer(copy_cmd_buf)

	return mesh
}


LineVertex :: struct {
	position: hlsl.float3,
	normal: hlsl.float3,
	texcoord: hlsl.float2,
	color: hlsl.float4,
}

LinePrimitive :: struct {
	positions: [dynamic]hlsl.float3,
	normals: [dynamic]hlsl.float3,
	tangents: [dynamic]hlsl.float3,
	texcoords: [dynamic]hlsl.float2,
	colors: [dynamic]hlsl.float4,
}

primitive_append_vertex :: proc(using primitive: ^LinePrimitive, vert: LineVertex) {

	num_verts := len(positions)
	tangent_new: hlsl.float3

	if num_verts > 2 {
		before_last_position := positions[num_verts-4]
		new_last_tangent := linalg.normalize(vert.position - before_last_position)
		tangents[num_verts-2] = new_last_tangent
		tangents[num_verts-2] = new_last_tangent

		last_position := positions[num_verts-2]
		tangent_new = linalg.normalize(vert.position - last_position)
	} else if num_verts == 2 {
		existing_position := positions[0]
		tangent_new = linalg.normalize(vert.position - existing_position)
		tangents[0] = tangent_new
		tangents[1] = tangent_new
	}

	append(&tangents, tangent_new)
	append(&tangents, tangent_new)

	append(&positions, vert.position)
	append(&positions, vert.position)
	append(&normals, vert.normal)
	append(&normals, vert.normal)
	append(&texcoords, [2]f32{vert.texcoord.x, 0})
	append(&texcoords, [2]f32{vert.texcoord.x, 1})
	append(&colors, vert.color)
	append(&colors, vert.color)
}

primitive_delete :: proc(using primitive: LinePrimitive) {
	delete(positions)
	delete(normals)
	delete(tangents)
	delete(texcoords)
	delete(colors)
}
