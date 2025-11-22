extends CanvasLayer

func _on_new_game_pressed() -> void:
	# Clear save
	var dir = DirAccess.open("user://")
	if dir.file_exists("echoes_save.json"):
		dir.remove("echoes_save.json")
	
	# Reset GameState
	var gs = get_node("/root/GameState")
	gs.loop_count = 1
	
	# Reset PersistenceManager
	var pm = get_node("/root/PersistenceManager")
	pm.modifications.clear()
	pm.inventory.clear()
	pm.collected_relics.clear()
	pm.previous_loop_path.clear()
	pm.current_loop_path.clear()
	
	get_tree().change_scene_to_file("res://main.tscn")

func _on_continue_pressed() -> void:
	if FileAccess.file_exists("user://echoes_save.json"):
		get_tree().change_scene_to_file("res://main.tscn")
	else:
		print("No save file found.")
