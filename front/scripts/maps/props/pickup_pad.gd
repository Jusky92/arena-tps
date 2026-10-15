class_name PickupPad
extends Node3D
## Socle lumineux d'un bonus : disque néon au sol et objet flottant qui tourne.
## Quand le bonus a été pris, l'objet disparaît et le disque s'assombrit jusqu'à
## sa réapparition. Purement visuel : c'est PickupDirector qui décide.

var kind := 0
var _item: Node3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _light: OmniLight3D
var _time := 0.0
var _available := true


func _ready() -> void:
	var color := Pickups.color_of(kind)
	_time = randf() * TAU
	# Socle de pierre et anneau néon.
	var base := MeshInstance3D.new()
	base.mesh = PartMesh.shape(Vector3(1.6, 0.16, 1.6), 1.0, 0.3)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.18, 0.19, 0.22)
	stone.roughness = 0.6
	base.material_override = stone
	base.position.y = 0.08
	add_child(base)
	_ring = MeshInstance3D.new()
	_ring.mesh = PartMesh.shape(Vector3(1.45, 0.04, 1.45), 1.0)
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = color
	_ring.material_override = _ring_mat
	_ring.position.y = 0.17
	add_child(_ring)
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.light_energy = 1.4
	_light.omni_range = 3.5
	_light.position.y = 1.0
	add_child(_light)
	_item = _build_item(kind, color)
	_item.position.y = 1.0
	add_child(_item)
	var label := Label3D.new()
	label.text = Pickups.name_of(kind).to_upper()
	label.font_size = 40
	label.pixel_size = 0.006
	label.outline_size = 8
	label.modulate = color.lightened(0.3)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.position.y = 1.85
	add_child(label)


func set_available(value: bool) -> void:
	_available = value
	if _item:
		_item.visible = value
		_light.visible = value
		_ring_mat.albedo_color = Pickups.color_of(kind) * (1.0 if value else 0.25)


func _process(delta: float) -> void:
	if _item == null or not _available:
		return
	_time += delta
	_item.rotation.y += delta * 1.6
	_item.position.y = 1.0 + sin(_time * 2.4) * 0.12


## Objet flottant reconnaissable selon le bonus (formes arrondies, néon).
static func _build_item(kind: int, color: Color) -> Node3D:
	var root := Node3D.new()
	var glow := StandardMaterial3D.new()
	glow.albedo_color = color * 0.6
	glow.emission_enabled = true
	glow.emission = color
	glow.emission_energy_multiplier = 2.2
	var parts := []
	match kind:
		Pickups.Kind.HEAL:          # croix
			parts = [[Vector3(0.55, 0.18, 0.18), Vector3.ZERO], [Vector3(0.18, 0.55, 0.18), Vector3.ZERO]]
		Pickups.Kind.ARMOR:         # bouclier
			parts = [[Vector3(0.5, 0.6, 0.14), Vector3.ZERO], [Vector3(0.3, 0.3, 0.16), Vector3(0, -0.28, 0)]]
		Pickups.Kind.DOUBLE_JUMP:   # deux flèches vers le haut
			parts = [[Vector3(0.4, 0.14, 0.14), Vector3(0, -0.12, 0)], [Vector3(0.4, 0.14, 0.14), Vector3(0, 0.16, 0)],
				[Vector3(0.12, 0.5, 0.12), Vector3.ZERO]]
		Pickups.Kind.SPEED:         # éclair
			parts = [[Vector3(0.14, 0.4, 0.14), Vector3(-0.06, 0.15, 0)], [Vector3(0.14, 0.4, 0.14), Vector3(0.06, -0.15, 0)]]
		Pickups.Kind.SUPER:         # étoile : trois anneaux croisés
			parts = [[Vector3(0.42, 0.42, 0.42), Vector3.ZERO]]
		_:                          # arme spéciale : caisse lumineuse
			parts = [[Vector3(0.7, 0.3, 0.3), Vector3.ZERO], [Vector3(0.2, 0.2, 0.32), Vector3(0.28, 0, 0)]]
	for p in parts:
		var mesh := MeshInstance3D.new()
		mesh.mesh = PartMesh.shape(p[0], 0.75)
		mesh.material_override = glow
		mesh.position = p[1]
		root.add_child(mesh)
	if kind == Pickups.Kind.SPEED:
		root.get_child(0).rotation_degrees.z = -25
		root.get_child(1).rotation_degrees.z = -25
	return root
