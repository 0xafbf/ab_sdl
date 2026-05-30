package shaderc
import "core:c"

when ODIN_OS == .Windows {
	@(export) foreign import lib { "shaderc_shared.lib" }
} else {
	@(export) foreign import lib { "system:shaderc" }
}

source_language :: enum {
    glsl,
    hlsl
}

shader_kind :: enum {
    vertex_shader,
    fragment_shader,
    compute_shader,
    geometry_shader,
    tess_control_shader,
    tess_evaluation_shader,

    glsl_vertex_shader = vertex_shader,
    glsl_fragment_shader = fragment_shader,
    glsl_compute_shader = compute_shader,
    glsl_geometry_shader = geometry_shader,
    glsl_tess_control_shader = tess_control_shader,
    glsl_tess_evaluation_shader = tess_evaluation_shader,

    glsl_infer_from_source,

    glsl_default_vertex_shader,
    glsl_default_fragment_shader,
    glsl_default_compute_shader,
    glsl_default_geometry_shader,
    glsl_default_tess_control_shader,
    glsl_default_tess_evaluation_shader,

    spirv_assembly,
    raygen_shader,
    anyhit_shader,
    closesthit_shader,
    miss_shader,
    intersection_shader,
    callable_shader,
    glsl_raygen_shader = raygen_shader,
    glsl_anyhit_shader = anyhit_shader,
    glsl_closesthit_shader = closesthit_shader,
    glsl_miss_shader = miss_shader,
    glsl_intersection_shader = intersection_shader,
    glsl_callable_shader = callable_shader,
    glsl_default_raygen_shader,
    glsl_default_anyhit_shader,
    glsl_default_closesthit_shader,
    glsl_default_miss_shader,
    glsl_default_intersection_shader,
    glsl_default_callable_shader,
    task_shader,
    mesh_shader,
    glsl_task_shader = task_shader,
    glsl_mesh_shader = mesh_shader,
    glsl_default_task_shader,
    glsl_default_mesh_shader,
}

profile :: enum {
    profile_none,
    profile_core,
    profile_compatibility,
    profile_es,
}
  
// Optimization level.
optimization_level :: enum {
    optimization_level_zero,
    optimization_level_size, 
    optimization_level_performance,
}
  
// Resource limits.
limit :: enum {
    limit_max_lights,
    limit_max_clip_planes,
    limit_max_texture_units,
    limit_max_texture_coords,
    limit_max_vertex_attribs,
    limit_max_vertex_uniform_components,
    limit_max_varying_floats,
    limit_max_vertex_texture_image_units,
    limit_max_combined_texture_image_units,
    limit_max_texture_image_units,
    limit_max_fragment_uniform_components,
    limit_max_draw_buffers,
    limit_max_vertex_uniform_vectors,
    limit_max_varying_vectors,
    limit_max_fragment_uniform_vectors,
    limit_max_vertex_output_vectors,
    limit_max_fragment_input_vectors,
    limit_min_program_texel_offset,
    limit_max_program_texel_offset,
    limit_max_clip_distances,
    limit_max_compute_work_group_count_x,
    limit_max_compute_work_group_count_y,
    limit_max_compute_work_group_count_z,
    limit_max_compute_work_group_size_x,
    limit_max_compute_work_group_size_y,
    limit_max_compute_work_group_size_z,
    limit_max_compute_uniform_components,
    limit_max_compute_texture_image_units,
    limit_max_compute_image_uniforms,
    limit_max_compute_atomic_counters,
    limit_max_compute_atomic_counter_buffers,
    limit_max_varying_components,
    limit_max_vertex_output_components,
    limit_max_geometry_input_components,
    limit_max_geometry_output_components,
    limit_max_fragment_input_components,
    limit_max_image_units,
    limit_max_combined_image_units_and_fragment_outputs,
    limit_max_combined_shader_output_resources,
    limit_max_image_samples,
    limit_max_vertex_image_uniforms,
    limit_max_tess_control_image_uniforms,
    limit_max_tess_evaluation_image_uniforms,
    limit_max_geometry_image_uniforms,
    limit_max_fragment_image_uniforms,
    limit_max_combined_image_uniforms,
    limit_max_geometry_texture_image_units,
    limit_max_geometry_output_vertices,
    limit_max_geometry_total_output_components,
    limit_max_geometry_uniform_components,
    limit_max_geometry_varying_components,
    limit_max_tess_control_input_components,
    limit_max_tess_control_output_components,
    limit_max_tess_control_texture_image_units,
    limit_max_tess_control_uniform_components,
    limit_max_tess_control_total_output_components,
    limit_max_tess_evaluation_input_components,
    limit_max_tess_evaluation_output_components,
    limit_max_tess_evaluation_texture_image_units,
    limit_max_tess_evaluation_uniform_components,
    limit_max_tess_patch_components,
    limit_max_patch_vertices,
    limit_max_tess_gen_level,
    limit_max_viewports,
    limit_max_vertex_atomic_counters,
    limit_max_tess_control_atomic_counters,
    limit_max_tess_evaluation_atomic_counters,
    limit_max_geometry_atomic_counters,
    limit_max_fragment_atomic_counters,
    limit_max_combined_atomic_counters,
    limit_max_atomic_counter_bindings,
    limit_max_vertex_atomic_counter_buffers,
    limit_max_tess_control_atomic_counter_buffers,
    limit_max_tess_evaluation_atomic_counter_buffers,
    limit_max_geometry_atomic_counter_buffers,
    limit_max_fragment_atomic_counter_buffers,
    limit_max_combined_atomic_counter_buffers,
    limit_max_atomic_counter_buffer_size,
    limit_max_transform_feedback_buffers,
    limit_max_transform_feedback_interleaved_components,
    limit_max_cull_distances,
    limit_max_combined_clip_and_cull_distances,
    limit_max_samples,
    limit_max_mesh_output_vertices_nv,
    limit_max_mesh_output_primitives_nv,
    limit_max_mesh_work_group_size_x_nv,
    limit_max_mesh_work_group_size_y_nv,
    limit_max_mesh_work_group_size_z_nv,
    limit_max_task_work_group_size_x_nv,
    limit_max_task_work_group_size_y_nv,
    limit_max_task_work_group_size_z_nv,
    limit_max_mesh_view_count_nv,
    limit_max_mesh_output_vertices_ext,
    limit_max_mesh_output_primitives_ext,
    limit_max_mesh_work_group_size_x_ext,
    limit_max_mesh_work_group_size_y_ext,
    limit_max_mesh_work_group_size_z_ext,
    limit_max_task_work_group_size_x_ext,
    limit_max_task_work_group_size_y_ext,
    limit_max_task_work_group_size_z_ext,
    limit_max_mesh_view_count_ext,
    limit_max_dual_source_draw_buffers_ext,
}

uniform_kind :: enum {
    uniform_kind_image,
    uniform_kind_sampler,
    uniform_kind_texture,
    uniform_kind_buffer,
    uniform_kind_storage_buffer,
    uniform_kind_unordered_access_view,
}

include_result :: struct {
    source_name:cstring,
    source_name_length:uint,
    content:cstring,
    content_length:uint,
    user_data:rawptr,
}

target_env :: enum {
    shaderc_target_env_vulkan,
    shaderc_target_env_opengl,
    shaderc_target_env_opengl_compat,
    shaderc_target_env_webgpu,
    shaderc_target_env_default = shaderc_target_env_vulkan
}

env_version :: enum {
    shaderc_env_version_vulkan_1_0 = ((1 << 22)),
    shaderc_env_version_vulkan_1_1 = ((1 << 22) | (1 << 12)),
    shaderc_env_version_vulkan_1_2 = ((1 << 22) | (2 << 12)),
    shaderc_env_version_vulkan_1_3 = ((1 << 22) | (3 << 12)),
    shaderc_env_version_vulkan_1_4 = ((1 << 22) | (4 << 12)),
    shaderc_env_version_opengl_4_5 = 450,
    shaderc_env_version_webgpu,
}
  

spirv_version :: enum {
    shaderc_spirv_version_1_0 = 0x010000,
    shaderc_spirv_version_1_1 = 0x010100,
    shaderc_spirv_version_1_2 = 0x010200,
    shaderc_spirv_version_1_3 = 0x010300,
    shaderc_spirv_version_1_4 = 0x010400,
    shaderc_spirv_version_1_5 = 0x010500,
    shaderc_spirv_version_1_6 = 0x010600
}
  
include_type :: enum {
    include_type_relative,
    include_type_standard
}

compilation_status :: enum {
    shaderc_compilation_status_success = 0,
    shaderc_compilation_status_invalid_stage = 1,
    shaderc_compilation_status_compilation_error = 2,
    shaderc_compilation_status_internal_error = 3,
    shaderc_compilation_status_null_result_object = 4,
    shaderc_compilation_status_invalid_assembly = 5,
    shaderc_compilation_status_validation_error = 6,
    shaderc_compilation_status_transformation_error = 7,
    shaderc_compilation_status_configuration_error = 8,
}

compiler_t :: rawptr
compile_options_t :: rawptr
compilation_result_t :: rawptr

include_resolve_fn :: proc "c" (user_data:rawptr, requested_source:cstring, type:c.int, requesting_source:cstring, include_depth:uint)
include_result_release_fn :: proc "c" (user_data:rawptr, include_result:^include_result) 

@(default_calling_convention="c", link_prefix="shaderc_", require_results)
foreign lib {
    
    compiler_initialize :: proc() -> compiler_t ---
    compiler_release :: proc(compiler:compiler_t) ---

    compile_options_initialize :: proc() -> compile_options_t ---
    compile_options_clone :: proc(options:compile_options_t) -> compile_options_t ---
    compile_options_release :: proc(options:compile_options_t) ---
    compile_options_add_macro_definition :: proc(options:compile_options_t, name:cstring, name_length:uint, value:cstring, value_length:uint) --- 
    compile_options_set_source_language :: proc(options:compile_options_t, lang:source_language) ---
    compile_options_set_generate_debug_info :: proc(options:compile_options_t) ---
    compile_options_set_optimization_level :: proc(options:compile_options_t, level:optimization_level) ---
    compile_options_set_forced_version_profile :: proc(options:compile_options_t, version:int, profile:profile) ---
    compile_options_set_include_callbacks :: proc(options:compile_options_t, resolver:include_resolve_fn, result_releaser:include_result_release_fn, user_data:rawptr) --- 
    compile_options_set_suppress_warnings :: proc(options:compile_options_t) ---
    compile_options_set_target_env :: proc(options:compile_options_t, target:target_env, version:u32) --- 
    compile_options_set_target_spirv :: proc(options:compile_options_t, version:spirv_version) ---
    compile_options_set_warnings_as_errors :: proc(options:compile_options_t) ---
    compile_options_set_limit :: proc(options:compile_options_t, limit:limit, value:int) ---
    compile_options_set_auto_bind_uniforms :: proc(options:compile_options_t, auto_bind:bool) ---
    compile_options_set_auto_combined_image_sampler :: proc(options:compile_options_t, upgrade:bool) --- 
    compile_options_set_hlsl_io_mapping :: proc(options:compile_options_t, hlsl_iomap:bool) ---
    compile_options_set_hlsl_offsets :: proc(options:compile_options_t, hlsl_offsets:bool) ---
    compile_options_set_binding_base :: proc(options:compile_options_t, kind:uniform_kind, base:u32) ---
    compile_options_set_binding_base_for_stage :: proc(options:compile_options_t, shader_kind:shader_kind, uniform_kind:uniform_kind, base:u32) --- 
    compile_options_set_preserve_bindings :: proc(options:compile_options_t, preserve_bindings:bool) --- 
    compile_options_set_auto_map_locations :: proc(options:compile_options_t, auto_map:bool) ---
    compile_options_set_hlsl_register_set_and_binding_for_stage :: proc(options:compile_options_t, kind:shader_kind, reg:cstring, set:cstring, binding:cstring) ---
    compile_options_set_hlsl_register_set_and_binding :: proc(options:compile_options_t, reg:cstring, set:cstring, binding:cstring) ---
    compile_options_set_hlsl_functionality1 :: proc(options:compile_options_t, enable:bool) ---
    compile_options_set_hlsl_16bit_types :: proc(options:compile_options_t, enable:bool) ---
    compile_options_set_vulkan_rules_relaxed :: proc(options:compile_options_t, enable:bool) ---
    compile_options_set_invert_y :: proc(options:compile_options_t, enable:bool)  ---
    compile_options_set_nan_clamp :: proc(options:compile_options_t, enable:bool)  ---
    
    compile_into_spv :: proc(compiler:compiler_t, source_text:cstring, source_text_size:uint, shader_kind:shader_kind, input_file_name:cstring, entry_point_name:cstring, additional_options:compile_options_t) -> compilation_result_t ---
    compile_into_spv_assembly :: proc(compiler:compiler_t, source_text:cstring, source_text_size:uint, shader_kind:shader_kind, input_file_name:cstring, entry_point_name:cstring, additional_options:compile_options_t) -> compilation_result_t ---
    compile_into_preprocessed_text :: proc(compiler:compiler_t, source_text:cstring, source_text_size:uint, shader_kind:shader_kind, input_file_name:cstring, entry_point_name:cstring, additional_options:compile_options_t) -> compilation_result_t ---
    
    assemble_into_spv :: proc(compiler:compiler_t, source_assembly:cstring, source_assembly_size:uint, additional_options:compile_options_t) -> compilation_result_t ---

    result_release :: proc(result:compilation_result_t)  ---
    result_get_length :: proc(result:compilation_result_t) -> uint ---
    result_get_num_warnings :: proc(result:compilation_result_t) -> uint ---
    result_get_num_errors :: proc(result:compilation_result_t) -> uint ---
    result_get_compilation_status :: proc(compilation_result_t) -> compilation_status  ---
    result_get_bytes :: proc(result:compilation_result_t) -> [^]u8  ---
    result_get_error_message :: proc(result:compilation_result_t) -> cstring  ---

    get_spv_version :: proc(version:^c.uint, revision:^c.uint)  ---
    parse_version_profile :: proc(str:cstring, version:^c.int, profile:^profile) -> bool ---

}