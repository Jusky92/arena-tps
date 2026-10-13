@tool
class_name Conveyor
extends Node3D
## Tapis roulant (décor du LAB IoT) : des caisses défilent en boucle le long du tapis.
## Le tapis est orienté selon l'axe X local, de longueur `length`.

@export var length := 14.0
@export var speed := 0.9
@export var box_count := 6

var _boxes: Array[Node3D] = []
var _time := 0.0


func _ready() -> void:
	for child in get_children():
		child.queue_free()
	_boxes.clear()
	var colors := [Color(0.2, 0.45, 0.85), Color(0.95, 0.45, 0.08), Color(0.85, 0.85, 0.88)]
	for i in box_count:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = colors[i % colors.size()]
		mat.roughness = 0.55
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.34, 0.3, 0.34)
		var b := MeshInstance3D.new()
		b.mesh = mesh
		b.material_override = mat
		add_child(b)
		_boxes.append(b)


func _process(delta: float) -> void:
	_time += delta
	for i in _boxes.size():
		var x := fmod(_time * speed + float(i) / _boxes.size() * length, length) - length * 0.5
		_boxes[i].position = Vector3(x, 0.16, 0)
		var edge := minf(x + length * 0.5, length * 0.5 - x)
		_boxes[i].scale = Vector3.ONE * clampf(edge / 0.4, 0.01, 1.0)   # apparition / disparition aux bouts
