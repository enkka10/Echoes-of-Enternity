extends CanvasLayer

func _on_continue_pressed() -> void:
	queue_free()

func _on_exit_pressed() -> void:
	get_tree().quit()
