extends CanvasLayer

@onready var loop_label: Label = $Control/VBoxContainer/LoopLabel
@onready var relic_label: Label = $Control/VBoxContainer/RelicLabel
@onready var hotbar_container: HBoxContainer = $Control/HotbarContainer

func _ready() -> void:
	add_to_group("hud")

func _process(delta: float) -> void:
	var loop = get_node("/root/GameState").loop_count
	loop_label.text = "Loop: %d" % loop
	
	var pm = get_node("/root/PersistenceManager")
	var relic_count = pm.inventory.size()
	relic_label.text = "Relics: %d/25" % relic_count
	
	get_node("/root/GameState").check_win_condition()
	
	# Simple hotbar update (inefficient but works for prototype)
	# In real app, use signals
	for child in hotbar_container.get_children():
		child.queue_free()
		
	for path in pm.inventory:
		var relic = load(path)
		if relic and relic.icon:
			var tex = TextureRect.new()
			tex.texture = relic.icon
			tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex.custom_minimum_size = Vector2(40, 40)
			hotbar_container.add_child(tex)
		else:
			# Placeholder for missing icon
			var color = ColorRect.new()
			color.color = Color.CYAN
			hotbar_container.add_child(color)

func play_rewind_anim() -> void:
	var rect = ColorRect.new()
	rect.color = Color(1, 1, 1, 0)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(rect)
	
	var tween = create_tween()
	tween.tween_property(rect, "color:a", 1.0, 0.5)
	tween.tween_property(rect, "color:a", 0.0, 0.5)
	tween.tween_callback(rect.queue_free)

