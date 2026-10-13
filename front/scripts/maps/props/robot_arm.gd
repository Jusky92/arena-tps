@tool
class_name RobotArm
extends Node3D
## Bras robotique industriel à 6 axes (décor IoT) : base, rotation, épaule, coude,
## poignet et pince. Il enchaîne tout seul un cycle "prendre / déplacer / poser".

@export var arm_scale := 1.0
@export var phase_offset := 0.0      ## décale le cycle pour que deux bras ne soient pas synchronisés
@export var cycle_speed := 1.0

# Poses : [rotation base, épaule, coude, poignet, ouverture pince (1 = ouverte), porte une caisse].
const POSES := [
	[-0.7, 0.35, 1.25, 0.75, 1.0, false],
	[-0.7, 0.8, 1.35, 0.85, 1.0, false],
	[-0.7, 0.8, 1.35, 0.85, 0.0, true],
	[-0.7, 0.3, 1.1, 0.9, 0.0, true],
	[0.75, 0.3, 1.1, 0.9, 0.0, true],
	[0.75, 0.8, 1.35, 0.85, 0.0, true],
	[0.75, 0.8, 1.35, 0.85, 1.0, false],
	[0.75, 0.3, 1.15, 0.8, 1.0, false],
]
const STEP_TIME := 1.1

var _yaw: Node3D
var _shoulder: Node3D
var _elbow: Node3D
var _wrist: Node3D
var _fingers: Array[Node3D] = []
var _cargo: Node3D
var _time := 0.0


func _ready() -> void:
	for child in get_children():
		child.queue_free()
	_build()


func _build() -> void:
	var s := arm_scale
	var orange := _material(Color(0.95, 0.45, 0.08), 0.35, 0.4)
	var dark := _material(Color(0.12, 0.12, 0.14), 0.7, 0.35)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.1, 0.5, 0.6)
	glow.emission_enabled = true
	glow.emission = Color(0.2, 0.9, 1.0)
	glow.emission_energy_multiplier = 3.0

	_cylinder(self, Vector3(0, 0.12, 0) * s, 0.45 * s, 0.24 * s, dark)
	_cylinder(self, Vector3(0, 0.245, 0) * s, 0.47 * s, 0.03 * s, _material(Color(0.95, 0.75, 0.1), 0.2, 0.6))
	_yaw = _pivot(self, Vector3(0, 0.25, 0) * s)
	_cylinder(_yaw, Vector3(0, 0.17, 0) * s, 0.32 * s, 0.34 * s, orange)
	_cylinder(_yaw, Vector3(0, 0.35, 0) * s, 0.25 * s, 0.03 * s, glow)

	_shoulder = _pivot(_yaw, Vector3(0, 0.5, 0) * s)
	_cylinder(_shoulder, Vector3.ZERO, 0.19 * s, 0.46 * s, dark, Vector3(0, 0, 90))
	_box(_shoulder, Vector3(0, 0.5, 0) * s, Vector3(0.22, 1.0, 0.24) * s, orange)
	_box(_shoulder, Vector3(0.115, 0.5, 0) * s, Vector3(0.01, 0.7, 0.04) * s, glow)

	_elbow = _pivot(_shoulder, Vector3(0, 1.0, 0) * s)
	_cylinder(_elbow, Vector3.ZERO, 0.15 * s, 0.36 * s, dark, Vector3(0, 0, 90))
	_box(_elbow, Vector3(0, 0.42, 0) * s, Vector3(0.17, 0.84, 0.17) * s, orange)

	_wrist = _pivot(_elbow, Vector3(0, 0.85, 0) * s)
	_cylinder(_wrist, Vector3.ZERO, 0.1 * s, 0.24 * s, dark, Vector3(0, 0, 90))
	_box(_wrist, Vector3(0, 0.1, 0) * s, Vector3(0.2, 0.06, 0.14) * s, dark)
	for side in [-1.0, 1.0]:
		var finger := _pivot(_wrist, Vector3(side * 0.06, 0.13, 0) * s)
		_box(finger, Vector3(0, 0.07, 0) * s, Vector3(0.03, 0.15, 0.06) * s, _material(Color(0.7, 0.72, 0.76), 0.8, 0.3))
		_fingers.append(finger)
	_cargo = _box(_wrist, Vector3(0, 0.27, 0) * s, Vector3(0.24, 0.24, 0.24) * s, _material(Color(0.2, 0.45, 0.85), 0.2, 0.5))


func _process(delta: float) -> void:
	if _yaw == null:
		return
	_time += delta * cycle_speed
	var total := STEP_TIME * POSES.size()
	var t := fmod(_time + phase_offset * total, total) / STEP_TIME
	var i := int(t)
	var a: Array = POSES[i]
	var b: Array = POSES[(i + 1) % POSES.size()]
	var k := smoothstep(0.0, 1.0, t - i)
	_yaw.rotation.y = lerpf(a[0], b[0], k)
	_shoulder.rotation.x = -lerpf(a[1], b[1], k)
	_elbow.rotation.x = -lerpf(a[2], b[2], k)
	_wrist.rotation.x = -lerpf(a[3], b[3], k)
	var grip := lerpf(a[4], b[4], k)
	for j in _fingers.size():
		_fingers[j].position.x = (-1.0 if j == 0 else 1.0) * lerpf(0.035, 0.09, grip) * arm_scale
	_cargo.visible = a[5] and (b[5] or k < 0.5)


# --------------------------------------------------------------------------- briques

func _pivot(parent: Node3D, offset: Vector3) -> Node3D:
	var n := Node3D.new()
	parent.add_child(n)
	n.position = offset
	return n


func _box(parent: Node3D, offset: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = material
	parent.add_child(m)
	m.position = offset
	return m


func _cylinder(parent: Node3D, offset: Vector3, radius: float, height: float, material: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 20
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = material
	parent.add_child(m)
	m.position = offset
	m.rotation_degrees = rot
	return m


func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	return mat
