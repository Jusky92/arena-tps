@tool
class_name VendingMachine
extends Node3D
## Distributeur de boissons (jidōhanbaiki) : la vitrine éclairée, les rangées de
## canettes et les étiquettes « chaud / froid ». C'est un abri solide pour le joueur.
##
## L'objet crée sa propre collision : on ne peut pas le traverser.

@export var body_color := Color(0.85, 0.12, 0.18)
@export var size := Vector3(1.1, 1.9, 0.75)
## Clignote légèrement, comme un vieux néon.
@export var flicker := true

var _screen: MeshInstance3D
var _time := 0.0
var _phase := 0.0


func _ready() -> void:
	for child in get_children():
		child.queue_free()
	_phase = randf() * TAU

	var shell := StandardMaterial3D.new()
	shell.albedo_color = body_color
	shell.roughness = 0.45
	shell.metallic = 0.25
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.08, 0.1)

	# Carrosserie + collision.
	var body := StaticBody3D.new()
	add_child(body)
	body.position.y = size.y * 0.5
	_box(body, Vector3.ZERO, size, shell)
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)

	# Vitrine éclairée (face -Z).
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(1.0, 0.97, 0.9)
	glass.emission_enabled = true
	glass.emission = Color(1.0, 0.95, 0.82)
	glass.emission_energy_multiplier = 2.2
	_screen = _box(body, Vector3(0, size.y * 0.1, -size.z * 0.5 - 0.01),
		Vector3(size.x * 0.82, size.y * 0.62, 0.02), glass)

	# Rangées de canettes derrière la vitre.
	var colors: Array[Color] = [Color(0.95, 0.25, 0.2), Color(0.15, 0.5, 0.9), Color(0.95, 0.75, 0.1),
		Color(0.2, 0.7, 0.35), Color(0.9, 0.9, 0.95), Color(0.6, 0.3, 0.8)]
	for row in 3:
		for col in 4:
			var can := StandardMaterial3D.new()
			can.albedo_color = colors[(row * 4 + col) % colors.size()]
			can.emission_enabled = true
			can.emission = can.albedo_color
			can.emission_energy_multiplier = 0.6
			_box(body, Vector3(-size.x * 0.3 + col * size.x * 0.2,
				size.y * 0.3 - row * size.y * 0.19, -size.z * 0.5 - 0.02),
				Vector3(size.x * 0.13, size.y * 0.12, 0.02), can)
			# Étiquette de prix sous chaque canette.
			var tag := _label("￥130", 26, Color(0.1, 0.1, 0.12))
			tag.position = Vector3(-size.x * 0.3 + col * size.x * 0.2,
				size.y * 0.3 - row * size.y * 0.19 - size.y * 0.08, -size.z * 0.5 - 0.03)
			body.add_child(tag)

	# Bandeaux « chaud » (rouge) et « froid » (bleu).
	var hot := _label("あたたかい", 40, Color(1.0, 0.35, 0.3))
	hot.position = Vector3(-size.x * 0.22, size.y * 0.45, -size.z * 0.5 - 0.02)
	body.add_child(hot)
	var cold := _label("つめたい", 40, Color(0.45, 0.8, 1.0))
	cold.position = Vector3(size.x * 0.24, size.y * 0.45, -size.z * 0.5 - 0.02)
	body.add_child(cold)

	# Bac de récupération et fente à monnaie.
	_box(body, Vector3(0, -size.y * 0.38, -size.z * 0.5 - 0.02), Vector3(size.x * 0.4, size.y * 0.1, 0.03), dark)
	_box(body, Vector3(size.x * 0.33, size.y * 0.02, -size.z * 0.5 - 0.02), Vector3(size.x * 0.1, size.y * 0.22, 0.03), dark)

	if not Engine.is_editor_hint():
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.95, 0.85)
		light.light_energy = 1.6
		light.omni_range = 6.0
		light.shadow_enabled = false
		body.add_child(light)
		light.position = Vector3(0, 0.2, -1.0)


func _process(delta: float) -> void:
	if not flicker or _screen == null:
		return
	_time += delta
	# Très léger battement de la lumière (néon fatigué).
	var m: StandardMaterial3D = _screen.material_override
	m.emission_energy_multiplier = 2.2 + sin(_time * 7.0 + _phase) * 0.12


func _label(text: String, font_size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = JapaneseFont.font()
	l.font_size = font_size
	l.pixel_size = 0.0016
	l.modulate = color
	l.outline_size = 0
	l.shaded = false
	l.rotation.y = PI       # lisible depuis la face avant (-Z)
	return l


func _box(parent: Node3D, offset: Vector3, box_size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = material
	parent.add_child(m)
	m.position = offset
	return m
