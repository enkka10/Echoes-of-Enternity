extends Area3D

@export var relic: Relic

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	
	# Collision (keep this for now, or move to scene if preferred)
	var col = CollisionShape3D.new()
	col.shape = SphereShape3D.new()
	col.shape.radius = 0.5
	add_child(col)
	
	# Find visual child (added by spawner)
	# We wait a frame to ensure children are added if done via code immediately after instantiation
	get_tree().create_timer(0.1).timeout.connect(_setup_visuals)
	
	# Snap to terrain
	_snap_to_terrain_deferred()

func _snap_to_terrain_deferred() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	var parent = get_parent()
	if parent.has_method("get_height_at_world"):
		var terrain_height = parent.get_height_at_world(global_position.x, global_position.z, [self])
		# Relics float slightly above ground
		global_position.y = terrain_height + 1.5

func _setup_visuals() -> void:
	var visual_node: Node3D = null
	for child in get_children():
		if child is Node3D and not child is CollisionShape3D:
			visual_node = child
			break
			
	if visual_node:
		# Float animation
		var tween = create_tween().set_loops()
		tween.tween_property(visual_node, "position:y", 0.2, 1.0).as_relative().set_trans(Tween.TRANS_SINE)
		tween.tween_property(visual_node, "position:y", -0.2, 1.0).as_relative().set_trans(Tween.TRANS_SINE)

func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		if relic:
			body.collect_relic(relic)
			queue_free()
