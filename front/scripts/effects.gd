class_name Effects
extends RefCounted
## Petits effets visuels réutilisables (traits de tir, impacts, éclairs).
## Fonctions "static" : on les appelle directement, ex. Effects.tracer(...).


## Trait lumineux entre deux points, visible une fraction de seconde.
static func tracer(parent: Node, from: Vector3, to: Vector3, color: Color, lifetime := 0.06) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_add_vertex(from)
	mesh.surface_add_vertex(to)
	mesh.surface_end()

	var line := MeshInstance3D.new()
	line.mesh = mesh
	line.material_override = _unshaded(color)
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spawn(parent, line, lifetime)


## Petite boule qui grossit puis disparaît à l'endroit touché.
static func impact(parent: Node, position: Vector3, color: Color, size := 0.07) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = size
	sphere.height = size * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	sphere.material = _unshaded(color)

	var node := MeshInstance3D.new()
	node.mesh = sphere
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spawn(parent, node, 0.25)
	node.global_position = position
	var tween := node.create_tween()
	tween.tween_property(node, "scale", Vector3.ONE * 2.5, 0.25)


## Éclair de lumière au bout du canon.
static func muzzle_flash(parent: Node3D, color: Color) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 3.0
	light.omni_range = 4.0
	parent.add_child(light)
	parent.get_tree().create_timer(0.05).timeout.connect(light.queue_free)


static func _unshaded(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material


static func _spawn(parent: Node, node: Node, lifetime: float) -> void:
	parent.add_child(node)
	parent.get_tree().create_timer(lifetime).timeout.connect(node.queue_free)
