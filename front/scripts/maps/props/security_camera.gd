@tool
class_name SecurityCamera
extends Node3D
## Caméra de surveillance connectée : elle balaie sa zone et suit le joueur le plus
## proche (groupe "players") quand il passe à portée. LED rouge qui clignote.

@export var sweep_angle := 55.0       ## amplitude du balayage (degrés)
@export var track_range := 28.0

var _pan: Node3D
var _tilt: Node3D
var _led: MeshInstance3D
var _time := 0.0
var _phase := 0.0


func _ready() -> void:
	for child in get_children():
		child.queue_free()
	_phase = randf() * TAU
	var body := _mat(Color(0.88, 0.89, 0.9), 0.3, 0.4)
	var dark := _mat(Color(0.1, 0.1, 0.12), 0.6, 0.3)
	_box(self, Vector3(0, 0, 0.12), Vector3(0.12, 0.12, 0.24), dark)          # support mural
	_pan = Node3D.new()
	add_child(_pan)
	_tilt = Node3D.new()
	_pan.add_child(_tilt)
	_tilt.position = Vector3(0, -0.12, 0)
	_box(_tilt, Vector3(0, 0, -0.12), Vector3(0.2, 0.18, 0.42), body)
	_box(_tilt, Vector3(0, 0.1, -0.16), Vector3(0.24, 0.02, 0.5), body)         # pare-soleil
	var lens := CylinderMesh.new()
	lens.top_radius = 0.06
	lens.bottom_radius = 0.07
	lens.height = 0.06
	var lens_node := MeshInstance3D.new()
	lens_node.mesh = lens
	lens_node.material_override = _mat(Color(0.05, 0.06, 0.1), 0.9, 0.05)
	_tilt.add_child(lens_node)
	lens_node.position = Vector3(0, 0, -0.35)
	lens_node.rotation_degrees = Vector3(90, 0, 0)
	_led = _box(_tilt, Vector3(0.07, 0.06, -0.33), Vector3(0.025, 0.025, 0.02), _glow(Color(1, 0.1, 0.1)))


func _process(delta: float) -> void:
	if _pan == null:
		return
	_time += delta
	_led.visible = fmod(_time + _phase, 1.0) < 0.5

	var wanted_yaw := deg_to_rad(sweep_angle) * sin(_time * 0.45 + _phase)
	var wanted_pitch := -0.35
	if not Engine.is_editor_hint():
		var target := _nearest_player()
		if target:
			var local := to_local(target.global_position + Vector3(0, 1.2, 0))
			wanted_yaw = atan2(-local.x, -local.z)
			wanted_pitch = atan2(local.y, Vector2(local.x, local.z).length())
	_pan.rotation.y = lerp_angle(_pan.rotation.y, wanted_yaw, minf(delta * 3.0, 1.0))
	_tilt.rotation.x = lerp_angle(_tilt.rotation.x, clampf(wanted_pitch, -1.2, 0.3), minf(delta * 3.0, 1.0))


func _nearest_player() -> Node3D:
	var best: Node3D = null
	var best_d := track_range
	for p in get_tree().get_nodes_in_group("players"):
		if not p.get("alive"):
			continue
		var d := global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


func _box(parent: Node3D, offset: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = material
	parent.add_child(m)
	m.position = offset
	return m


func _mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	return mat


func _glow(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 4.0
	return mat
