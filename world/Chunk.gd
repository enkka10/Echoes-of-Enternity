extends MeshInstance3D
class_name Chunk

const TERRAIN_HEIGHT_SCALE: float = 20.0

# Cache resources
const TERRAIN_SHADER = preload("res://materials/terrain_blender.gdshader")
const GRASS_TEX = preload("res://assets/textures/grass.png")
const SAND_TEX = preload("res://assets/textures/sand.png")
const ROCK_TEX = preload("res://assets/textures/rock.png")
const SNOW_TEX = preload("res://assets/textures/snow.png")
const PERSISTENT_OBJ_SCENE = preload("res://world/PersistentObject.tscn")

var _thread: Thread

signal chunk_generated(chunk: Chunk)

var chunk_coord: Vector2i
var chunk_size: int

func generate(coord: Vector2i, size: int, noise_height: FastNoiseLite, noise_temp: FastNoiseLite, noise_moisture: FastNoiseLite, height_scale: float = 20.0) -> void:
	chunk_coord = coord
	chunk_size = size
	_thread = Thread.new()
	_thread.start(_generate_mesh_data.bind([coord, size, noise_height, noise_temp, noise_moisture, height_scale]))

func _generate_mesh_data(args: Array) -> void:
	var coord = args[0]
	var size = args[1]
	var noise_height = args[2]
	var noise_temp = args[3]
	var noise_moisture = args[4]
	var height_scale = args[5]
	
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	for z in range(size + 1):
		for x in range(size + 1):
			var world_x = coord.x * size + x
			var world_z = coord.y * size + z
			
			var height = noise_height.get_noise_2d(world_x, world_z) * height_scale
			var temp = noise_temp.get_noise_2d(world_x, world_z)
			var moisture = noise_moisture.get_noise_2d(world_x, world_z)
			
			# Biome coloring
			var color = Color.GREEN # Default Grass
			if height > 15:
				color = Color.WHITE # Snow
			elif height < -5:
				color = Color.SANDY_BROWN # Sand
			elif temp > 0.5 and moisture < -0.2:
				color = Color.DARK_GOLDENROD # Desert
			
			st.set_color(color)
			st.set_uv(Vector2(x, z))
			st.add_vertex(Vector3(x, height, z))
			
	for z in range(size):
		for x in range(size):
			var i = z * (size + 1) + x
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + size + 1)
			st.add_index(i + size + 1)
			st.add_index(i + 1)
			st.add_index(i + size + 2)
			
	st.generate_normals()
	var mesh = st.commit()
	
	call_deferred("_apply_mesh", mesh, coord, size)

func _apply_mesh(mesh: ArrayMesh, coord: Vector2i, size: int) -> void:
	# Use the root node itself as the MeshInstance3D
	self.mesh = mesh
	
	# Material
	var mat = ShaderMaterial.new()
	mat.shader = TERRAIN_SHADER
	
	mat.set_shader_parameter("grass_texture", GRASS_TEX)
	mat.set_shader_parameter("sand_texture", SAND_TEX)
	mat.set_shader_parameter("rock_texture", ROCK_TEX)
	mat.set_shader_parameter("snow_texture", SNOW_TEX)
	
	self.material_override = mat
	self.create_trimesh_collision()
	
	# Ensure the StaticBody uses correct layers (root's child 0 is the StaticBody)
	# Ensure the StaticBody uses correct layers
	var static_body: StaticBody3D = null
	for child in get_children():
		if child is StaticBody3D:
			static_body = child
			break
			
	if static_body:
		static_body.collision_layer = 1
		static_body.collision_mask = 1
	else:
		printerr("Chunk: No StaticBody found after create_trimesh_collision!")
	
	position = Vector3(coord.x * size, 0, coord.y * size)
	
	if _thread.is_alive():
		_thread.wait_to_finish()
		
	# Wait for physics engine to update collision shapes
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	# Configure and bake navigation mesh
	var nav_region = $NavigationRegion3D
	if nav_region:
		var nav_mesh = NavigationMesh.new()
		nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
		nav_mesh.geometry_collision_mask = 1
		nav_mesh.agent_height = 1.0
		nav_mesh.agent_radius = 0.5
		nav_mesh.agent_max_climb = 1.0 # Allow climbing small slopes
		nav_mesh.agent_max_slope = 45.0
		
		nav_region.navigation_mesh = nav_mesh
		
		# Bake on a thread
		nav_region.bake_navigation_mesh(true)
	else:
		printerr("Chunk: NavigationRegion3D not found!")
	
	# NOW it's safe to load objects
	_load_persistent_objects(coord)
	
	# Snap player if they are in this chunk (e.g. after teleport)
	snap_player_if_needed()
	
	emit_signal("chunk_generated", self)

func snap_player_if_needed() -> void:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() == 0:
		return
	var player = players[0]
	
	if player:
		var p_pos = player.global_position
		
		if chunk_size > 0:
			var min_x = chunk_coord.x * chunk_size
			var max_x = (chunk_coord.x + 1) * chunk_size
			var min_z = chunk_coord.y * chunk_size
			var max_z = (chunk_coord.y + 1) * chunk_size
			
			if p_pos.x >= min_x and p_pos.x < max_x and p_pos.z >= min_z and p_pos.z < max_z:
				var correct_y = get_height_at_world(p_pos.x, p_pos.z, [player])
				player.global_position.y = correct_y
				# Reset vertical velocity if possible to stop falling momentum
				if player is CharacterBody3D:
					player.velocity.y = 0

func _exit_tree() -> void:
	if _thread and _thread.is_alive():
		_thread.wait_to_finish()

func _load_persistent_objects(coord: Vector2i) -> void:
	var mods = get_node("/root/PersistenceManager").get_modifications_for_chunk(coord)
	
	for mod in mods:
		if mod.has("pos_x") and mod.has("pos_y") and mod.has("pos_z"):
			var pos = Vector3(mod["pos_x"], mod["pos_y"], mod["pos_z"])
			
			if PERSISTENT_OBJ_SCENE:
				var obj = PERSISTENT_OBJ_SCENE.instantiate()
				add_child(obj)
				
				# Snap to correct terrain height
				var correct_y = get_height_at_world(pos.x, pos.z, [obj])
				obj.global_position = Vector3(pos.x, correct_y, pos.z)
			else:
				printerr("Failed to load PersistentObject.tscn in Chunk")

func get_height_at_world(x: float, z: float, exclude: Array = []) -> float:
	# Start high above the terrain
	var ray_from = Vector3(x, 2000.0, z)
	var ray_to   = Vector3(x, -2000.0, z)

	var space_state = get_world_3d().direct_space_state
	# Use simple intersect_ray overload if available, or create parameters object
	var query = PhysicsRayQueryParameters3D.create(ray_from, ray_to)
	query.collision_mask = 1    # Your chunk's collision mask
	query.exclude = exclude
	
	var result = space_state.intersect_ray(query)

	if result.has("position"):
		return result["position"].y
	else:
		# No terrain hit — return a safe default
		return 0.0
