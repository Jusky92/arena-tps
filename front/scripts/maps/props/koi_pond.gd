@tool
class_name KoiPond
extends Node3D
## Bassin du jardin : surface d'eau, carpes koï qui tournent lentement sous la
## surface, nénuphars. Purement décoratif (on marche autour, pas dedans).

@export var size := Vector2(14.0, 9.0)
@export var fish_count := 6

var _fish: Array[Node3D] = []
var _orbits: Array = []          # [rayon x, rayon z, vitesse, phase, profondeur]
var _time := 0.0


func _ready() -> void:
	for child in get_children():
		child.queue_free()
	_fish.clear()
	_orbits.clear()

	# Surface d'eau : légèrement transparente, très réfléchissante.
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.09, 0.28, 0.3, 0.86)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.roughness = 0.08
	water.metallic = 0.35
	water.albedo_texture = load("res://textures/water_pond_albedo.png")
	water.normal_enabled = true
	water.normal_texture = load("res://textures/water_pond_normal.png")
	water.normal_scale = 0.4
	water.uv1_scale = Vector3(0.25, 0.25, 0.25)
	var surface := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = size
	surface.mesh = plane
	surface.material_override = water
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surface)

	# Fond sombre, pour que l'eau ne soit pas « vide » vue de près.
	var bottom := StandardMaterial3D.new()
	bottom.albedo_color = Color(0.07, 0.09, 0.08)
	bottom.roughness = 1.0
	var floor_mesh := MeshInstance3D.new()
	var floor_plane := PlaneMesh.new()
	floor_plane.size = size
	floor_mesh.mesh = floor_plane
	floor_mesh.material_override = bottom
	floor_mesh.position.y = -0.45
	add_child(floor_mesh)

	for i in fish_count:
		_fish.append(_make_fish(i))
		_orbits.append([
			randf_range(size.x * 0.12, size.x * 0.38),
			randf_range(size.y * 0.12, size.y * 0.36),
			randf_range(0.18, 0.4) * (1.0 if i % 2 == 0 else -1.0),
			randf() * TAU,
			randf_range(-0.22, -0.08),
		])
	_place_lilies()


## Une carpe : corps allongé, queue, taches orange ou blanches.
func _make_fish(index: int) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var body_color: Color = [Color(0.95, 0.42, 0.12), Color(0.95, 0.95, 0.93), Color(0.9, 0.55, 0.2),
		Color(0.2, 0.2, 0.24)][index % 4]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = body_color
	mat.roughness = 0.35
	var body := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.13
	mesh.height = 0.26
	mesh.radial_segments = 10
	mesh.rings = 6
	body.mesh = mesh
	body.material_override = mat
	body.scale = Vector3(0.7, 0.55, 2.4)         # corps allongé
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)

	var tail := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.26, 0.2)
	tail.mesh = quad
	var tail_mat := mat.duplicate()
	tail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	tail_mat.albedo_color.a = 0.85
	tail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tail.material_override = tail_mat
	tail.rotation.x = PI / 2.0
	tail.position.z = 0.34
	tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(tail)
	return root


## Nénuphars posés au hasard sur l'eau.
func _place_lilies() -> void:
	var leaf := StandardMaterial3D.new()
	leaf.albedo_color = Color(0.16, 0.38, 0.18)
	leaf.roughness = 0.6
	for i in 7:
		var pad := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = randf_range(0.22, 0.4)
		mesh.bottom_radius = mesh.top_radius
		mesh.height = 0.02
		mesh.radial_segments = 10
		pad.mesh = mesh
		pad.material_override = leaf
		pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(pad)
		pad.position = Vector3(randf_range(-0.42, 0.42) * size.x, 0.02, randf_range(-0.42, 0.42) * size.y)


func _process(delta: float) -> void:
	if _fish.is_empty():
		return
	_time += delta
	for i in _fish.size():
		var o: Array = _orbits[i]
		var t: float = _time * o[2] + o[3]
		var pos := Vector3(cos(t) * o[0], o[4] + sin(_time * 0.8 + o[3]) * 0.03, sin(t * 1.3) * o[1])
		var ahead := Vector3(cos(t + 0.1) * o[0], pos.y, sin((t + 0.1) * 1.3) * o[1])
		_fish[i].position = pos
		var dir := ahead - pos
		if dir.length() > 0.001:
			_fish[i].rotation.y = atan2(dir.x, dir.z)
