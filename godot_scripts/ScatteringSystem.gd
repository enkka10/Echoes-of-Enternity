extends Node
class_name ScatteringSystem

# ScatteringSystem.gd
# Scatters objects on a terrain mesh using metadata from GLTF files.

func scatter_objects(root_node: Node3D, terrain_mesh: MeshInstance3D, object_scenes: Array[PackedScene], count: int):
	if object_scenes.is_empty():
		return

	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	# Get terrain AABB for bounds
	var aabb = terrain_mesh.get_aabb()
	var start_pos = terrain_mesh.global_position + aabb.position
	var size = aabb.size
	
	# Create collision for raycasting if not present (assuming terrain has collision)
	var space_state = terrain_mesh.get_world_3d().direct_space_state
	
	for i in range(count):
		# Pick random object
		var scene = object_scenes.pick_random()
		var instance = scene.instantiate()
		
		# Read Metadata (from GLTF extras)
		# Note: Godot imports GLTF extras as metadata on the root node of the scene
		var ground_offset = 0.0
		if instance.has_meta("ground_offset"):
			ground_offset = instance.get_meta("ground_offset")
			
		var align_to_slope = false
		if instance.has_meta("align_to_slope"):
			align_to_slope = instance.get_meta("align_to_slope")
			
		# Random Position (XZ)
		var x = rng.randf_range(start_pos.x, start_pos.x + size.x)
		var z = rng.randf_range(start_pos.z, start_pos.z + size.z)
		
		# Raycast to find Y
		var origin = Vector3(x, start_pos.y + size.y + 100, z) # Start high up
		var target = Vector3(x, start_pos.y - 100, z) # End low down
		
		var query = PhysicsRayQueryParameters3D.create(origin, target)
		var result = space_state.intersect_ray(query)
		
		if result:
			var hit_pos = result.position
			var normal = result.normal
			
			instance.position = hit_pos
			instance.position.y += ground_offset
			
			if align_to_slope:
				# Align Up vector to Normal
				# Basic alignment: Look at cross product or use basis
				var new_y = normal
				var new_x = Vector3.UP.cross(new_y).normalized()
				if new_x.length() < 0.01: # Handle case where normal is exactly up
					new_x = Vector3.RIGHT
				var new_z = new_x.cross(new_y).normalized()
				
				instance.transform.basis = Basis(new_x, new_y, new_z)
				
				# Random rotation around Y (local)
				instance.rotate_object_local(Vector3.UP, rng.randf() * TAU)
			else:
				# Just random Y rotation
				instance.rotation.y = rng.randf() * TAU
				
			root_node.add_child(instance)
		else:
			instance.queue_free() # Failed to hit terrain
