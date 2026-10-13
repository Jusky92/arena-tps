@tool
class_name PaperLantern
extends Node3D
## Lanterne en papier (chōchin) suspendue : elle oscille doucement, éclaire autour
## d'elle et porte un caractère peint sur le flanc.
##
## Sert partout dans la map : entrée du sanctuaire, échoppes, ruelle, jardin.

@export var radius := 0.26
@export var lantern_height := 0.5
@export var text := "祭"
@export var color := Color(1.0, 0.45, 0.25)
## Longueur du fil de suspension (0 = posée).
@export var cord := 0.0
@export var with_light := true
## Décalage de l'oscillation, pour que deux lanternes voisines ne bougent pas pareil.
@export var phase := 0.0

var _body: Node3D
var _time := 0.0


func _ready() -> void:
	for child in get_children():
		child.queue_free()
	_body = Node3D.new()
	add_child(_body)
	_body.position.y = -cord

	if cord > 0.0:
		var dark := StandardMaterial3D.new()
		dark.albedo_color = Color(0.1, 0.09, 0.08)
		_cylinder(self, Vector3(0, -cord * 0.5, 0), 0.012, cord, dark)

	# Corps lumineux : sphère aplatie, papier translucide éclairé de l'intérieur.
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(1.0, 0.93, 0.8)
	paper.emission_enabled = true
	paper.emission = color
	paper.emission_energy_multiplier = 2.6
	paper.roughness = 0.9
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = lantern_height
	mesh.radial_segments = 16
	mesh.rings = 8
	var globe := MeshInstance3D.new()
	globe.mesh = mesh
	globe.material_override = paper
	globe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(globe)

	# Cerclages haut et bas.
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.12, 0.1, 0.09)
	_cylinder(_body, Vector3(0, lantern_height * 0.5, 0), radius * 0.45, 0.04, frame)
	_cylinder(_body, Vector3(0, -lantern_height * 0.5, 0), radius * 0.45, 0.04, frame)

	if not text.is_empty():
		var label := Label3D.new()
		label.text = text
		label.font = JapaneseFont.font()
		label.font_size = 64
		label.pixel_size = radius * 0.016
		label.modulate = Color(0.1, 0.05, 0.05)
		label.outline_size = 0
		label.shaded = false
		label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		label.position.z = radius * 0.92
		_body.add_child(label)

	if with_light and not Engine.is_editor_hint():
		var light := OmniLight3D.new()
		light.light_color = color
		light.light_energy = 1.4
		light.omni_range = 5.0
		light.shadow_enabled = false
		_body.add_child(light)


func _process(delta: float) -> void:
	if _body == null or cord <= 0.0:
		return
	_time += delta
	# Balancement très léger, comme sous une brise.
	_body.rotation.x = sin(_time * 0.9 + phase) * 0.05
	_body.rotation.z = cos(_time * 0.7 + phase * 1.3) * 0.04


func _cylinder(parent: Node3D, offset: Vector3, r: float, h: float, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = r
	mesh.bottom_radius = r
	mesh.height = h
	mesh.radial_segments = 10
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = material
	parent.add_child(m)
	m.position = offset
