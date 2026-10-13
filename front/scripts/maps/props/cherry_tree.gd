@tool
class_name CherryTree
extends Node3D
## Cerisier en fleurs (sakura) : tronc incliné, branches, grappes de fleurs roses
## et pétales qui tombent en tourbillonnant.
##
## L'arbre est construit par code : la forme change avec `seed_value`, donc deux
## arbres côte à côte ne se ressemblent pas.

@export var height := 6.0
@export var seed_value := 0
@export var petals := true
## Teinte des fleurs (rose clair par défaut, blanc pour un arbre plus pâle).
@export var blossom_color := Color(1.0, 0.72, 0.82)

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	for child in get_children():
		child.queue_free()
	_rng.seed = seed_value * 7919 + 13

	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.24, 0.17, 0.14)
	bark.roughness = 0.95
	var blossom := StandardMaterial3D.new()
	blossom.albedo_color = blossom_color
	blossom.roughness = 0.8
	# Les fleurs renvoient un peu de lumière : l'arbre reste clair à l'ombre.
	blossom.emission_enabled = true
	blossom.emission = blossom_color * 0.35
	blossom.emission_energy_multiplier = 0.4

	# Tronc légèrement penché.
	var lean := Vector3(_rng.randf_range(-0.12, 0.12), 0, _rng.randf_range(-0.12, 0.12))
	var trunk_top := Vector3(0, height * 0.55, 0) + lean * height
	_branch(Vector3.ZERO, trunk_top, height * 0.075, bark)

	# 4 à 6 branches principales, chacune avec une grappe de fleurs au bout.
	var count := _rng.randi_range(4, 6)
	for i in count:
		var angle := TAU * i / count + _rng.randf_range(-0.3, 0.3)
		var length := height * _rng.randf_range(0.34, 0.5)
		var tip := trunk_top + Vector3(cos(angle), _rng.randf_range(0.5, 0.95), sin(angle)).normalized() * length
		_branch(trunk_top, tip, height * 0.03, bark)
		_blossom_cluster(tip, height * _rng.randf_range(0.2, 0.28), blossom)
	_blossom_cluster(trunk_top + Vector3(0, height * 0.22, 0), height * 0.26, blossom)

	if petals and not Engine.is_editor_hint():
		_add_petals(blossom_color)


## Segment de bois entre deux points (tronc ou branche).
func _branch(from: Vector3, to: Vector3, radius: float, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.7
	mesh.bottom_radius = radius
	mesh.height = from.distance_to(to)
	mesh.radial_segments = 7
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = material
	add_child(m)
	m.position = (from + to) * 0.5
	# Le cylindre est vertical par défaut : on le bascule de Y vers la direction voulue.
	var dir := (to - from).normalized()
	var axis := Vector3.UP.cross(dir)
	if axis.length() > 0.001:
		m.basis = Basis(axis.normalized(), acos(clampf(Vector3.UP.dot(dir), -1.0, 1.0)))


## Grappe de fleurs : plusieurs sphères aplaties qui se chevauchent.
func _blossom_cluster(center: Vector3, radius: float, material: Material) -> void:
	for i in 5:
		var mesh := SphereMesh.new()
		mesh.radius = radius * _rng.randf_range(0.6, 1.0)
		mesh.height = mesh.radius * 1.5
		mesh.radial_segments = 10
		mesh.rings = 6
		var m := MeshInstance3D.new()
		m.mesh = mesh
		m.material_override = material
		add_child(m)
		m.position = center + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.4, 0.5), _rng.randf_range(-1, 1)) * radius * 0.8


## Pluie de pétales sous la couronne.
func _add_petals(color: Color) -> void:
	var particles := CPUParticles3D.new()
	particles.amount = 34
	particles.lifetime = 6.0
	particles.preprocess = 3.0
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = height * 0.42
	particles.direction = Vector3.DOWN
	particles.spread = 25.0
	particles.gravity = Vector3(0.25, -0.5, 0.1)      # chute lente, portée par le vent
	particles.initial_velocity_min = 0.1
	particles.initial_velocity_max = 0.4
	particles.angular_velocity_min = -120.0
	particles.angular_velocity_max = 120.0
	particles.scale_amount_min = 0.07
	particles.scale_amount_max = 0.13
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.5, 0.34)
	particles.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color * 0.4
	mat.emission_energy_multiplier = 0.25
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	particles.mesh.material = mat
	add_child(particles)
	particles.position.y = height * 0.72
