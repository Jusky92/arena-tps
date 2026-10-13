@tool
class_name PatrolDrone
extends Node3D
## Drone quadricoptère en patrouille : hélices qui tournent, feux de navigation,
## léger tangage dans la direction du vol. Trajectoire en cercle ou en "8".

@export var center := Vector3.ZERO
@export var radius := Vector2(15, 15)
@export var altitude := 9.0
@export var speed := 0.25            ## tours par minute / 60 (vitesse angulaire en rad/s)
@export var figure_eight := false
@export var phase := 0.0

var _body: Node3D
var _rotors: Array[Node3D] = []
var _strobe: MeshInstance3D
var _time := 0.0
var _last_pos := Vector3.ZERO


func _ready() -> void:
	for child in get_children():
		child.queue_free()
	add_to_group("iot_drone")
	_body = Node3D.new()
	add_child(_body)
	var shell := _mat(Color(0.15, 0.16, 0.18), 0.6, 0.3)
	var white := _mat(Color(0.9, 0.9, 0.92), 0.2, 0.4)
	_box(_body, Vector3.ZERO, Vector3(0.42, 0.14, 0.5), white)
	_box(_body, Vector3(0, -0.1, -0.12), Vector3(0.14, 0.12, 0.14), shell)       # nacelle caméra
	_box(_body, Vector3(0, -0.1, -0.2), Vector3(0.06, 0.06, 0.02), _glow(Color(0.2, 0.9, 1.0)))
	for i in 4:
		var corner := Vector3(0.42 if i % 2 == 0 else -0.42, 0.04, 0.42 if i < 2 else -0.42)
		var arm := _box(_body, corner * 0.5, Vector3(0.06, 0.04, 0.62), shell)
		arm.rotation.y = atan2(corner.x, corner.z)
		_cylinder(_body, corner + Vector3(0, -0.02, 0), 0.05, 0.1, shell)
		var rotor := Node3D.new()
		_body.add_child(rotor)
		rotor.position = corner + Vector3(0, 0.06, 0)
		_box(rotor, Vector3.ZERO, Vector3(0.5, 0.01, 0.05), _mat(Color(0.2, 0.2, 0.22, 0.85), 0.2, 0.5))
		_rotors.append(rotor)
		# Feux : rouge à gauche, vert à droite.
		_box(_body, corner + Vector3(0, -0.06, 0), Vector3(0.04, 0.04, 0.04), _glow(Color(1, 0.15, 0.1) if corner.x < 0 else Color(0.2, 1, 0.3)))
	_strobe = _box(_body, Vector3(0, 0.09, 0.1), Vector3(0.05, 0.03, 0.05), _glow(Color(1, 1, 1)))


func _process(delta: float) -> void:
	if _body == null:
		return
	_time += delta
	var t := _time * speed + phase
	var offset := Vector3(cos(t) * radius.x, 0, sin(t * (2.0 if figure_eight else 1.0)) * radius.y)
	var pos := center + offset + Vector3(0, altitude + sin(_time * 1.3 + phase) * 0.3, 0)
	position = pos
	var velocity := (pos - _last_pos) / maxf(delta, 0.001)
	_last_pos = pos
	if velocity.length() > 0.1:
		var yaw := atan2(-velocity.x, -velocity.z)
		rotation.y = lerp_angle(rotation.y, yaw, minf(delta * 2.0, 1.0))
	_body.rotation.x = lerpf(_body.rotation.x, -0.18, minf(delta * 2.0, 1.0))
	for r in _rotors:
		r.rotate_y(delta * 40.0)
	_strobe.visible = fmod(_time + phase, 1.2) < 0.08


func _box(parent: Node3D, offset: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = material
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	m.position = offset
	return m


func _cylinder(parent: Node3D, offset: Vector3, radius_m: float, height: float, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius_m
	mesh.bottom_radius = radius_m
	mesh.height = height
	mesh.radial_segments = 12
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = material
	parent.add_child(m)
	m.position = offset


func _mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


func _glow(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 5.0
	return mat
