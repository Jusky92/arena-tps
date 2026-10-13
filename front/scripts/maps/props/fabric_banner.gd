@tool
class_name FabricBanner
extends Node3D
## Tissu suspendu qui ondule au vent. Deux formes :
##   NOREN  : petit rideau fendu au-dessus d'une porte d'échoppe ;
##   NOBORI : bannière verticale tendue sur une hampe (entrée, sanctuaire).
##
## Le tissu est une grille de sommets déformée à chaque image (pas de physique) :
## c'est léger et ça suffit largement pour du décor.

enum Kind { NOREN, NOBORI }

@export var kind: Kind = Kind.NOREN
@export var size := Vector2(2.4, 0.9)
@export var color := Color(0.1, 0.12, 0.2)
@export var text := ""
@export var text_color := Color(0.95, 0.92, 0.85)
@export var wind := 1.0
@export var phase := 0.0

const COLUMNS := 10
const ROWS := 5

var _mesh_instance: MeshInstance3D
var _immediate: ImmediateMesh
var _time := 0.0
var _material: StandardMaterial3D


func _ready() -> void:
	for child in get_children():
		child.queue_free()
	_material = StandardMaterial3D.new()
	_material.albedo_color = color
	_material.roughness = 0.95
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED      # tissu visible des deux côtés

	_immediate = ImmediateMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _immediate
	_mesh_instance.material_override = _material
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)

	if kind == Kind.NOBORI:
		# Hampe en bois le long du bord gauche + traverse en haut.
		var pole := StandardMaterial3D.new()
		pole.albedo_color = Color(0.3, 0.21, 0.14)
		_cylinder(Vector3(-size.x * 0.5 - 0.04, size.y * 0.5 - 0.6, 0), 0.04, size.y + 1.2, pole)
		_cylinder(Vector3(0, size.y * 0.5 + 0.02, 0), 0.03, size.x, pole, true)

	if not text.is_empty():
		var label := Label3D.new()
		label.text = text
		label.font = JapaneseFont.font()
		label.font_size = 72
		label.pixel_size = size.y * (0.0045 if kind == Kind.NOBORI else 0.0075)
		label.modulate = text_color
		label.outline_size = 0
		label.shaded = false
		label.double_sided = true
		label.position = Vector3(0, 0, 0.03)
		if kind == Kind.NOBORI:
			# Texte vertical : un caractère par ligne, comme sur une vraie bannière.
			var vertical := ""
			for i in text.length():
				vertical += text[i]
				if i < text.length() - 1:
					vertical += "\n"
			label.text = vertical
			label.position.y = size.y * 0.12
		add_child(label)
	_update_mesh()


func _process(delta: float) -> void:
	if _immediate == null:
		return
	_time += delta
	_update_mesh()


## Reconstruit la grille de tissu, déformée par une onde qui se propage.
func _update_mesh() -> void:
	_immediate.clear_surfaces()
	_immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in ROWS:
		for col in COLUMNS:
			# Noren : fente verticale au milieu (deux pans qui se séparent).
			if kind == Kind.NOREN and col == COLUMNS / 2 and row >= 1:
				continue
			_quad(col, row)
	_immediate.surface_end()


func _quad(col: int, row: int) -> void:
	var p00 := _point(col, row)
	var p10 := _point(col + 1, row)
	var p11 := _point(col + 1, row + 1)
	var p01 := _point(col, row + 1)
	for v in [p00, p10, p11, p00, p11, p01]:
		_immediate.surface_set_normal(Vector3.BACK)
		_immediate.surface_add_vertex(v)


## Position d'un sommet de la grille, avec l'ondulation du vent.
func _point(col: int, row: int) -> Vector3:
	var u := float(col) / COLUMNS
	var v := float(row) / ROWS
	var x := (u - 0.5) * size.x
	var y := size.y * 0.5 - v * size.y
	# L'amplitude augmente vers le bas (le haut est fixé à la tringle).
	var sway := sin(_time * 1.6 + u * 4.0 + phase) * 0.06 * wind * v
	var flap := sin(_time * 2.3 + v * 3.0 + phase * 0.7) * 0.03 * wind * v
	return Vector3(x + flap * 0.3, y + sway * 0.2, sway + flap)


func _cylinder(offset: Vector3, radius: float, height: float, material: Material, horizontal := false) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = material
	add_child(m)
	m.position = offset
	if horizontal:
		m.rotation.z = PI / 2.0
