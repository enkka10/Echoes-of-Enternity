extends Node3D

@export var chunk_scene: PackedScene
@export var player: Node3D
@export var noise_height: FastNoiseLite
@export var noise_temp: FastNoiseLite
@export var noise_moisture: FastNoiseLite

const CHUNK_SIZE: int = 32
const RENDER_DISTANCE: int = 6
const REBASE_THRESHOLD: float = 800.0
const TERRAIN_HEIGHT_SCALE: float = 20.0
const GRID_SPACING: float = 1.0

# Preload 3D Models
var tree_models: Array[PackedScene] = []
var rock_models: Array[PackedScene] = []


var active_chunks: Dictionary = {}
var _timer: float = 0.0

func _ready() -> void:
	if not chunk_scene:
		chunk_scene = preload("res://world/Chunk.tscn")
	
	if not noise_height:
		noise_height = FastNoiseLite.new()
		noise_height.seed = randi()
		noise_height.frequency = 0.01
		
	if not noise_temp:
		noise_temp = FastNoiseLite.new()
		noise_temp.seed = randi()
		noise_temp.frequency = 0.02
		
	if not noise_moisture:
		noise_moisture = FastNoiseLite.new()
		noise_moisture.seed = randi()
		noise_moisture.frequency = 0.02
	
	# Initial generation
	if player:
		# Load models using AssetScatterer
		var AssetScatterer = load("res://scripts/AssetScatterer.gd")
		tree_models = AssetScatterer.load_models_from_dir("res://assets/trees")
		rock_models = AssetScatterer.load_models_from_dir("res://assets/rocks")
		
		update_chunks()
		
	# Spawn Cozy Hub
	var hub_scene = load("res://world/CozyHub.tscn")
	if hub_scene:
		var hub = hub_scene.instantiate()
		add_child(hub)
		hub.global_position = Vector3(0, 50, 0)
	else:
		printerr("Failed to load CozyHub.tscn")

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= 0.3:
		_timer = 0.0
		if player:
			update_chunks()
			check_rebasing()

func update_chunks() -> void:
	if not player:
		return
		
	var player_pos = player.global_position
	var p_x = int(floor(player_pos.x / CHUNK_SIZE))
	var p_z = int(floor(player_pos.z / CHUNK_SIZE))
	
	var current_coord = Vector2i(p_x, p_z)
	
	# Identify chunks to keep or create
	var chunks_to_keep = []
	
	for x in range(current_coord.x - RENDER_DISTANCE, current_coord.x + RENDER_DISTANCE + 1):
		for z in range(current_coord.y - RENDER_DISTANCE, current_coord.y + RENDER_DISTANCE + 1):
			var coord = Vector2i(x, z)
			chunks_to_keep.append(coord)
			
			if not active_chunks.has(coord):
				spawn_chunk(coord)
	
	# Remove old chunks
	var coords_to_remove = []
	for coord in active_chunks:
		if not coord in chunks_to_keep:
			coords_to_remove.append(coord)
			
	for coord in coords_to_remove:
		var chunk = active_chunks[coord]
		chunk.queue_free()
		active_chunks.erase(coord)

func spawn_chunk(coord: Vector2i) -> void:
	var chunk = chunk_scene.instantiate() as Chunk
	add_child(chunk)
	chunk.chunk_generated.connect(_on_chunk_generated)
	chunk.generate(coord, CHUNK_SIZE, noise_height, noise_temp, noise_moisture, TERRAIN_HEIGHT_SCALE)
	active_chunks[coord] = chunk

func get_noise_height(global_x: float, global_z: float) -> float:
	return noise_height.get_noise_2d(global_x, global_z) * TERRAIN_HEIGHT_SCALE

func get_mesh_height(global_x: float, global_z: float) -> float:
	var grid_x = global_x / GRID_SPACING
	var grid_z = global_z / GRID_SPACING
	
	var ix = floor(grid_x)
	var iz = floor(grid_z)
	var fx = grid_x - ix
	var fz = grid_z - iz
	
	# Get heights at the four corners of the grid cell
	var h00 = get_noise_height(ix * GRID_SPACING, iz * GRID_SPACING)
	var h10 = get_noise_height((ix + 1) * GRID_SPACING, iz * GRID_SPACING)
	var h01 = get_noise_height(ix * GRID_SPACING, (iz + 1) * GRID_SPACING)
	var h11 = get_noise_height((ix + 1) * GRID_SPACING, (iz + 1) * GRID_SPACING)
	
	# Interpolate based on the triangle split
	var height = 0.0
	if fx + fz <= 1.0:
		height = h00 + (h10 - h00) * fx + (h01 - h00) * fz
	else:
		height = h11 + (h10 - h11) * (1.0 - fz) + (h01 - h11) * (1.0 - fx)
		
	return height

func _on_chunk_generated(chunk: Chunk) -> void:
	var coord = chunk.chunk_coord
	
	# Spawn Enemy (Low chance, far chunks)
	if randf() < 0.02: # 2% chance
		var dist = coord.length()
		if dist > 2: # Only spawn in chunks somewhat far from origin
			var enemy_scene = load("res://enemies/Enemy.tscn")
			if enemy_scene:
				var enemy = enemy_scene.instantiate()
				chunk.add_child(enemy)
				
				var ex = randi_range(0, CHUNK_SIZE)
				var ez = randi_range(0, CHUNK_SIZE)
				var global_ex = coord.x * CHUNK_SIZE + ex
				var global_ez = coord.y * CHUNK_SIZE + ez
				var e_height = get_mesh_height(global_ex, global_ez)
				
				enemy.position = Vector3(ex, e_height + 1.0, ez)
				
				if not enemy.is_in_group("enemies"):
					enemy.add_to_group("enemies")
			else:
				printerr("Failed to load Enemy.tscn") 
				
	# Spawn Vegetation (Trees and Rocks)
	_spawn_vegetation(chunk, coord)

func _spawn_vegetation(chunk: Chunk, coord: Vector2i) -> void:
	var AssetScatterer = load("res://scripts/AssetScatterer.gd")
	
	# Spawn Trees (10-20 per chunk)
	AssetScatterer.scatter(chunk, randi_range(10, 20), tree_models)
			
	# Spawn Rocks (5-10 per chunk)
	AssetScatterer.scatter(chunk, randi_range(5, 10), rock_models)

func check_rebasing() -> void:
	if player.global_position.length() > REBASE_THRESHOLD:
		var shift = -player.global_position
		shift.y = 0 
		
		player.global_position += shift
		
		for coord in active_chunks:
			active_chunks[coord].global_position += shift
			
		get_node("/root/PersistenceManager").add_world_offset(-shift)
		
		print("Origin rebased by: ", shift)
