extends CharacterBody3D

@export var speed: float = 3.0
@export var acceleration: float = 10.0
@export var attack_range: float = 1.5
@export var detection_range: float = 20.0

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D


var player: Node3D = null

func _ready() -> void:
	# Find player
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]
		
	# Setup navigation
	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = attack_range
	nav_agent.avoidance_enabled = true

func _physics_process(delta: float) -> void:
	if not player:
		return
		
	var dist = global_position.distance_to(player.global_position)
	
	if dist > detection_range:
		return # Idle
		
	# Update target position
	nav_agent.target_position = player.global_position
	
	if nav_agent.is_navigation_finished():
		return # Reached target
		
	var current_agent_position = global_position
	var next_path_position = nav_agent.get_next_path_position()
	
	var new_velocity = (next_path_position - current_agent_position).normalized() * speed
	
	# Simple rotation
	if new_velocity.length() > 0.1:
		var look_dir = Vector2(new_velocity.z, new_velocity.x)
		rotation.y = look_dir.angle()
		
	velocity = velocity.move_toward(new_velocity, acceleration * delta)
	
	# Apply gravity if needed, but we are on navmesh so usually Y is handled by move_and_slide on slopes
	# However, for a simple enemy, we might want to snap to floor
	if not is_on_floor():
		velocity.y -= 9.8 * delta
		
	move_and_slide()
