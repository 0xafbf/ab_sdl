
package main

import SDL "vendor:sdl3"
import mui "vendor:microui"
import "vendor:cgltf"

import "core:math"
import "core:math/linalg"
import hlm "core:math/linalg/hlsl"
import "core:fmt"
import "core:mem"


WindowData :: struct {
	mui_ctx: ^mui.Context,
	size: [2]u32,
	format: SDL.GPUTextureFormat,
	ui_rect_pipeline: ^SDL.GPUGraphicsPipeline,
	ui_rect_tex_pipeline: ^SDL.GPUGraphicsPipeline,
	ui_texture: ^SDL.GPUTexture,
	ui_sampler: ^SDL.GPUSampler,
	pending_transfer: ^SDL.GPUTransferBuffer,
}

DrawContext :: struct {
	gpu_device: ^SDL.GPUDevice,
	cmd_buf: ^SDL.GPUCommandBuffer,
	swapchain_tex: ^SDL.GPUTexture,
	render_pass: ^SDL.GPURenderPass
}

ui_load_pipelines :: proc(window: ^WindowData, gpu_device: ^SDL.GPUDevice) {

	ui_rect_shader_vert := LoadShader(gpu_device, "Content/Shaders/ui/rect.vert.spv", .VERTEX, 0, 0, 0, 1)
	ui_rect_shader_frag := LoadShader(gpu_device, "Content/Shaders/ui/rect.frag.spv", .FRAGMENT, 0, 0, 0, 1)


	color_target_desc := []SDL.GPUColorTargetDescription{{
		format = window.format
	}}

	ui_rect_pipeline_info := SDL.GPUGraphicsPipelineCreateInfo {
		vertex_shader = ui_rect_shader_vert,
		fragment_shader = ui_rect_shader_frag,
		primitive_type = .TRIANGLESTRIP,
		target_info = {
			num_color_targets = 1,
			color_target_descriptions = raw_data(color_target_desc),
		}
	}

	window.ui_rect_pipeline = SDL.CreateGPUGraphicsPipeline(gpu_device, ui_rect_pipeline_info)

	SDL.ReleaseGPUShader(gpu_device, ui_rect_shader_vert)
	SDL.ReleaseGPUShader(gpu_device, ui_rect_shader_frag)

	ui_rect_tex_shader_vert := LoadShader(gpu_device, "Content/Shaders/ui/rect_tex.vert.spv", .VERTEX, 0, 0, 0, 1)
	ui_rect_tex_shader_frag := LoadShader(gpu_device, "Content/Shaders/ui/rect_tex.frag.spv", .FRAGMENT, 1, 0, 0, 1)

	color_target_desc_tex := []SDL.GPUColorTargetDescription{{
		format = window.format,
		blend_state = {
			src_color_blendfactor = .SRC_ALPHA,
			dst_color_blendfactor = .ONE_MINUS_SRC_ALPHA,
			color_blend_op = .ADD,
			src_alpha_blendfactor = .SRC_ALPHA,
			dst_alpha_blendfactor = .ONE_MINUS_SRC_ALPHA,
			alpha_blend_op = .ADD,
			enable_blend = true,
		}
	}}

	ui_rect_tex_pipeline_info := SDL.GPUGraphicsPipelineCreateInfo {
		vertex_shader = ui_rect_tex_shader_vert,
		fragment_shader = ui_rect_tex_shader_frag,
		primitive_type = .TRIANGLESTRIP,
		target_info = {
			num_color_targets = 1,
			color_target_descriptions = raw_data(color_target_desc_tex),
		}
	}

	window.ui_rect_tex_pipeline = SDL.CreateGPUGraphicsPipeline(gpu_device, ui_rect_tex_pipeline_info)
	fmt.println("release shaders")

	SDL.ReleaseGPUShader(gpu_device, ui_rect_tex_shader_vert)
	SDL.ReleaseGPUShader(gpu_device, ui_rect_tex_shader_frag)



	window.ui_texture = SDL.CreateGPUTexture(gpu_device, SDL.GPUTextureCreateInfo{
		type = .D2,
		format = .A8_UNORM,
		usage = {.SAMPLER},
		width = mui.DEFAULT_ATLAS_WIDTH,
		height = mui.DEFAULT_ATLAS_HEIGHT,
		layer_count_or_depth = 1,
		num_levels = 1,
	})

	window.ui_sampler = SDL.CreateGPUSampler(gpu_device, SDL.GPUSamplerCreateInfo{})

	buffer_size: int = mui.DEFAULT_ATLAS_WIDTH * mui.DEFAULT_ATLAS_HEIGHT
	transfer_buffer := SDL.CreateGPUTransferBuffer(gpu_device, SDL.GPUTransferBufferCreateInfo{
		usage = .UPLOAD,
		size = u32(buffer_size),
	})
	window.pending_transfer = transfer_buffer

	transfer_buffer_mem := SDL.MapGPUTransferBuffer(gpu_device, transfer_buffer, false)
	mem.copy_non_overlapping(transfer_buffer_mem, &mui.default_atlas_alpha[0], buffer_size);
	SDL.UnmapGPUTransferBuffer(gpu_device, transfer_buffer)


}

ui_unload_pipelines :: proc(window: ^WindowData, gpu_device: ^SDL.GPUDevice) {
	SDL.ReleaseGPUGraphicsPipeline(gpu_device, window.ui_rect_pipeline)
	SDL.ReleaseGPUGraphicsPipeline(gpu_device, window.ui_rect_tex_pipeline)
	window.ui_rect_pipeline = nil
	window.ui_rect_pipeline = nil
	SDL.ReleaseGPUTexture(gpu_device, window.ui_texture)
	SDL.ReleaseGPUSampler(gpu_device, window.ui_sampler)

}

draw_mui :: proc(window: ^WindowData, in_draw_ctx: DrawContext) {
	draw_ctx := in_draw_ctx
	if window.pending_transfer != nil {
		copy_pass := SDL.BeginGPUCopyPass(draw_ctx.cmd_buf)
		SDL.UploadToGPUTexture(copy_pass, SDL.GPUTextureTransferInfo {
			transfer_buffer = window.pending_transfer,
			pixels_per_row = mui.DEFAULT_ATLAS_WIDTH,
			rows_per_layer = mui.DEFAULT_ATLAS_HEIGHT,
		}, SDL.GPUTextureRegion {
			texture = window.ui_texture, 
			x = 0, y = 0, 
			w = mui.DEFAULT_ATLAS_WIDTH, h = mui.DEFAULT_ATLAS_HEIGHT, d = 1,
		}, false)
		SDL.EndGPUCopyPass(copy_pass)
		SDL.ReleaseGPUTransferBuffer(draw_ctx.gpu_device, window.pending_transfer)
		window.pending_transfer = nil
	}

	mui_ctx: ^mui.Context = window.mui_ctx
	mui_cmd: ^mui.Command



	color_target_info := SDL.GPUColorTargetInfo {
		texture = draw_ctx.swapchain_tex,
		load_op = .LOAD,
		store_op = .STORE,
	}

	render_pass := SDL.BeginGPURenderPass(draw_ctx.cmd_buf, &color_target_info, 1, nil)
	draw_ctx.render_pass = render_pass

	for mui.next_command(mui_ctx, &mui_cmd) {
		switch e in mui_cmd.variant {
		case ^mui.Command_Jump: fmt.println("Command_Jump")
		case ^mui.Command_Clip:
			sdl_rect := SDL.Rect {e.rect.x, e.rect.y, e.rect.w, e.rect.h}
			SDL.SetGPUScissor(render_pass, sdl_rect)
		case ^mui.Command_Rect: 
			window_draw_rect(window^, draw_ctx, e.rect, e.color)
		case ^mui.Command_Icon:
			icon := e.id
			atlas_rect := mui.default_atlas[icon]
			window_draw_textured_rect(window^, draw_ctx, e.rect, e.color, atlas_rect)


		case ^mui.Command_Text: 
			// Command_Text :: struct { 
			// 	using command: Command, 
			// 	font:  Font, 
			// 	pos:   Vec2, 
			// 	color: Color, 
			// 	str:   string, /* + string data (VLA) */ 
			// }
			text := e.str
			current_pos := e.pos
			atlas := mui.default_atlas
			for idx in 0 ..< len(text) {
				char := text[idx]
				atlas_rect := atlas[u8(mui.DEFAULT_ATLAS_FONT) + char]
				rect: mui.Rect = {current_pos.x, current_pos.y, atlas_rect.w, atlas_rect.h}
				current_pos.x += atlas_rect.w
				window_draw_textured_rect(window^, draw_ctx, rect, e.color, atlas_rect)
			}
		}
	}

	SDL.EndGPURenderPass(draw_ctx.render_pass)

}


sdl_to_microui_btn :: proc(sdl_button: u8) -> mui.Mouse {
	switch sdl_button {
		case 1: return mui.Mouse.LEFT
		case 2: return mui.Mouse.MIDDLE
		case 3: return mui.Mouse.RIGHT
		case: return mui.Mouse(4)
	}
}

mui_process_sdl_event :: proc(mui_ctx: ^mui.Context, event: SDL.Event) {
	#partial switch event.type {
	case .MOUSE_MOTION:
		motion := event.motion
		mui.input_mouse_move(mui_ctx, i32(motion.x), i32(motion.y))
	case .MOUSE_BUTTON_DOWN:
		button := event.button
		mui.input_mouse_down(mui_ctx, i32(button.x), i32(button.y), sdl_to_microui_btn(button.button))
	case .MOUSE_BUTTON_UP:
		button := event.button
		mui.input_mouse_up(mui_ctx, i32(button.x), i32(button.y), sdl_to_microui_btn(button.button))
	case .MOUSE_WHEEL:
		wheel := event.wheel
		mui.input_scroll(mui_ctx, i32(wheel.x), i32(wheel.y))
	case .KEY_DOWN:
		key := event.key
		switch key.key {
			case SDL.K_LCTRL: mui.input_key_down(mui_ctx, .CTRL)
			case SDL.K_LSHIFT: mui.input_key_down(mui_ctx, .SHIFT)
			case SDL.K_LALT: mui.input_key_down(mui_ctx, .ALT)
			case SDL.K_RETURN: mui.input_key_down(mui_ctx, .RETURN)
			case SDL.K_DELETE: mui.input_key_down(mui_ctx, .DELETE)
			case SDL.K_BACKSPACE: mui.input_key_down(mui_ctx, .BACKSPACE)
			case SDL.K_LEFT: mui.input_key_down(mui_ctx, .LEFT)
			case SDL.K_RIGHT: mui.input_key_down(mui_ctx, .RIGHT)
			case SDL.K_HOME: mui.input_key_down(mui_ctx, .HOME)
			case SDL.K_END: mui.input_key_down(mui_ctx, .END)
			case 'A': mui.input_key_down(mui_ctx, .A)
			case 'X': mui.input_key_down(mui_ctx, .X)
			case 'C': mui.input_key_down(mui_ctx, .C)
			case 'V': mui.input_key_down(mui_ctx, .V)
		}
	case .KEY_UP:
		key := event.key
		switch key.key {
			case SDL.K_LCTRL: mui.input_key_up(mui_ctx, .CTRL)
			case SDL.K_LSHIFT: mui.input_key_up(mui_ctx, .SHIFT)
			case SDL.K_LALT: mui.input_key_up(mui_ctx, .ALT)
			case SDL.K_RETURN: mui.input_key_up(mui_ctx, .RETURN)
			case SDL.K_DELETE: mui.input_key_up(mui_ctx, .DELETE)
			case SDL.K_BACKSPACE: mui.input_key_up(mui_ctx, .BACKSPACE)
			case SDL.K_LEFT: mui.input_key_up(mui_ctx, .LEFT)
			case SDL.K_RIGHT: mui.input_key_up(mui_ctx, .RIGHT)
			case SDL.K_HOME: mui.input_key_up(mui_ctx, .HOME)
			case SDL.K_END: mui.input_key_up(mui_ctx, .END)
			case 'A': mui.input_key_up(mui_ctx, .A)
			case 'X': mui.input_key_up(mui_ctx, .X)
			case 'C': mui.input_key_up(mui_ctx, .C)
			case 'V': mui.input_key_up(mui_ctx, .V)
		}
	// case:
	// 	fmt.println(event.type)
	}
}


VertexUniformData :: struct {
	vp_size: [4]f32,
	rect: [4]f32,
	region: [4]f32
}

window_draw_rect :: proc (window: WindowData, draw_ctx: DrawContext, in_rect: mui.Rect, in_color: mui.Color) {

	rect := [4]f32{f32(in_rect.x), f32(in_rect.y), f32(in_rect.w), f32(in_rect.h)}
	color := [4]f32{f32(in_color.r)/255, f32(in_color.g)/255, f32(in_color.b)/255, f32(in_color.a) / 255}

	vert_uniform_data := VertexUniformData {
		vp_size = {f32 (window.size.x), f32 (window.size.y), 0, 0},
		rect = rect,
	}
	SDL.PushGPUVertexUniformData(draw_ctx.cmd_buf, 0, &vert_uniform_data, size_of(vert_uniform_data))
	
	SDL.PushGPUFragmentUniformData(draw_ctx.cmd_buf, 0, &color, size_of(color))

	SDL.BindGPUGraphicsPipeline(draw_ctx.render_pass, window.ui_rect_pipeline)
	SDL.DrawGPUPrimitives(draw_ctx.render_pass, 4, 1, 0, 0)
}


window_draw_textured_rect :: proc (window: WindowData, draw_ctx: DrawContext, in_rect: mui.Rect, in_color: mui.Color, atlas_region: mui.Rect) {

	rect := [4]f32{f32(in_rect.x), f32(in_rect.y), f32(in_rect.w), f32(in_rect.h)}
	color := [4]f32{f32(in_color.r)/255, f32(in_color.g)/255, f32(in_color.b)/255, f32(in_color.a) / 255}
	region := [4]f32{f32(atlas_region.x)/128, f32(atlas_region.y)/128, f32(atlas_region.w)/128, f32(atlas_region.h) / 128}
	// region := [4]f32{0, 0, 1, 1}

	vert_uniform_data := VertexUniformData {
		vp_size = {f32 (window.size.x), f32 (window.size.y), 0, 0},
		rect = rect,
		region = region,
	}
	SDL.PushGPUVertexUniformData(draw_ctx.cmd_buf, 0, &vert_uniform_data, size_of(vert_uniform_data))
	
	SDL.PushGPUFragmentUniformData(draw_ctx.cmd_buf, 0, &color, size_of(color))

	SDL.BindGPUGraphicsPipeline(draw_ctx.render_pass, window.ui_rect_tex_pipeline)

	sampler_bindings := []SDL.GPUTextureSamplerBinding {
		{
			texture = window.ui_texture,
			sampler = window.ui_sampler,
		}
	}
	SDL.BindGPUFragmentSamplers(draw_ctx.render_pass, 0, &sampler_bindings[0], u32(len(sampler_bindings)))

	SDL.DrawGPUPrimitives(draw_ctx.render_pass, 4, 1, 0, 0)
}