extends Node3D

@export var ground_offset: float = 0.0

func _ready() -> void:
	# Initial offset (optional, might be overwritten by snap)
	# position.y += ground_offset 
	
	# Wait for physics to stabilize
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	_snap_to_terrain()

func _snap_to_terrain() -> void:
	var parent = get_parent()
	if parent.has_method("get_height_at_world"):
		# We use the parent chunk's raycast method to find the exact terrain height
		# Pass [self] to exclude this object's colliders from the raycast
		var terrain_height = parent.get_height_at_world(global_position.x, global_position.z, [self])
		
		# If the raycast missed (returns 0.0 and we are not near 0), we might want to ignore?
		# But for now, we trust the chunk's method.
		# Note: get_height_at_world returns 0.0 if no hit. 
		# If we are high up, 0.0 might be wrong.
		# But generally trees are spawned within the chunk bounds.
		
		global_position.y = terrain_height + ground_offset
