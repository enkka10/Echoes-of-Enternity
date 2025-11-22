extends Node

signal origin_rebased(new_offset: Vector3)

const SAVE_PATH = "user://echoes_save.json"

var world_origin_offset: Vector3 = Vector3.ZERO

var modifications: Dictionary = {} # Key: "chunk_x_z|type|index", Value: {data}
var inventory: Array = [] # Array of Relic resource paths
var collected_relics: Array = [] # Array of unique IDs for collected relics
var previous_loop_path: Array = [] # Array of Vector3 positions from previous loop
var current_loop_path: Array = [] # Array of Vector3 positions for current loop

func _ready() -> void:
	load_game()

func add_world_offset(offset: Vector3) -> void:
	world_origin_offset += offset
	emit_signal("origin_rebased", offset)

func register_modification(chunk_coord: Vector2i, type: String, index: int, data: Dictionary) -> void:
	var key = "chunk_%d_%d|%s|%d" % [chunk_coord.x, chunk_coord.y, type, index]
	modifications[key] = data
	# Auto-save on modification could be an option, but let's stick to manual/loop save for now

func get_modifications_for_chunk(chunk_coord: Vector2i) -> Array:
	var chunk_mods = []
	var prefix = "chunk_%d_%d|" % [chunk_coord.x, chunk_coord.y]
	
	for key in modifications:
		if key.begins_with(prefix):
			chunk_mods.append(modifications[key])
			
	return chunk_mods

func save_game() -> void:
	var save_data = {
		"loop_count": get_node("/root/GameState").loop_count,
		"modifications": modifications,
		"inventory": inventory,
		"collected_relics": collected_relics,
		"previous_loop_path": current_loop_path # Save current path as previous for next loop
	}
	
	var file = FileAccess.open_compressed(SAVE_PATH, FileAccess.WRITE, FileAccess.COMPRESSION_GZIP)
	if file:
		file.store_string(JSON.stringify(save_data))
		print("Game saved.")
	else:
		printerr("Failed to save game: ", FileAccess.get_open_error())

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
		
	var file = FileAccess.open_compressed(SAVE_PATH, FileAccess.READ, FileAccess.COMPRESSION_GZIP)
	if file:
		var content = file.get_as_text()
		var json = JSON.new()
		var error = json.parse(content)
		
		if error == OK:
			var data = json.data
			if data.has("loop_count"):
				get_node("/root/GameState").loop_count = data["loop_count"]
			if data.has("modifications"):
				modifications = data["modifications"]
			if data.has("inventory"):
				inventory = data["inventory"]
			if data.has("collected_relics"):
				collected_relics = data["collected_relics"]
			if data.has("previous_loop_path"):
				previous_loop_path = data["previous_loop_path"]
			print("Game loaded. Loop: ", get_node("/root/GameState").loop_count)
		else:
			printerr("Failed to parse save file: ", json.get_error_message())
	else:
		printerr("Failed to open save file: ", FileAccess.get_open_error())
