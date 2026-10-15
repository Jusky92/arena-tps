@tool
class_name IotDashboard
extends Node3D
## Grand écran "LAB IoT · CFA INSTA" fixé sur l'entrepôt : il affiche en direct une
## température et un taux de CO2 simulés, les caméras en ligne, le nombre de joueurs
## détectés et un faux débit de messages MQTT.

@export var size := Vector2(8.0, 3.2)

var _lines: Array[Label3D] = []
var _time := 0.0
var _messages := 1200.0
var _footer: Label3D


func _ready() -> void:
	for child in get_children():
		child.queue_free()
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.08, 0.09, 0.11)
	frame.metallic = 0.6
	_box(Vector3(0, 0, 0.05), Vector3(size.x + 0.3, size.y + 0.3, 0.12), frame)
	var screen := StandardMaterial3D.new()
	screen.albedo_color = Color(0.01, 0.02, 0.04)
	screen.emission_enabled = true
	screen.emission = Color(0.02, 0.08, 0.14)
	screen.emission_energy_multiplier = 1.0
	_box(Vector3(0, 0, -0.02), Vector3(size.x, size.y, 0.02), screen)

	var title := _text("LAB IoT · CFA INSTA", Vector3(0, size.y * 0.5 - 0.42, -0.04), 92, Color(0.25, 2.2, 2.6))
	title.font = load("res://assets/fonts/Orbitron.ttf")
	for i in 4:
		var row := i / 2
		var col := i % 2
		var pos := Vector3(-size.x * 0.25 + col * size.x * 0.5, 0.35 - row * 0.85, -0.04)
		_lines.append(_text("", pos, 56, Color(1.6, 1.7, 1.9)))
	_footer = _text("", Vector3(0, -size.y * 0.5 + 0.28, -0.04), 40, Color(0.9, 0.5, 1.6))
	_refresh()


func _process(delta: float) -> void:
	if _lines.is_empty():
		return
	_time += delta
	_messages += randf_range(-30, 30) * delta
	if fmod(_time, 1.0) < delta:
		_refresh()


func _refresh() -> void:
	var players := 0
	var cameras := 0
	if is_inside_tree():
		cameras = get_tree().get_nodes_in_group("security_camera").size()
		if not Engine.is_editor_hint():
			players = get_tree().get_nodes_in_group("players").filter(func(p): return p.alive).size()
	# Mesures simulées : elles varient doucement pour que l'écran vive.
	var temperature := 21.5 + sin(_time * 0.05) * 1.8
	var co2 := 620.0 + sin(_time * 0.11) * 60.0
	_lines[0].text = "T° extérieure  %.1f °C" % temperature
	_lines[1].text = "CO2  %d ppm" % int(co2)
	_lines[2].text = "Caméras en ligne  %d / %d" % [cameras, cameras]
	_lines[3].text = "Joueurs détectés  %d" % players
	_footer.text = "MQTT · lab-iot.cfa-insta.local · %d msg/min" % int(_messages)


func _text(text: String, pos: Vector3, font_size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = 0.006
	l.modulate = color
	l.outline_size = 0
	l.shaded = false
	l.position = pos
	l.rotation.y = PI       # lisible depuis l'avant (-Z de l'écran)
	add_child(l)
	return l


func _box(offset: Vector3, box_size: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = material
	add_child(m)
	m.position = offset
