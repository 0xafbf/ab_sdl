
package main

import mikk "vendor/mikktspace"

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
	children: []^Node3D,
}

MeshInstance3D :: struct {
	node: ^Node3D,
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

PrimitiveAttributeType :: enum {
	POSITION,
	NORMAL,
	TANGENT,
	COLOR,
	TEXCOORD,
	TEXCOORD1,
}

PrimitiveAttribute :: struct {
	buffer: MeshBuffer,
}

MeshPrimitive :: struct {
	attributes: [PrimitiveAttributeType]PrimitiveAttribute,
	indices: MeshBuffer,
	material: ^MaterialPBR,
}

MaterialPBR :: struct {
	base_color_tex: Texture,
	metal_rough_tex: Texture,
	normal_tex: Texture,
	sampler: ^SDL.GPUSampler,
}

Mesh :: struct {
	primitives: []MeshPrimitive,

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

gltf_context :: struct {
	materials: []^MaterialPBR,
	meshes: []^Mesh,
	copy_pass: ^SDL.GPUCopyPass,
	normal_tex: Texture,
	white_tex: Texture,
}


scene_load :: proc(path: cstring, gpu_device: ^SDL.GPUDevice) -> (scene: Node3D, out_mesh_instances: []MeshInstance3D) {
	data: ^cgltf.data
	result: cgltf.result

	data, result = cgltf.parse_file({}, path)
	assert(result == .success)
	load_result := cgltf.load_buffers({}, data, path)
	assert(load_result == .success)
	defer cgltf.free(data)

	ctx := new(gltf_context)

	ctx.materials = make([]^MaterialPBR, len(data.materials))
	gltf_meshes := data.meshes
	ctx.meshes = make([]^Mesh, len(gltf_meshes))

	white := [][4]f32 {{1.0, 1.0, 1.0, 1.0}}
	normal := [][4]f32 {{0.5, 0.5, 1.0, 1.0}}

	ctx.white_tex = ab_create_texture_raw(gpu_device, {1, 1}, white)
	ctx.normal_tex = ab_create_texture_raw(gpu_device, {1, 1}, normal)

	copy_cmd_buf := SDL.AcquireGPUCommandBuffer(gpu_device)
	ctx.copy_pass = SDL.BeginGPUCopyPass(copy_cmd_buf)

	ab_texture_upload(ctx.white_tex, ctx.copy_pass)
	ab_texture_upload(ctx.normal_tex, ctx.copy_pass)

	assert(len(data.scenes) == 1)
	assert(&data.scenes[0] == data.scene)

	gltf_scene := data.scene
	nodes := gltf_scene.nodes
	fmt.println("nodes ", len(nodes))

	mesh_instances: [dynamic]MeshInstance3D
	root_node := Node3D{}
	root_children := make([]^Node3D, len(nodes))
	root_node.children = root_children

	root_node.transform = PosRotScale {
		scale = 1,
		rotation = {1.57, 0, 0},
	}
	root_trs := root_node.transform.(PosRotScale)
	root_rot := root_trs.rotation
	root_quat := linalg.quaternion_from_euler_angles(root_rot.x, root_rot.y, root_rot.z, .XYZ)
	root_node.global_transform = linalg.matrix4_from_trs(root_trs.position, root_quat, root_trs.scale)

	idx := 0
	for gltf_node in nodes {
		fmt.println("loading node", idx)
		ab_node := new(Node3D)
		if gltf_node.mesh != nil {
			mesh_idx := (uintptr(gltf_node.mesh) - uintptr(&data.meshes[0])) / size_of(cgltf.mesh)
			if ctx.meshes[mesh_idx] == nil {
				ctx.meshes[mesh_idx] = load_mesh(data, ctx, gltf_node.mesh, gpu_device)
			}
			ab_mesh := ctx.meshes[mesh_idx]
			append(&mesh_instances, MeshInstance3D{ab_node, ab_mesh})
		}
		trs := PosRotScale {
			scale = 1,
		}

		if gltf_node.has_translation {
			trs.position = gltf_node.translation
		}
		if gltf_node.has_rotation {
			rot := gltf_node.rotation
			quat := quaternion(x=rot.x, y=rot.y, z=rot.z, w=rot.w)
			rx, ry, rz := linalg.euler_angles_from_quaternion(quat, .XYZ)
			trs.rotation = {rx, ry, rz}
		}
		if gltf_node.has_scale {
			trs.scale = gltf_node.scale
		}

		fmt.println(trs)
		ab_node.transform = trs


		rot := trs.rotation
		quat := linalg.quaternion_from_euler_angles(rot.x, rot.y, rot.z, .XYZ)

		node_mat := linalg.matrix4_from_trs(trs.position, quat, trs.scale)
		ab_node.global_transform = root_node.global_transform * node_mat

		root_children[idx] = ab_node
		idx += 1
	}

	SDL.EndGPUCopyPass(ctx.copy_pass)
	copy_submit_result := SDL.SubmitGPUCommandBuffer(copy_cmd_buf)

	return root_node, mesh_instances[:]
}

node3d_draw :: proc(instances: []MeshInstance3D, cmd_buf: ^SDL.GPUCommandBuffer, render_pass: ^SDL.GPURenderPass) {
	for instance in instances {
		node := instance.node
		SDL.PushGPUVertexUniformData(cmd_buf, 1, &node.global_transform, size_of(node.global_transform))

		mesh := instance.mesh
		for primitive in mesh.primitives {
			primitive_draw(render_pass, primitive)
		}
	}
}


load_mesh :: proc(data: ^cgltf.data, ctx: ^gltf_context, mesh: ^cgltf.mesh, gpu_device: ^SDL.GPUDevice) -> ^Mesh{
	new_mesh := new(Mesh)
	num_primitives := len(mesh.primitives)
	new_mesh.primitives = make([]MeshPrimitive, num_primitives)
	idx := 0
	for gltf_primitive in mesh.primitives {
		fmt.println("    loading primitive", idx)
		new_primitive: MeshPrimitive
		for gltf_attribute in gltf_primitive.attributes {
			attribute_type: PrimitiveAttributeType
			if gltf_attribute.type == .position {      attribute_type = .POSITION }
			else if gltf_attribute.type == .normal {   attribute_type = .NORMAL }
			else if gltf_attribute.type == .tangent {  attribute_type = .TANGENT }
			else if gltf_attribute.type == .texcoord { attribute_type = .TEXCOORD }
			else if gltf_attribute.type == .color {    attribute_type = .COLOR }

			fmt.println("        loading primitive", gltf_attribute.type, attribute_type)

			new_attribute: PrimitiveAttribute

			num_floats := cgltf.accessor_unpack_floats(gltf_attribute.data, nil, 0)
			buffer := make([]f32, num_floats)
			num_floats = cgltf.accessor_unpack_floats(gltf_attribute.data, &buffer[0], num_floats)
			new_attribute.buffer = meshbuffer_create(gpu_device, buffer, {.VERTEX})
			new_attribute.buffer.data = buffer

			meshbuffer_upload(new_attribute.buffer, ctx.copy_pass)

			new_primitive.attributes[attribute_type] = new_attribute
		}

		fmt.println("    loading indices")

		num_indices := cgltf.accessor_unpack_indices(gltf_primitive.indices, nil, 4, 0)
		indices := make([]u32, num_indices)
		num_indices = cgltf.accessor_unpack_indices(gltf_primitive.indices, &indices[0], 4, num_indices)
		new_primitive.indices = meshbuffer_create(gpu_device, indices, {.INDEX})
		new_primitive.indices.data = indices
		meshbuffer_upload(new_primitive.indices, ctx.copy_pass)

		fmt.println("    generating tangents")
		if new_primitive.attributes[.TANGENT].buffer.size == 0 {
			buf_tangents := make_tangents(
				new_primitive.attributes[.POSITION].buffer.data.([]f32),
				new_primitive.attributes[.TEXCOORD].buffer.data.([]f32),
				new_primitive.indices.data.([]u32),
				new_primitive.attributes[.NORMAL].buffer.data.([]f32),
			)
			new_primitive.attributes[.TANGENT].buffer = meshbuffer_create(gpu_device, buf_tangents, {.VERTEX})
			meshbuffer_upload(new_primitive.attributes[.TANGENT].buffer, ctx.copy_pass)
		}


		fmt.println("    loading material")
		material_idx := (uintptr(gltf_primitive.material) - uintptr(raw_data(data.materials))) / size_of(cgltf.material)
		if ctx.materials[material_idx] == nil {
			ctx.materials[material_idx] = load_material(data, ctx, gltf_primitive.material, gpu_device)
		}
		new_primitive.material = ctx.materials[material_idx]
		fmt.println("    end loading material")

		new_mesh.primitives[idx] = new_primitive
		idx += 1

	}

	return new_mesh
}

load_material :: proc(data: ^cgltf.data, ctx: ^gltf_context, mat: ^cgltf.material, gpu_device: ^SDL.GPUDevice) -> ^MaterialPBR{
	new_mat := new(MaterialPBR)
	assert(bool(mat.has_pbr_metallic_roughness))
	pbr := mat.pbr_metallic_roughness

	if pbr.base_color_texture.texture != nil {
		base_color := load_cgltf_texture(pbr.base_color_texture)
		new_mat.base_color_tex = ab_create_texture(gpu_device, base_color, .R8G8B8A8_UNORM_SRGB)
		ab_texture_upload(new_mat.base_color_tex, ctx.copy_pass)
	} else {
		new_mat.base_color_tex = ctx.white_tex
	}

	if pbr.metallic_roughness_texture.texture != nil {
		metallic_roughness_texture := load_cgltf_texture(pbr.metallic_roughness_texture)
		new_mat.metal_rough_tex = ab_create_texture(gpu_device,  metallic_roughness_texture, .R8G8B8A8_UNORM)
		ab_texture_upload(new_mat.metal_rough_tex, ctx.copy_pass)
	} else {
		new_mat.metal_rough_tex = ctx.white_tex
	}

	if mat.normal_texture.texture != nil {
		normal_texture := load_cgltf_texture(mat.normal_texture)
		new_mat.normal_tex = ab_create_texture(gpu_device,  normal_texture, .R8G8B8A8_UNORM)
		ab_texture_upload(new_mat.normal_tex, ctx.copy_pass)
	} else {
		new_mat.normal_tex = ctx.normal_tex
	}

	new_mat.sampler = SDL.CreateGPUSampler(gpu_device, SDL.GPUSamplerCreateInfo{})


	return new_mat
}

load_cgltf_texture :: proc(tex_view: cgltf.texture_view) -> ^SDL.Surface {

	image := tex_view.texture.image_
	buffer_view := image.buffer_view
	buffer := buffer_view.buffer

	data_ptr := ([^]u8)(buffer.data)
	img_io := SDL.IOFromConstMem(&data_ptr[buffer_view.offset], buffer_view.size)
	img_surface := IMG.Load_IO(img_io, false)
	return img_surface
}

mesh_load :: proc(path: cstring, gpu_device: ^SDL.GPUDevice, correct: bool = false) -> (mesh: Mesh) {

	data: ^cgltf.data
	result: cgltf.result

	data, result = cgltf.parse_file({}, path)
	assert(result == .success)
	load_result := cgltf.load_buffers({}, data, path)
	assert(load_result == .success)
	defer cgltf.free(data)

	assert(len(data.scenes) == 1)
	assert(&data.scenes[0] == data.scene)

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
			buf_tangents := make_tangents(
				mesh.buf_mesh_pos.data.([]f32),
				mesh.buf_mesh_uv.data.([]f32),
				mesh.buf_mesh_idx.data.([]u32),
				mesh.buf_mesh_normal.data.([]f32),
			)
			mesh.buf_mesh_tangent = meshbuffer_create(gpu_device, buf_tangents, {.VERTEX})
		}
		if correct {
			new_pos := make([]f32, num_indices * 3)
			new_uv := make([]f32, num_indices * 2)
			new_normal := make([]f32, num_indices * 3)
			new_idx := make([]u32, num_indices)
			old_pos := mesh.buf_mesh_pos.data.([]f32)
			old_normal := mesh.buf_mesh_normal.data.([]f32)
			old_uv := mesh.buf_mesh_uv.data.([]f32)

			for idx in 0..<num_indices  {
				new_idx[idx] = u32(idx)
				vert_idx := indices[idx]
				new_pos[idx*3+0] = old_pos[vert_idx*3+0]
				new_pos[idx*3+1] = old_pos[vert_idx*3+1]
				new_pos[idx*3+2] = old_pos[vert_idx*3+2]

				new_normal[idx*3+0] = old_normal[vert_idx*3+0]
				new_normal[idx*3+1] = old_normal[vert_idx*3+1]
				new_normal[idx*3+2] = old_normal[vert_idx*3+2]

				new_uv[idx*2+0] = old_uv[vert_idx*2+0]
				new_uv[idx*2+1] = old_uv[vert_idx*2+1]
			}
			new_tangents := make_tangents(
				new_pos,
				new_uv,
				new_idx,
				new_normal,
			)

			mesh.buf_mesh_pos = meshbuffer_create(gpu_device, new_pos, {.VERTEX})
			mesh.buf_mesh_uv = meshbuffer_create(gpu_device, new_uv, {.VERTEX})
			mesh.buf_mesh_normal = meshbuffer_create(gpu_device, new_normal, {.VERTEX})
			mesh.buf_mesh_tangent = meshbuffer_create(gpu_device, new_tangents, {.VERTEX})
			mesh.buf_mesh_idx = meshbuffer_create(gpu_device, new_idx, {.INDEX})


		}


		mat := primitive.material
		if mat.has_pbr_metallic_roughness {
			pbr := mat.pbr_metallic_roughness

			base_color := load_cgltf_texture(pbr.base_color_texture)
			mesh.base_color_tex = ab_create_texture(gpu_device, base_color, .R8G8B8A8_UNORM_SRGB)

			metallic_roughness_texture := load_cgltf_texture(pbr.metallic_roughness_texture)
			mesh.metal_rough_tex = ab_create_texture(gpu_device,  metallic_roughness_texture, .R8G8B8A8_UNORM)

			normal_texture := load_cgltf_texture(mat.normal_texture)
			mesh.normal_tex = ab_create_texture(gpu_device,  normal_texture, .R8G8B8A8_UNORM)

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

make_tangents :: proc(vertices: []f32, uvs: []f32, indices: []u32, normals: []f32) -> []hlsl.float4 {
	log.info("making tangents")
	data_pos := slice.reinterpret([]hlsl.float3, vertices)
	data_tex := slice.reinterpret([]hlsl.float2, uvs)
	data_normal := slice.reinterpret([]hlsl.float3, normals)
	log.info("   data_pos ", len(data_pos))
	data_idx := indices
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

primitive_draw :: proc(render_pass: ^SDL.GPURenderPass, primitive: MeshPrimitive) {
	//SDL.BindGPUGraphicsPipeline(render_pass, shader.pipeline)
	mat := primitive.material
	sampler_bindings := []SDL.GPUTextureSamplerBinding {
		{
			texture = mat.base_color_tex.texture,
			sampler = mat.sampler,
		},
		{
			texture = mat.metal_rough_tex.texture,
			sampler = mat.sampler,
		},
		{
			texture = mat.normal_tex.texture,
			sampler = mat.sampler,
		},
	}
	SDL.BindGPUFragmentSamplers(render_pass, 0, &sampler_bindings[0], u32(len(sampler_bindings)))
	/*
	if mat.base_color_tex.texture != nil {
		SDL.BindGPUFragmentSamplers(render_pass, 0, &sampler_bindings[0], 1)
	}
	if mat.metal_rough_tex.texture != nil {
		SDL.BindGPUFragmentSamplers(render_pass, 1, &sampler_bindings[1], 1)
	}
	if mat.normal_tex.texture != nil {
		SDL.BindGPUFragmentSamplers(render_pass, 2, &sampler_bindings[2], 1)
	}
	*/

	bindings := []SDL.GPUBufferBinding{
		{ buffer = primitive.attributes[.POSITION].buffer.gpu_buffer, offset = 0 },
		{ buffer = primitive.attributes[.TEXCOORD].buffer.gpu_buffer, offset = 0 },
		{ buffer = primitive.attributes[.NORMAL].buffer.gpu_buffer, offset = 0 },
		{ buffer = primitive.attributes[.TANGENT].buffer.gpu_buffer, offset = 0 },
	}

	SDL.BindGPUVertexBuffers(render_pass, 0, &bindings[0], u32(len(bindings)))
	SDL.BindGPUIndexBuffer(render_pass, {primitive.indices.gpu_buffer, 0}, ._32BIT)

	// SDL.DrawGPUPrimitives(render_pass, u32(len(indices)), 1, 0, 0)
	SDL.DrawGPUIndexedPrimitives(render_pass, primitive.indices.size/4, 1, 0, 0, 0)
	// SDL.DrawGPUPrimitives(render_pass, 12, 1, 0, 0)
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
