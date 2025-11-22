class_name AssetScatterer
extends RefCounted

static func load_models_from_dir(path: String) -> Array[PackedScene]:
	var models: Array[PackedScene] = []
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if !dir.current_is_dir() and (file_name.ends_with(".glb") or file_name.ends_with(".gltf")):
				var full_path = path + "/" + file_name
				var scene = load(full_path)
				if scene:
					models.append(scene)
			file_name = dir.get_next()
	return models

static func scatter(chunk: Node3D, count: int, models: Array[PackedScene]):
	if models.is_empty():
		return
	
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	# Assuming chunk has a size property. Chunk.gd has chunk_size.
	var size = 32 
	if "chunk_size" in chunk:
		size = chunk.chunk_size
		
	var space_state = chunk.get_world_3d().direct_space_state
	
	for i in range(count):
		var scene = models.pick_random()
		var instance = scene.instantiate()
		chunk.add_child(instance)
		
		var rx = rng.randf_range(0, size)
		var rz = rng.randf_range(0, size)
		
		# Raycast
		# Start high relative to the chunk's Y (which is 0 usually, but let's use global)
		var global_origin = chunk.global_position + Vector3(rx, 200, rz)
		var global_target = chunk.global_position + Vector3(rx, -200, rz)
		
		var query = PhysicsRayQueryParameters3D.create(global_origin, global_target)
		query.collision_mask = 1 # Terrain
		
		var result = space_state.intersect_ray(query)
		
		if result:
			var hit_pos = result.position
			var normal = result.normal
			
			# Metadata
			var ground_offset = 0.0
			if instance.has_meta("ground_offset"):
				ground_offset = instance.get_meta("ground_offset")
			
			var align = false
			if instance.has_meta("align_to_slope"):
				align = instance.get_meta("align_to_slope")
				
			instance.global_position = hit_pos + Vector3(0, ground_offset, 0)
			
			if align:
				# Align to normal
				# Create a basis where Y is the normal
				var up = normal
				var forward = Vector3.FORWARD
				# If up is parallel to forward, pick another
				if abs(up.dot(forward)) > 0.99:
					forward = Vector3.RIGHT
					
				var right = forward.cross(up).normalized()
				forward = up.cross(right).normalized()
				
				instance.global_transform.basis = Basis(right, up, forward)
				
				# Random Y rotation (local)
				instance.rotate_object_local(Vector3.UP, rng.randf() * TAU)
			else:
				# Just random Y rotation, keep upright
				instance.rotation.y = rng.randf() * TAU
				
			# Random Scale
			var s = rng.randf_range(0.8, 1.2)
			instance.scale = Vector3(s, s, s)
		else:
			instance.queue_free()
