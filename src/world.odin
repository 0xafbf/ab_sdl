
package main

import "core:log"
import "core:unicode/utf8"

import "core:reflect"

import SDL "vendor:sdl3"

World :: struct {

}

SceneResource :: struct {

}

SceneInstance :: struct {
	resource: int,
	data: map[string]int,
}

Scene :: struct {

	resources: []SceneResource,

}

Scene_Section_Asset :: struct {
	path: string,
	id: string,
}

Scene_Section_Node :: struct {
	id: string,
	type: string,
	parent: string,
}

Scene_Section :: union {
	Scene_Section_Asset,
	Scene_Section_Node,
}

Scene_Parse_Context :: struct {
	payload: string,
	cursor: uint,
	all_sections: [dynamic]Scene_Section,
	current_section: uint,
}


scene_load_new :: proc(path: cstring) -> Scene {
	scene: Scene
	log.info("loading file at path:", path)

	file_size: uint = ---
	file_bytes := ([^]u8)(SDL.LoadFile(path, &file_size))

	scene_ctx := Scene_Parse_Context{
		payload = string(file_bytes[:file_size])
	}
	scene_parse(&scene_ctx)

	log.info("FINISH")

	return scene;
}

scene_parse :: proc(scene_ctx: ^Scene_Parse_Context) {
	str := scene_ctx.payload
	for scene_ctx.cursor < len(str) {
		char, char_len := utf8.decode_rune(str[scene_ctx.cursor:])
		if char == '[' {
			scene_ctx.cursor += uint(char_len)
			section := scene_parse_section(scene_ctx)
			if section == nil {
				log.info("stopping parsing as section is malformed")
				return
			}
			append(&scene_ctx.all_sections, section)
			scene_ctx.current_section = len(scene_ctx.all_sections)
		}
		else if char == '\n' {
			scene_ctx.cursor += uint(char_len)
			log.info("linebreak")
		} else if char == ' ' {
			scene_ctx.cursor += uint(char_len)
			log.info("space")
		} else {
			scene_parse_property(scene_ctx)
		}
	}
}

scene_parse_word :: proc(buffer: string, in_cursor: uint) -> string {
	cursor := in_cursor
	word_start: uint = cursor
	for cursor < len(buffer) {
		char, char_len_int := utf8.decode_rune(buffer[cursor:])
		char_len := uint(char_len_int)
		end_word :=  char == ' ' || char == ']' || char == '\n'
		if end_word {
			word := buffer[word_start: cursor]
			return word
		}
		cursor += char_len
	}
	return buffer[word_start:cursor]
}

scene_parse_property :: proc(scene_ctx: ^Scene_Parse_Context) {
	str := scene_ctx.payload
	word := scene_parse_word(str, scene_ctx.cursor)
	log.info("property:", word)
	scene_ctx.cursor += len(word)
}

scene_parse_attribute :: proc(scene_ctx: ^Scene_Parse_Context) -> (key: string, value: string) {
	buffer := scene_ctx.payload
	cursor := scene_ctx.cursor
	value_start: uint
	is_quoted: bool

	for cursor < len(buffer) {
		char, char_len_int := utf8.decode_rune(buffer[cursor:])
		char_len := uint(char_len_int)
		is_whitespace :=  char == ' '
		if is_whitespace {
			cursor += char_len
		} else {
			break
		}
	}

	key_start: uint = cursor

	for cursor < len(buffer) {
		char, char_len_int := utf8.decode_rune(buffer[cursor:])
		char_len := uint(char_len_int)
		end_word :=  char == ' ' || char == ']' || char == '\n' || char == '='
		if end_word {
			key = buffer[key_start: cursor]
			break
		} else {
			cursor += char_len
		}
	}

	if buffer[cursor] == '=' {
		cursor += 1
		value_start = cursor

		if cursor < len(buffer) && buffer[cursor] == '"' {
			cursor += 1
			value_start = cursor
			is_quoted = true
		}

		for cursor < len(buffer) {
			char, char_len_int := utf8.decode_rune(buffer[cursor:])
			char_len := uint(char_len_int)
			end_word: bool
			if is_quoted {
				end_word = char == '"'
			} else {
				end_word = char == ' ' || char == ']' || char == '\n'
			}
			if end_word {
				value = buffer[value_start: cursor]
				if is_quoted {
					cursor += 1
				}
				break
			} else {
				cursor += char_len
			}
		}
	}

	scene_ctx.cursor = cursor

	return key, value

}


scene_parse_section_asset :: proc(scene_ctx: ^Scene_Parse_Context) -> Scene_Section_Asset {
	scene_asset_ref := Scene_Section_Asset {}
	for scene_ctx.payload[scene_ctx.cursor] != ']' {
		cursor_start := scene_ctx.cursor
		attr_key, attr_val := scene_parse_attribute(scene_ctx)
		log.info("attr:", attr_key, attr_val)

		log.info("scene_asset_ref:", &scene_asset_ref, scene_asset_ref)


		struct_field := reflect.struct_field_by_name(Scene_Section_Asset, attr_key)
		log.info("struct_field:", struct_field)

		target_val := reflect.struct_field_value(
			{&scene_asset_ref, typeid_of(Scene_Section_Asset)},
			struct_field
		)
		log.info("target_val", target_val)


		target := (^string) (target_val.data)

		target^ = attr_val

	}

	log.info(scene_asset_ref)
	return scene_asset_ref
}

scene_parse_section_node :: proc(scene_ctx: ^Scene_Parse_Context) -> Scene_Section_Node {
	scene_asset_ref := Scene_Section_Node {}
	return scene_asset_ref
}

scene_parse_section :: proc(scene_ctx: ^Scene_Parse_Context) -> (section: Scene_Section) {
	str := scene_ctx.payload
	section_name := scene_parse_word(str, scene_ctx.cursor)
	scene_ctx.cursor += len(section_name) + 1

	if section_name == "asset" {
		section = scene_parse_section_asset(scene_ctx)
	} else if section_name == "node" {
		section = Scene_Section_Node {}
	} else {
		log.info("invalid section:", section_name)
		return nil
	}

	cursor := scene_ctx.cursor
	for cursor < len(str) {
		char, char_len_int := utf8.decode_rune(str[cursor:])
		char_len := uint(char_len_int)
		end_word :=  char == ' ' || char == ']' || char == '\n'

		if char == ']' {
			log.info("end section header")
			scene_ctx.cursor = cursor + char_len
			return section
		} else if end_word {
			cursor += 1
		} else {
			word := scene_parse_word(str, cursor)
			log.info("parsed word:", word)
			cursor += len(word)
		}
	}
	log.info("Error: never found section end")
	return section
}


world_spawn_scene :: proc(scene: Scene) {

}
