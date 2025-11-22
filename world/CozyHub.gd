extends StaticBody3D

func _ready() -> void:
	_create_ghost_trail()

func _create_ghost_trail() -> void:
	var pm = get_node("/root/PersistenceManager")
	if pm.previous_loop_path.is_empty():
		return
		
	var line = MeshInstance3D.new()
	var immediate_mesh = ImmediateMesh.new()
	var material = StandardMaterial3D.new()
	
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.5, 0.8, 1.0, 0.5) # Ghostly blue
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
	
	for pos in pm.previous_loop_path:
		immediate_mesh.surface_add_vertex(pos)
		
	immediate_mesh.surface_end()
	
	line.mesh = immediate_mesh
	# Ghost trail is in global coordinates, so add to world root or reset transform
	get_parent().add_child.call_deferred(line)
	line.global_transform = Transform3D.IDENTITY
