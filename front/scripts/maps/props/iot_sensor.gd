@tool
class_name IotSensor
extends Node3D
## Capteur connecté (décor IoT) : boîtier, antenne, LED qui clignote à chaque envoi
## de mesure, et petit afficheur avec la valeur en direct.
## Le capteur de présence compte vraiment les joueurs à moins de 10 m.

enum Kind { TEMPERATURE, HUMIDITY, CO2, NOISE, LIGHT, PRESENCE, WIND }

@export var kind: Kind = Kind.TEMPERATURE
@export var show_display := true

const INFO := {
	Kind.TEMPERATURE: ["T°", "°C", 21.5, 0.3, Color(1.0, 0.55, 0.2)],
	Kind.HUMIDITY: ["HUM", "%", 47.0, 1.5, Color(0.3, 0.7, 1.0)],
	Kind.CO2: ["CO2", "ppm", 620.0, 25.0, Color(0.5, 1.0, 0.4)],
	Kind.NOISE: ["BRUIT", "dB", 55.0, 4.0, Color(1.0, 0.35, 0.8)],
	Kind.LIGHT: ["LUX", "lx", 840.0, 40.0, Color(1.0, 0.9, 0.3)],
	Kind.PRESENCE: ["PRÉSENCE", "", 0.0, 0.0, Color(0.2, 0.95, 1.0)],
	Kind.WIND: ["VENT", "km/h", 14.0, 2.0, Color(0.7, 0.85, 1.0)],
}

var value := 0.0
var _led: MeshInstance3D
var _label: Label3D
var _next_send := 0.0
var _time := 0.0
var _flash := 0.0


var _cups: Node3D


func _ready() -> void:
	for child in get_children():
		child.queue_free()
	add_to_group("iot_sensor")
	var info: Array = INFO[kind]
	value = info[2]
	_next_send = randf() * 2.0
	var case_mat := StandardMaterial3D.new()
	case_mat.albedo_color = Color(0.9, 0.91, 0.93)
	case_mat.roughness = 0.5
	_box(Vector3(0, 0, 0), Vector3(0.22, 0.3, 0.1), case_mat)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.08, 0.1)
	_box(Vector3(0.07, 0.24, 0.02), Vector3(0.015, 0.2, 0.015), dark)             # antenne
	_box(Vector3(0, 0.05, -0.052), Vector3(0.14, 0.08, 0.005), dark)              # écran
	var led_mat := StandardMaterial3D.new()
	led_mat.albedo_color = info[4]
	led_mat.emission_enabled = true
	led_mat.emission = info[4]
	led_mat.emission_energy_multiplier = 5.0
	_led = _box(Vector3(-0.07, -0.1, -0.053), Vector3(0.025, 0.025, 0.01), led_mat)
	if kind == Kind.WIND:
		# Anémomètre : trois coupelles qui tournent au-dessus du boîtier.
		_cups = Node3D.new()
		add_child(_cups)
		_cups.position = Vector3(0, 0.42, 0)
		for i in 3:
			var arm := _box(Vector3.ZERO, Vector3(0.02, 0.02, 0.3), dark)
			arm.reparent(_cups, false)
			arm.rotation.y = TAU * i / 3.0
			arm.position = Vector3(sin(TAU * i / 3.0), 0, cos(TAU * i / 3.0)) * 0.15
			var cup := _box(Vector3.ZERO, Vector3(0.07, 0.07, 0.07), case_mat)
			cup.reparent(_cups, false)
			cup.position = Vector3(sin(TAU * i / 3.0), 0, cos(TAU * i / 3.0)) * 0.3
	if show_display:
		_label = Label3D.new()
		_label.pixel_size = 0.0022
		_label.font_size = 40
		_label.outline_size = 8
		_label.modulate = (info[4] as Color) * 1.6
		_label.position = Vector3(0, 0.62 if kind == Kind.WIND else 0.32, 0)
		_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		add_child(_label)
	_update_label()


func _process(delta: float) -> void:
	if _led == null:
		return
	_time += delta
	_next_send -= delta
	if _next_send <= 0.0:
		_next_send = randf_range(1.0, 2.5)
		_measure()
		_flash = 0.15
	_flash -= delta
	if _cups:
		_cups.rotate_y(delta * (2.0 + value * 0.25))
	_led.visible = _flash > 0.0 or fmod(_time, 3.0) < 0.05


## Nouvelle mesure (petite variation aléatoire autour d'une valeur de base).
func _measure() -> void:
	var info: Array = INFO[kind]
	if kind == Kind.PRESENCE:
		var count := 0
		if not Engine.is_editor_hint():
			for p in get_tree().get_nodes_in_group("players"):
				if p.get("alive") and global_position.distance_to(p.global_position) < 10.0:
					count += 1
		value = count
	else:
		value = clampf(value + randf_range(-1.0, 1.0) * info[3], info[2] - info[3] * 6.0, info[2] + info[3] * 6.0)
	_update_label()


func _update_label() -> void:
	if _label == null:
		return
	var info: Array = INFO[kind]
	if kind == Kind.PRESENCE:
		_label.text = "%s : %d" % [info[0], int(value)]
	elif value >= 100.0:
		_label.text = "%s %d %s" % [info[0], int(value), info[1]]
	else:
		_label.text = "%s %.1f %s" % [info[0], value, info[1]]


func _box(offset: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = material
	add_child(m)
	m.position = offset
	return m
