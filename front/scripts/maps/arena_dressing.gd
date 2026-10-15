class_name ArenaDressing
extends RefCounted
## Habillage de la map NEO-EDO ajouté en phase 4 : verdure et couverts.
## Construit par ArenaMap.build() avec ses outils (_box, _mesh_box, _mat…).
##
## Verdure : carrés de pelouse aux teintes variées, touffes d'herbe (un seul
## MultiMesh : des milliers de touffes pour un seul appel de rendu), buissons ronds.
## Couverts : murets de pierre, jardinières, caisses, chariots, barrières néon,
## placés dans les zones ouvertes (vérifiées avec une carte d'occupation) et à
## plus de 3 m des points d'apparition.
##
## Repère : x = ouest (-) / est (+), z = nord (-) / sud (+), sol à y = 0.

## Pelouses : [x0, z0, x1, z1].
const LAWNS := [
	[-58, 44, -22, 58],     # sud-ouest, au pied de la pagode
	[14, 50, 58, 58],       # sud du jardin, le long du mur
	[50, 12, 58, 30],       # est du jardin
	[-58, -27, -24, -14],   # ouest du marché
]

## Teintes de pelouse (variations de couleur, carrés de 4 m).
const LAWN_TINTS := [Color(0.62, 0.62, 0.62), Color(0.5, 0.66, 0.5), Color(0.74, 0.68, 0.45), Color(0.56, 0.6, 0.66)]
## Couleurs des touffes d'herbe (vert tendre, vert profond, jaunâtre, quelques fleurs).
const TUFT_COLORS := [
	Color(0.36, 0.66, 0.24), Color(0.22, 0.48, 0.17), Color(0.56, 0.62, 0.26),
	Color(0.44, 0.74, 0.32), Color(0.3, 0.56, 0.2),
]
const FLOWER_COLORS := [Color(1.0, 0.72, 0.85), Color(1.0, 0.95, 0.75), Color(0.75, 0.82, 1.0)]

## Buissons ronds (couvert « doux », avec collision) : [x, z, taille].
const BUSHES := [
	[-52, 47, 1.4], [-38, 55, 1.6], [-30, 46, 1.3], [-24, 56, 1.5], [-46, 56, 1.2],
	[20, 54, 1.5], [30, 56, 1.3], [52, 21, 1.4], [55, 14, 1.2],
	[-56, -16, 1.3], [-34, -26, 1.5], [-48, -24, 1.2],
]

## Couverts. Types : "wall" (muret 4 m, accroupi), "planter" (jardinière + buisson,
## debout), "crates" (pile de caisses), "cart" (chariot du marché), "barrier"
## (barrière néon du labo). [type, x, z, rotation en degrés]
const COVERS := [
	# Nord-ouest : marché.
	["wall", -40, -22, 0], ["cart", -31, -17, 90], ["crates", -52, -20, 0], ["planter", -45, -30, 0],
	# Nord-est : cour du laboratoire.
	["planter", 26, -15, 0], ["planter", 38, -13, 0], ["planter", 50, -16, 0],
	["barrier", 32, -18, 0], ["barrier", 44, -12, 0],
	# Sud-ouest : pagode et pelouse.
	["wall", -50, 14, 0], ["planter", -28, 13, 0], ["crates", -20, 18, 0], ["wall", -45, 48, 90], ["cart", -32, 34, 0],
	# Sud-est : jardin.
	["wall", 28, 18, 0], ["planter", 40, 24, 0], ["planter", 50, 14, 0], ["crates", 22, 30, 0],
	# Ruelles : couverts bas pour traverser à l'abri.
	["wall", -4, -40, 90], ["wall", 4, -24, 0], ["wall", -3, 44, 90],
	["wall", -30, -4, 0], ["wall", 25, 4, 0], ["wall", 46, -3, 0],
]

const GRASS_PER_M2 := 2.4          # touffes par m² de pelouse
const WALL_BASE_GRASS := 320       # touffes au pied du mur d'enceinte


# =========================================================================== verdure

static func build_greenery(map: ArenaMap, root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42                      # toujours la même verdure (client et serveur)
	var grass: StandardMaterial3D = map._mat("grass")
	var tints := []
	for tint in LAWN_TINTS:
		var m: StandardMaterial3D = grass.duplicate()
		m.albedo_color = grass.albedo_color * tint
		tints.append(m)

	var tufts: Array[Transform3D] = []
	var colors: Array[Color] = []
	for lawn in LAWNS:
		var x0: float = lawn[0]
		var z0: float = lawn[1]
		var x1: float = lawn[2]
		var z1: float = lawn[3]
		# Carrés de 4 m aux teintes variées (pas de collision : le sol reste celui de la map).
		var x := x0
		while x < x1:
			var z := z0
			while z < z1:
				var w := minf(4.0, x1 - x)
				var d := minf(4.0, z1 - z)
				map._mesh_box(Vector3(x + w / 2, 0.015, z + d / 2), Vector3(w, 0.03, d), tints[rng.randi() % tints.size()], false)
				z += 4.0
			x += 4.0
		var count := int((x1 - x0) * (z1 - z0) * GRASS_PER_M2)
		for i in count:
			_add_tuft(tufts, colors, rng, Vector3(rng.randf_range(x0, x1), 0.03, rng.randf_range(z0, z1)))

	# Herbe folle au pied du mur d'enceinte, tout autour.
	var half := ArenaMap.HALF
	for i in WALL_BASE_GRASS:
		var along := rng.randf_range(-half + 2.0, half - 2.0)
		var inset := rng.randf_range(0.6, 1.8)
		var side := rng.randi() % 4
		var pos := [Vector3(along, 0, -half + inset), Vector3(along, 0, half - inset),
			Vector3(-half + inset, 0, along), Vector3(half - inset, 0, along)][side] as Vector3
		if absf(pos.x) < 4.0 or absf(pos.z) < 4.0:
			continue                   # pas devant les grandes portes
		_add_tuft(tufts, colors, rng, pos)

	var field := MultiMeshInstance3D.new()
	field.name = "Grass"
	field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _tuft_mesh()
	mm.instance_count = tufts.size()
	for i in tufts.size():
		mm.set_instance_transform(i, tufts[i])
		mm.set_instance_color(i, colors[i])
	field.multimesh = mm
	root.add_child(field)

	# Buissons ronds : plusieurs boules de feuillage, avec collision (couvert doux).
	var foliage: StandardMaterial3D = map._mat("foliage")
	for b in BUSHES:
		_bush(map, root, Vector3(b[0], 0, b[1]), b[2], foliage, rng)


static func _add_tuft(tufts: Array[Transform3D], colors: Array[Color], rng: RandomNumberGenerator, pos: Vector3) -> void:
	var scale := rng.randf_range(0.7, 1.4)
	var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(scale, scale * rng.randf_range(0.8, 1.3), scale))
	tufts.append(Transform3D(basis, pos))
	if rng.randf() < 0.06:
		colors.append(FLOWER_COLORS[rng.randi() % FLOWER_COLORS.size()])
	else:
		var c: Color = TUFT_COLORS[rng.randi() % TUFT_COLORS.size()]
		colors.append(c * rng.randf_range(0.85, 1.15))


## Une touffe : cinq brins effilés et arrondis, légèrement penchés.
static func _tuft_mesh() -> Mesh:
	var tool := SurfaceTool.new()
	for i in 5:
		var blade := PartMesh.shape(Vector3(0.06, 0.46, 0.02), 0.8, -1.0, Vector2(1.0, 0.1))
		var angle := TAU * i / 5.0
		var lean := Basis(Vector3.UP, angle) * Basis(Vector3.RIGHT, deg_to_rad(18.0))
		tool.append_from(blade, 0, Transform3D(lean, Vector3(cos(angle), 0, sin(angle)) * 0.05 + lean * Vector3(0, 0.23, 0)))
	var mesh := tool.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.roughness = 0.9
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, material)
	return mesh


static func _bush(map: ArenaMap, root: Node3D, pos: Vector3, size: float, foliage: StandardMaterial3D, rng: RandomNumberGenerator) -> void:
	for i in 3:
		var ball := MeshInstance3D.new()
		var s := size * rng.randf_range(0.7, 1.0)
		ball.mesh = PartMesh.shape(Vector3(s, s * 0.85, s), 1.0)
		var m: StandardMaterial3D = foliage.duplicate()
		m.albedo_color = foliage.albedo_color * rng.randf_range(0.8, 1.25)
		ball.material_override = m
		root.add_child(ball)
		ball.position = pos + Vector3(rng.randf_range(-0.35, 0.35) * size, s * 0.4, rng.randf_range(-0.35, 0.35) * size)
	map._collider_box(pos + Vector3(0, size * 0.45, 0), Vector3(size * 1.1, size * 0.9, size * 1.1))


# =========================================================================== couverts

static func build_cover(map: ArenaMap, root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for c in COVERS:
		var pos := Vector3(c[1], 0, c[2])
		var yaw := deg_to_rad(c[3])
		match c[0]:
			"wall":
				_low_wall(map, pos, yaw)
			"planter":
				_planter(map, root, pos, rng)
			"crates":
				map._crate(pos.x, pos.z, 0)
				map._crate(pos.x + 1.7, pos.z + 0.2, 0)
				map._crate(pos.x + 0.8, pos.z, 1)
			"cart":
				_cart(map, pos, yaw)
			"barrier":
				_barrier(map, pos, yaw)


## Muret de pierre de 4 m, assez haut pour se cacher accroupi (1,1 m).
static func _low_wall(map: ArenaMap, pos: Vector3, yaw: float) -> void:
	var size := Vector3(4.0, 1.1, 0.6)
	var body := map._box(pos + Vector3(0, size.y / 2, 0), size, map._mat("stone_grey"))
	body.rotation.y = yaw
	var cap := map._mesh_box(pos + Vector3(0, size.y + 0.06, 0), Vector3(4.2, 0.12, 0.75), map._mat("roof_tile_dark"))
	cap.rotation.y = yaw


## Jardinière de pierre avec un buisson : couvert debout (1,7 m en tout).
static func _planter(map: ArenaMap, root: Node3D, pos: Vector3, rng: RandomNumberGenerator) -> void:
	map._box(pos + Vector3(0, 0.45, 0), Vector3(2.4, 0.9, 2.4), map._mat("stone_grey"))
	map._mesh_box(pos + Vector3(0, 0.93, 0), Vector3(2.1, 0.06, 2.1), map._mat("grass"), false)
	_bush(map, root, pos + Vector3(0, 0.9, 0), 1.5, map._mat("foliage"), rng)


## Chariot de marché en bois : caisse sur roues, couvert accroupi.
static func _cart(map: ArenaMap, pos: Vector3, yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var body := map._box(pos + Vector3(0, 0.85, 0), Vector3(2.6, 1.0, 1.4), map._mat("wood_warm"))
	body.rotation.y = yaw
	for side in [-1.0, 1.0]:
		# Roue : cylindre couché (axe le long du côté du chariot), puis tourné avec lui.
		map._mesh_cylinder_at(pos + basis * Vector3(side * 0.9, 0.38, 0.75), 0.38, 0.12,
			map._mat("wood_dark"), Vector3(PI / 2, yaw, 0))
	var handle := map._mesh_box(pos + basis * Vector3(1.7, 1.0, 0), Vector3(1.0, 0.08, 0.9), map._mat("wood_dark"))
	handle.rotation.y = yaw


## Barrière de chantier du labo : béton avec un liseré néon cyan.
static func _barrier(map: ArenaMap, pos: Vector3, yaw: float) -> void:
	var body := map._box(pos + Vector3(0, 0.55, 0), Vector3(3.2, 1.1, 0.7), map._mat("wall_concrete"))
	body.rotation.y = yaw
	var strip := map._neon(pos + Vector3(0, 0.8, 0) + Basis(Vector3.UP, yaw) * Vector3(0, 0, -0.37), Vector3(3.0, 0.1, 0.03), "neon_cyan")
	strip.rotation.y = yaw
