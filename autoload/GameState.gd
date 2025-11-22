extends Node

var loop_count: int = 1

func start_new_loop() -> void:
	trigger_rewind_effect()
	
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("play_loop_reset_sfx"):
		player.play_loop_reset_sfx()
		
	await get_tree().create_timer(1.0).timeout # Wait for effect
	
	loop_count += 1
	print("Starting loop: ", loop_count)
	# Use get_node to avoid cyclic dependency issues at parse time
	get_node("/root/PersistenceManager").save_game()
	get_tree().reload_current_scene()

func trigger_rewind_effect() -> void:
	# Simple visual effect: Chromatic Aberration + Saturation drop
	var tween = create_tween()
	var env = get_viewport().get_camera_3d().environment
	if not env: return # Should have WorldEnvironment
	
	# Note: This assumes we have a WorldEnvironment with adjustments enabled. 
	# If not, we might need to add one or use a CanvasLayer shader.
	# For prototype, let's just use time scale and maybe a color rect if we had one.
	# Actually, let's just slow down time and print for now, or try to access the default env.
	
	Engine.time_scale = -1.0 # Reverse time? No, physics doesn't support that easily.
	Engine.time_scale = 5.0 # Fast forward?
	
	# Let's just do a simple fade out or "glitch" via HUD if possible.
	# Since we don't have easy access to HUD from here without lookup:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.play_rewind_anim()
		
	# Audio
	# var audio = AudioStreamPlayer.new()
	# add_child(audio)
	# audio.stream = load("res://assets/rewind.wav")
	# audio.play()

func check_win_condition() -> void:
	var pm = get_node("/root/PersistenceManager")
	if loop_count >= 12 and pm.inventory.size() >= 25:
		show_win_screen()

func show_win_screen() -> void:
	var win_screen_scene = load("res://ui/WinScreen.tscn")
	if win_screen_scene:
		var win_screen = win_screen_scene.instantiate()
		get_tree().root.add_child(win_screen)
	else:
		printerr("Failed to load WinScreen.tscn")
