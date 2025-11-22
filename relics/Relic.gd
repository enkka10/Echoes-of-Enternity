extends Resource
class_name Relic

@export var name: String = "Unknown Relic"
@export var icon: Texture2D
@export var modifiers: Dictionary = {} # e.g. {"move_speed": 1.2, "jump_velocity": 1.1}
