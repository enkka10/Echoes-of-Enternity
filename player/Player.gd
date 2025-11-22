extends CharacterBody3D
class_name Player

signal player_died

@export var move_speed: float = 8.0
@export var sprint_multiplier: float = 1.8
@export var jump_velocity: float = 10.0
@export var mouse_sensitivity: float = 0.002

var _gravity: float = 0.0
const FALL_THRESHOLD: float = -50.0

var _velocity: Vector3 = Vector3.ZERO
var _paused: bool = false
var _has_died: bool = false

@onready var _spring_arm: SpringArm3D = $SpringArm3D
@onready var _pause_overlay: Control = $CanvasLayer/PauseOverlay

func _ready() -> void:
	position = Vector3(0, 10, 0)
	add_to_group("player")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_pause_overlay.visible = false
	_gravity = ProjectSettings.get_setting("physics/3d/default_gravity") as float
	
	_gravity = ProjectSettings.get_setting("physics/3d/default_gravity") as float
	
	player_died.connect(get_node("/root/GameState").start_new_loop)
	
	_load_inventory()

func _physics_process(delta: float) -> void:
	if not _paused:
		_apply_gravity(delta)
		var direction = _get_input_direction()
		_apply_movement(direction)
		_handle_jump()
	else:
		_velocity.x = lerp(_velocity.x, 0.0, 0.1)
		_velocity.z = lerp(_velocity.z, 0.0, 0.1)
	velocity = _velocity
	move_and_slide()
	_check_fall()
	
	# Record path for Ghost Trail
	if Engine.get_physics_frames() % 10 == 0: # Record every 10 frames
		var pm = get_node("/root/PersistenceManager")
		pm.current_loop_path.append(global_position)

func _input(event: InputEvent) -> void:
	if _paused:
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)
		var pitch = clamp(_spring_arm.rotation.x - event.relative.y * mouse_sensitivity, -1.2, 1.2)
		_spring_arm.rotation.x = pitch
		
	if event is InputEventKey and event.pressed:
		if event.keycode == Key.KEY_B:
			_try_build()
		elif event.keycode == Key.KEY_T:
			get_node("/root/GameState").start_new_loop()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == Key.KEY_ESCAPE and event.pressed:
		_toggle_pause()

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		_velocity.y -= _gravity * delta
	elif _velocity.y < 0.0:
		_velocity.y = 0.0

func _get_input_direction() -> Vector3:
	var horizontal = Vector2(
		int(Input.is_key_pressed(Key.KEY_D)) - int(Input.is_key_pressed(Key.KEY_A)),
		int(Input.is_key_pressed(Key.KEY_S)) - int(Input.is_key_pressed(Key.KEY_W))
	)
	if horizontal == Vector2.ZERO:
		return Vector3.ZERO
	horizontal = horizontal.normalized()
	var forward = -_spring_arm.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right = _spring_arm.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	return forward * horizontal.y + right * horizontal.x

func _apply_movement(direction: Vector3) -> void:
	var target_speed = move_speed
	if Input.is_key_pressed(Key.KEY_SHIFT):
		target_speed *= sprint_multiplier
	var target_velocity = direction * target_speed
	_velocity.x = target_velocity.x
	_velocity.z = target_velocity.z

func _handle_jump() -> void:
	if is_on_floor() and Input.is_key_pressed(Key.KEY_SPACE):
		_velocity.y = jump_velocity

func _toggle_pause() -> void:
	_paused = not _paused
	if _paused:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_pause_overlay.visible = _paused

func _check_fall() -> void:
	if global_transform.origin.y < FALL_THRESHOLD and not _has_died:
		_has_died = true
		emit_signal("player_died")

func _try_build() -> void:
	var space_state = get_world_3d().direct_space_state
	var cam = get_viewport().get_camera_3d()
	if not cam: return
	
	var mouse_pos = get_viewport().get_mouse_position()
	var from = cam.project_ray_origin(mouse_pos)
	var to = from + cam.project_ray_normal(mouse_pos) * 10.0 # 10 units reach
	
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space_state.intersect_ray(query)
	
	if result:
		var pos = result.position
		var chunk_size = 32 # Hardcoded for now, should match WorldGenerator
		var chunk_x = int(floor(pos.x / chunk_size))
		var chunk_z = int(floor(pos.z / chunk_size))
		var chunk_coord = Vector2i(chunk_x, chunk_z)
		
		# Create object
		var obj_scene = load("res://world/PersistentObject.tscn")
		if obj_scene:
			var obj = obj_scene.instantiate()
			get_parent().add_child(obj) # Add to world, ideally should be child of chunk but global is easier for now
			obj.global_position = pos
		else:
			printerr("Failed to load PersistentObject.tscn")
			return
		
		# Register modification
		# Index needs to be unique per chunk. For now using timestamp or random int
		var index = Time.get_ticks_msec() 
		var data = {
			"pos_x": pos.x,
			"pos_y": pos.y,
			"pos_z": pos.z
		}
		get_node("/root/PersistenceManager").register_modification(chunk_coord, "object", index, data)
		print("Built object at ", pos)

# Relic System
var inventory: Array[Relic] = []

func collect_relic(relic: Relic) -> void:
	if not relic: return
	inventory.append(relic)
	_apply_relics()
	print("Collected relic: ", relic.name)
	
	# Persist
	var pm = get_node("/root/PersistenceManager")
	if not pm.inventory.has(relic.resource_path):
		pm.inventory.append(relic.resource_path)

func _apply_relics() -> void:
	# Reset base stats
	move_speed = 8.0
	jump_velocity = 10.0
	sprint_multiplier = 1.8
	
	for relic in inventory:
		if relic.modifiers.has("move_speed"):
			move_speed *= relic.modifiers["move_speed"]
		if relic.modifiers.has("jump_velocity"):
			jump_velocity *= relic.modifiers["jump_velocity"]
		if relic.modifiers.has("sprint_multiplier"):
			sprint_multiplier *= relic.modifiers["sprint_multiplier"]
			
	print("Stats updated: Speed=", move_speed, " Jump=", jump_velocity)

# Preload Audio
# Using load() to be safe against missing files
var loop_reset_sfx = load("res://assets/audio/loop_reset_whoosh.ogg")

func play_loop_reset_sfx() -> void:
	var sfx_node = $PlayerSFX
	if sfx_node:
		sfx_node.stream = loop_reset_sfx
		sfx_node.play()

func _load_inventory() -> void:
	var pm = get_node("/root/PersistenceManager")
	inventory.clear()
	for path in pm.inventory:
		var relic = load(path)
		if relic:
			inventory.append(relic)
	_apply_relics()
