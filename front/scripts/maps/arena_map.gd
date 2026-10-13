@tool
class_name ArenaMap
extends Node3D
## Map "Arena" : zone industrielle et urbaine de 120 x 120 m pour 8 joueurs.
##
## La map est construite par code à partir des listes ci-dessous (positions en mètres),
## ce qui la rend facile à modifier sans outil de modélisation. Grâce à @tool, elle
## s'affiche aussi dans l'éditeur Godot : ouvrir scenes/maps/arena.tscn.
##
## Repère : le centre de la map est (0, 0), le sol est à y = 0.
## x négatif = ouest, x positif = est, z négatif = nord, z positif = sud.
##
## Zones :
##   Centre        tour à 3 m de haut, 4 rampes, auvent
##   Nord-ouest    parc à conteneurs + portique de levage
##   Nord-est      entrepôt (mezzanine, caisses)
##   Sud-ouest     échafaudages : deux tours reliées par une passerelle à 5 m
##   Sud-est       place moderne (pergola, arbres, fontaine, kiosque)
##   Croix         deux avenues qui traversent la map, avec barrières et lampadaires

const HALF := 60.0                 # demi-côté de l'arène (120 m de côté)
const WALL_HEIGHT := 8.0
const ROAD_HALF_WIDTH := 10.0

## Points d'apparition des joueurs (au sol). Ils regardent vers le centre.
const SPAWN_POINTS: Array[Vector3] = [
	Vector3(0, 0, -55), Vector3(0, 0, 55), Vector3(55, 0, 0), Vector3(-55, 0, 0),
	Vector3(-52, 0, -26), Vector3(-20, 0, -46), Vector3(-35, 0, -56),
	Vector3(34, 0, -30), Vector3(55, 0, -30), Vector3(30, 0, -55),
	Vector3(-46, 0, 26), Vector3(-26, 0, 40), Vector3(-52, 0, 52),
	Vector3(18, 0, 48), Vector3(55, 0, 26), Vector3(38, 0, 16),
]

## Emplacements des cibles d'entraînement (y = hauteur de la surface).
const TARGET_POINTS: Array[Vector3] = [
	Vector3(5.5, 3, 0), Vector3(-38, 2.6, -34), Vector3(34, 3.5, -46),
	Vector3(-46, 5, 25), Vector3(37.5, 0.6, 40), Vector3(0, 0, 30),
	Vector3(-30, 0, -30), Vector3(30, 0, -14),
]

# Conteneurs : [x, z, orienté selon x ?, étage (0 = au sol), couleur].
const CONTAINERS := [
	[-44, -50, true, 0, "red"], [-44, -50, true, 1, "blue"], [-36, -50, true, 0, "orange"],
	[-26, -50, true, 0, "teal"], [-26, -50, true, 1, "white"],
	[-50, -42, true, 0, "teal"], [-33, -42, true, 0, "red"], [-33, -42, true, 1, "orange"],
	[-46, -34, true, 0, "white"], [-46, -34, true, 1, "red"], [-38, -34, true, 0, "blue"],
	[-22, -34, true, 0, "green"],
	[-55, -30, false, 0, "orange"], [-28, -26, false, 0, "blue"], [-28, -26, false, 1, "teal"],
	[-16, -46, false, 0, "red"],
	[-48, -20, true, 0, "blue"], [-38, -22, true, 0, "orange"],
]
const CONTAINER_SIZE := Vector3(6.1, 2.6, 2.44)   # longueur, hauteur, largeur

# Barrières en béton : [x, z, angle en degrés].
const BARRIERS := [
	[0, 28, 0], [6, 40, 25], [-5, 50, -15], [28, 0, 90], [40, -5, 65], [50, 5, 100],
	[-28, 0, 90], [-40, 4, 115], [-50, -4, 80], [0, -28, 0], [-6, -40, -25], [5, -50, 15],
	[-52, 40, 30], [-36, 52, 0], [-18, 38, 70], [-40, 16, 0], [14, -18, 45], [-14, 18, 45],
]

# Caisses : [x, z, étage].
const CRATES := [
	[24, -29, 0], [25.6, -29, 0], [24.8, -29, 1], [34, -36, 0], [34, -37.6, 0],
	[26, -47, 0], [27.6, -47, 0], [16, -20, 0], [16, -18.4, 0],
	[-14, -14, 0], [14, 14, 0], [15.6, 14, 0], [-12, 30, 0], [12, -32, 0], [12, -33.6, 0],
	[-20, 52, 0], [-21.6, 52, 0], [-20.8, 52, 1],
]

# Arbres de la place : [x, z].
const TREES := [[22, 40], [46, 48], [52, 34], [26, 52], [40, 56]]

var _root: Node3D
var _materials := {}

## Bouton dans l'inspecteur pour reconstruire la map après une modification du script.
@export_tool_button("Reconstruire la map") var rebuild_action := build


func _ready() -> void:
	build()


## Positions d'apparition sous forme de Transform3D (position + orientation vers le centre).
func get_spawn_transforms() -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for p in SPAWN_POINTS:
		var yaw := atan2(-(0.0 - p.x), -(0.0 - p.z))
		result.append(Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0, 0.1, 0)))
	return result


func build() -> void:
	if _root and is_instance_valid(_root):
		_root.free()
	_root = Node3D.new()
	_root.name = "Generated"
	add_child(_root)

	_build_environment()
	_build_ground()
	_build_perimeter()
	_build_skyline()
	_build_center_tower()
	_build_container_yard()
	_build_warehouse()
	_build_scaffolds()
	_build_plaza()
	_build_roads()


# =========================================================================== ambiance

func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.18, 0.36, 0.68)
	sky_material.sky_horizon_color = Color(0.78, 0.72, 0.66)
	sky_material.sky_curve = 0.12
	sky_material.ground_bottom_color = Color(0.16, 0.16, 0.18)
	sky_material.ground_horizon_color = Color(0.78, 0.72, 0.66)
	sky_material.sun_angle_max = 20.0

	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# Lumière ambiante : moitié ciel, moitié gris neutre (ombres moins bleues).
	env.ambient_light_color = Color(0.62, 0.6, 0.58)
	env.ambient_light_sky_contribution = 0.45
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.tonemap_white = 6.0
	# Halo lumineux autour des néons uniquement (seuil élevé).
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.3
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	# Légère brume : donne de la profondeur et estompe les immeubles lointains.
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.72, 0.74)
	env.fog_density = 0.0025
	env.fog_sky_affect = 0.15
	# Petits réglages de couleur.
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.1

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_root.add_child(world_env)

	# Soleil de fin d'après-midi : lumière chaude, ombres longues.
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.9, 0.78)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.directional_shadow_max_distance = 110.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_root.add_child(sun)
	sun.rotation_degrees = Vector3(-32, -48, 0)


# =========================================================================== sol et murs

func _build_ground() -> void:
	# Une seule collision pour tout le sol (évite les accrocs entre dalles)...
	_collider_box(Vector3(0, -0.5, 0), Vector3(HALF * 2, 1, HALF * 2))
	# ...et des dalles visuelles de 10 m avec un revêtement par zone.
	var tile := 10.0
	for i in 12:
		for j in 12:
			var x0 := -HALF + i * tile
			var z0 := -HALF + j * tile
			var center := Vector3(x0 + tile / 2, -0.5, z0 + tile / 2)
			_mesh_box(center, Vector3(tile, 1, tile), _ground_material(x0, z0), true)
	# Sol au-delà des murs, visible depuis les hauteurs.
	_mesh_box(Vector3(0, -0.55, 0), Vector3(500, 1, 500), _mat("floor_asphalt"), false)


func _ground_material(x0: float, z0: float) -> Material:
	var on_road_x := x0 >= -ROAD_HALF_WIDTH and x0 < ROAD_HALF_WIDTH
	var on_road_z := z0 >= -ROAD_HALF_WIDTH and z0 < ROAD_HALF_WIDTH
	if on_road_x and on_road_z:
		return _mat("floor_concrete")          # dalle sous la tour centrale
	if on_road_x or on_road_z:
		return _mat("floor_asphalt")           # avenues
	if x0 >= ROAD_HALF_WIDTH and z0 >= ROAD_HALF_WIDTH:
		return _mat("floor_plaza")             # place sud-est
	if x0 < -ROAD_HALF_WIDTH and z0 < -ROAD_HALF_WIDTH:
		return _mat("floor_asphalt")           # parc à conteneurs
	return _mat("floor_concrete")


func _build_perimeter() -> void:
	var h := WALL_HEIGHT
	var t := 1.0
	var walls := [
		[Vector3(0, h / 2, -HALF - t / 2), Vector3(HALF * 2 + t * 2, h, t)],
		[Vector3(0, h / 2, HALF + t / 2), Vector3(HALF * 2 + t * 2, h, t)],
		[Vector3(-HALF - t / 2, h / 2, 0), Vector3(t, h, HALF * 2)],
		[Vector3(HALF + t / 2, h / 2, 0), Vector3(t, h, HALF * 2)],
	]
	for w in walls:
		_box(w[0], w[1], _mat("wall_concrete"))
		# Chaperon métallique en haut du mur.
		_mesh_box(w[0] + Vector3(0, h / 2 + 0.15, 0), w[1] * Vector3(1, 0, 1) + Vector3(0.3, 0.3, 0.3), _mat("metal_dark"))

	# Piliers métalliques tous les 10 m + bande néon en haut, côté intérieur.
	var step := 10.0
	var s := -HALF + step
	while s < HALF - 1:
		for side in [-1.0, 1.0]:
			_box(Vector3(s, h / 2, side * (HALF - 0.25)), Vector3(0.8, h + 0.4, 0.5), _mat("metal_dark"))
			_box(Vector3(side * (HALF - 0.25), h / 2, s), Vector3(0.5, h + 0.4, 0.8), _mat("metal_dark"))
		s += step
	for side in [-1.0, 1.0]:
		_neon(Vector3(0, h - 0.6, side * (HALF - 0.04)), Vector3(HALF * 2, 0.12, 0.06), "neon_cyan")
		_neon(Vector3(side * (HALF - 0.04), h - 0.6, 0), Vector3(0.06, 0.12, HALF * 2), "neon_cyan")
		# Bande de danger en bas des murs.
		_mesh_box(Vector3(0, 0.4, side * (HALF - 0.02)), Vector3(HALF * 2, 0.8, 0.04), _mat("hazard"), false)
		_mesh_box(Vector3(side * (HALF - 0.02), 0.4, 0), Vector3(0.04, 0.8, HALF * 2), _mat("hazard"), false)


## Immeubles autour de l'arène (décor sans collision) pour l'ambiance urbaine.
func _build_skyline() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7  # toujours la même ville
	var count := 28
	for i in count:
		var angle := TAU * i / count + rng.randf_range(-0.05, 0.05)
		var distance := rng.randf_range(85, 125)
		var width := rng.randf_range(16, 30)
		var depth := rng.randf_range(16, 30)
		var height := rng.randf_range(22, 70)
		var pos := Vector3(cos(angle) * distance, height / 2 - 0.5, sin(angle) * distance)
		var facade: String = ["facade", "facade_warm", "facade_dark"][i % 3]
		var building := _mesh_box(pos, Vector3(width, height, depth), _mat(facade), true)
		building.rotation.y = -angle
		# Liseré néon autour du toit de certains immeubles.
		if i % 3 == 0:
			var basis := Basis(Vector3.UP, -angle)
			var roof := pos + Vector3(0, height / 2 + 0.15, 0)
			var neon_name := "neon_magenta" if i % 2 == 0 else "neon_cyan"
			for edge in [[Vector3(0, 0, depth / 2), Vector3(width, 0.3, 0.3)], [Vector3(0, 0, -depth / 2), Vector3(width, 0.3, 0.3)],
					[Vector3(width / 2, 0, 0), Vector3(0.3, 0.3, depth)], [Vector3(-width / 2, 0, 0), Vector3(0.3, 0.3, depth)]]:
				var strip := _neon(roof + basis * (edge[0] as Vector3), edge[1], neon_name)
				strip.rotation.y = -angle


# =========================================================================== centre

func _build_center_tower() -> void:
	var top := 3.0
	var half := 8.0
	_box(Vector3(0, top / 2, 0), Vector3(half * 2, top, half * 2), _mat("wall_concrete"))
	# Bandeau métallique et néon sur le pourtour.
	_mesh_box(Vector3(0, top - 0.25, 0), Vector3(half * 2 + 0.1, 0.5, half * 2 + 0.1), _mat("metal_dark"))
	_neon_ring(Vector3(0, top - 0.55, 0), half * 2 + 0.1, half * 2 + 0.1, "neon_cyan")

	# Quatre rampes (une par côté), largeur 4 m, pente d'environ 17°.
	for dir in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		var bottom: Vector3 = dir * (half + 9.5)
		var upper: Vector3 = dir * half + Vector3(0, top, 0)
		_ramp(bottom, upper, 4.0, _mat("grating"))
		# Rayures de danger au pied de la rampe.
		_mesh_box(bottom + dir * 0.6 + Vector3(0, 0.01, 0), _oriented(dir, 4.0, 0.02, 1.2), _mat("hazard"), false)

	# Murets en L dans les coins (couverture), entrées des rampes dégagées.
	var wall_h := 1.1
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var y := top + wall_h / 2
			_box(Vector3(sx * 5.75, y, sz * (half - 0.25)), Vector3(4.5, wall_h, 0.5), _mat("metal_light"))
			_box(Vector3(sx * (half - 0.25), y, sz * 5.75), Vector3(0.5, wall_h, 4.5), _mat("metal_light"))

	# Auvent sur 4 colonnes.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_cylinder(Vector3(sx * 4.0, top + 2.5, sz * 4.0), 0.35, 5.0, _mat("metal_dark"))
	_box(Vector3(0, top + 5.2, 0), Vector3(12, 0.4, 12), _mat("metal_dark"))
	_neon_ring(Vector3(0, top + 4.96, 0), 12.0, 12.0, "neon_magenta")


# =========================================================================== nord-ouest

func _build_container_yard() -> void:
	for c in CONTAINERS:
		_container(c[0], c[1], c[2], c[3], c[4])

	# Rampe en caillebotis pour monter sur un conteneur.
	_ramp(Vector3(-38, 0, -24), Vector3(-38, CONTAINER_SIZE.y, -32.78), 2.4, _mat("grating"))

	# Portique de levage (repère visuel du quartier).
	var legs := [Vector2(-50, -55), Vector2(-20, -55), Vector2(-50, -17), Vector2(-20, -17)]
	for leg in legs:
		_box(Vector3(leg.x, 7, leg.y), Vector3(1.2, 14, 1.2), _mat("metal_accent"))
		_mesh_box(Vector3(leg.x, 1, leg.y), Vector3(1.3, 2, 1.3), _mat("hazard"), false)
	for z in [-55.0, -17.0]:
		_box(Vector3(-35, 14.5, z), Vector3(32, 1.2, 1.4), _mat("metal_accent"))
	_mesh_box(Vector3(-35, 14.0, -36), Vector3(1.6, 1.0, 39.4), _mat("metal_dark"))
	_mesh_box(Vector3(-35, 13.0, -36), Vector3(3.0, 1.4, 2.4), _mat("metal_accent"))
	_neon(Vector3(-35, 12.25, -36), Vector3(2.0, 0.08, 1.2), "neon_orange")


func _container(x: float, z: float, along_x: bool, level: int, color: String) -> void:
	var s := CONTAINER_SIZE
	var size := Vector3(s.x, s.y, s.z) if along_x else Vector3(s.z, s.y, s.x)
	var center := Vector3(x, s.y / 2 + level * s.y, z)
	_box(center, size, _mat("container_" + color))
	# Cadre sombre aux deux extrémités (portes) pour le détail.
	var axis := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
	for side in [-1.0, 1.0]:
		var end: Vector3 = center + axis * side * (s.x / 2 + 0.02)
		var frame := Vector3(0.06, s.y, s.z) if along_x else Vector3(s.z, s.y, 0.06)
		_mesh_box(end, frame, _mat("metal_dark"), false)


# =========================================================================== nord-est

func _build_warehouse() -> void:
	var x0 := 18.0
	var x1 := 50.0
	var z0 := -50.0
	var z1 := -24.0
	var h := 7.0
	var t := 0.6
	var wall := _mat("metal_light")

	# Mur sud (face au centre) : deux grandes portes.
	_wall_with_openings(Vector3(x0, 0, z1), Vector3(x1, 0, z1), h, t, [[23.0, 29.0], [39.0, 45.0]], 5.0, wall)
	# Mur nord : plein.
	_wall_with_openings(Vector3(x0, 0, z0), Vector3(x1, 0, z0), h, t, [], 5.0, wall)
	# Mur ouest : une porte.
	_wall_with_openings(Vector3(x0, 0, z0), Vector3(x0, 0, z1), h, t, [[-40.0, -34.0]], 5.0, wall)
	# Mur est : une porte.
	_wall_with_openings(Vector3(x1, 0, z0), Vector3(x1, 0, z1), h, t, [[-42.0, -36.0]], 5.0, wall)

	# Soubassement en béton et bandeau orange (style industriel moderne).
	_mesh_box(Vector3((x0 + x1) / 2, h + 0.2, z1), Vector3(x1 - x0 + 0.8, 0.4, t + 0.2), _mat("metal_accent"))
	_mesh_box(Vector3((x0 + x1) / 2, h + 0.2, z0), Vector3(x1 - x0 + 0.8, 0.4, t + 0.2), _mat("metal_accent"))
	_mesh_box(Vector3(x0, h + 0.2, (z0 + z1) / 2), Vector3(t + 0.2, 0.4, z1 - z0), _mat("metal_accent"))
	_mesh_box(Vector3(x1, h + 0.2, (z0 + z1) / 2), Vector3(t + 0.2, 0.4, z1 - z0), _mat("metal_accent"))

	# Toit partiel au nord (ombre sous la mezzanine) + poutres apparentes.
	_box(Vector3((x0 + x1) / 2, h + 0.15, -44), Vector3(x1 - x0, 0.3, 12), _mat("metal_dark"))
	for z in [-36.0, -30.0]:
		_mesh_box(Vector3((x0 + x1) / 2, h - 0.25, z), Vector3(x1 - x0, 0.5, 0.3), _mat("metal_dark"))
	for x in [26.0, 34.0, 42.0]:
		_mesh_box(Vector3(x, h - 0.25, (z0 + z1) / 2), Vector3(0.3, 0.5, z1 - z0), _mat("metal_dark"))

	# Mezzanine à 3,5 m, en caillebotis, sur piliers.
	var deck_top := 3.5
	_box(Vector3(34, deck_top - 0.2, -46.2), Vector3(24, 0.4, 6.4), _mat("grating"))
	for x in [22.5, 30.0, 38.0, 45.8]:
		_box(Vector3(x, (deck_top - 0.4) / 2, -43.3), Vector3(0.4, deck_top - 0.4, 0.4), _mat("metal_dark"))
	# Garde-corps (avec une ouverture pour la rampe).
	_box(Vector3(32, deck_top + 0.5, -43.1), Vector3(20, 1.0, 0.15), _mat("metal_dark"))
	_neon(Vector3(32, deck_top + 1.02, -43.1), Vector3(20, 0.05, 0.17), "neon_orange")
	_ramp(Vector3(44, 0, -33), Vector3(44, deck_top, -43), 3.0, _mat("grating"))

	# Lampes suspendues sous le toit.
	for x in [26.0, 34.0, 42.0]:
		_mesh_box(Vector3(x, h - 1.0, -40), Vector3(1.6, 0.12, 0.5), _mat("lamp_warm"), false)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.85, 0.65)
		light.light_energy = 1.4
		light.omni_range = 11.0
		_root.add_child(light)
		light.position = Vector3(x, h - 1.4, -40)

	# Marquage au sol à l'intérieur.
	_mesh_box(Vector3(34, 0.012, -38.5), Vector3(28, 0.02, 0.2), _mat("paint_yellow"), false)

	for c in CRATES:
		_crate(c[0], c[1], c[2])


# =========================================================================== sud-ouest

func _build_scaffolds() -> void:
	var deck_top := 5.0
	# Deux tours : plateforme de 8 x 8 m sur 4 piliers.
	for tower in [Vector2(-46, 26), Vector2(-26, 26)]:
		_box(Vector3(tower.x, deck_top - 0.25, tower.y), Vector3(8, 0.5, 8), _mat("metal_dark"))
		_neon_ring(Vector3(tower.x, deck_top - 0.25, tower.y), 8.0, 8.0, "neon_cyan")
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				_box(Vector3(tower.x + sx * 3.7, (deck_top - 0.5) / 2, tower.y + sz * 3.7),
					Vector3(0.5, deck_top - 0.5, 0.5), _mat("hazard"))
	# Couverture sur les tours.
	var y := deck_top + 0.55
	_box(Vector3(-49.8, y, 26), Vector3(0.4, 1.1, 8), _mat("metal_light"))
	_box(Vector3(-46, y, 22.2), Vector3(8, 1.1, 0.4), _mat("metal_light"))
	_box(Vector3(-26, y, 22.2), Vector3(8, 1.1, 0.4), _mat("metal_light"))
	_box(Vector3(-26, y, 29.8), Vector3(4, 1.1, 0.4), _mat("metal_light"))

	# Passerelle entre les tours, avec garde-corps.
	_box(Vector3(-36, deck_top - 0.15, 26), Vector3(12, 0.3, 2.4), _mat("grating"))
	for side in [-1.0, 1.0]:
		_box(Vector3(-36, deck_top + 0.5, 26 + side * 1.15), Vector3(12, 1.0, 0.1), _mat("metal_dark"))

	# Rampes d'accès.
	_ramp(Vector3(-46, 0, 44), Vector3(-46, deck_top, 30), 3.0, _mat("grating"))
	_ramp(Vector3(-8, 0, 26), Vector3(-22, deck_top, 26), 3.0, _mat("grating"))

	# Panneau publicitaire lumineux.
	for x in [-40.0, -30.0]:
		_box(Vector3(x, 2.5, 46), Vector3(0.6, 5, 0.6), _mat("metal_dark"))
	_box(Vector3(-35, 6.5, 46), Vector3(12, 5, 0.4), _mat("metal_dark"))
	for side in [-1.0, 1.0]:
		_mesh_box(Vector3(-35, 6.5, 46 + side * 0.22), Vector3(11.4, 4.4, 0.02), _mat("screen"), false)

	# Groupe électrogène.
	_box(Vector3(-24, 1, 50), Vector3(4, 2, 2.2), _mat("metal_dark"))
	_neon(Vector3(-24, 1.4, 48.88), Vector3(2.8, 0.1, 0.04), "neon_orange")


# =========================================================================== sud-est

func _build_plaza() -> void:
	# Pergola : deux rangées de colonnes et des lames au-dessus.
	for z in [24.0, 30.0]:
		for x in [20.0, 26.0, 32.0, 38.0, 44.0, 50.0]:
			_cylinder(Vector3(x, 2.75, z), 0.4, 5.5, _mat("paint_white"))
		_box(Vector3(35, 5.8, z), Vector3(34, 0.6, 0.6), _mat("paint_white"))
	var slat := 18.5
	while slat < 52:
		_mesh_box(Vector3(slat, 6.2, 27), Vector3(0.25, 0.2, 7.2), _mat("metal_dark"))
		slat += 1.5

	# Fontaine ronde surélevée avec une sculpture au centre.
	_cylinder(Vector3(34, 0.3, 40), 4.0, 0.6, _mat("wall_concrete"))
	_mesh_cylinder(Vector3(34, 0.61, 40), 3.6, 0.02, _mat("glass"))
	_box(Vector3(34, 1.6, 40), Vector3(1.4, 2.0, 1.4), _mat("metal_light"))
	var cube := _box(Vector3(34, 3.3, 40), Vector3(1.4, 1.4, 1.4), _mat("metal_accent"))
	cube.rotation_degrees = Vector3(35, 45, 0)
	_neon(Vector3(34, 0.65, 40), Vector3(1.6, 0.05, 1.6), "neon_cyan")

	# Arbres dans des jardinières.
	for t in TREES:
		_tree(t[0], t[1])

	# Bancs.
	for b in [[30, 46], [38, 46], [44, 40], [20, 34]]:
		_box(Vector3(b[0], 0.22, b[1]), Vector3(2.2, 0.45, 0.6), _mat("metal_dark"))

	# Kiosque moderne.
	_box(Vector3(46, 1.75, 16.5), Vector3(8, 3.5, 5), _mat("metal_light"))
	_mesh_box(Vector3(46, 1.9, 13.98), Vector3(7.2, 1.4, 0.04), _mat("glass"), false)
	_box(Vector3(46, 3.65, 16.0), Vector3(9.5, 0.3, 7), _mat("metal_dark"))
	_neon(Vector3(46, 3.3, 13.96), Vector3(6, 0.25, 0.05), "neon_magenta")


func _tree(x: float, z: float) -> void:
	_box(Vector3(x, 0.4, z), Vector3(3.2, 0.8, 3.2), _mat("wall_concrete"))
	_mesh_box(Vector3(x, 0.81, z), Vector3(2.8, 0.02, 2.8), _mat("grass"), false)
	_cylinder(Vector3(x, 0.8 + 1.8, z), 0.22, 3.6, _mat("bark"))
	# Feuillage : plusieurs sphères pour une silhouette naturelle (sans collision).
	var rng := RandomNumberGenerator.new()
	rng.seed = int(x * 31 + z * 17)
	for i in 4:
		var offset := Vector3(rng.randf_range(-0.9, 0.9), rng.randf_range(0, 1.2), rng.randf_range(-0.9, 0.9))
		_mesh_sphere(Vector3(x, 5.0, z) + offset, rng.randf_range(1.3, 1.9), _mat("foliage"))


# =========================================================================== avenues

func _build_roads() -> void:
	# Lignes blanches discontinues au milieu des avenues.
	var d := 12.0
	while d < HALF - 2:
		for side in [-1.0, 1.0]:
			_mesh_box(Vector3(0, 0.012, side * d), Vector3(0.25, 0.02, 3), _mat("paint_white"), false)
			_mesh_box(Vector3(side * d, 0.012, 0), Vector3(3, 0.02, 0.25), _mat("paint_white"), false)
		d += 6.0
	# Bordures jaunes le long des avenues.
	for side in [-1.0, 1.0]:
		for half_side in [-1.0, 1.0]:
			var mid: float = half_side * (HALF + ROAD_HALF_WIDTH) / 2
			var length := HALF - ROAD_HALF_WIDTH
			_mesh_box(Vector3(side * ROAD_HALF_WIDTH, 0.012, mid), Vector3(0.2, 0.02, length), _mat("paint_yellow"), false)
			_mesh_box(Vector3(mid, 0.012, side * ROAD_HALF_WIDTH), Vector3(length, 0.02, 0.2), _mat("paint_yellow"), false)

	for b in BARRIERS:
		_barrier(b[0], b[1], b[2])

	# Lampadaires le long des avenues.
	for d2 in [20.0, 40.0]:
		for s1 in [-1.0, 1.0]:
			for s2 in [-1.0, 1.0]:
				_street_light(Vector3(s1 * 11, 0, s2 * d2), Vector3(-s1, 0, 0))
				_street_light(Vector3(s2 * d2, 0, s1 * 11), Vector3(0, 0, -s1))


func _barrier(x: float, z: float, angle_deg: float) -> void:
	var base := _box(Vector3(x, 0.55, z), Vector3(3.2, 1.1, 0.7), _mat("wall_concrete"))
	base.rotation_degrees.y = angle_deg
	var band := _mesh_box(Vector3(x, 0.85, z), Vector3(3.22, 0.25, 0.72), _mat("hazard"), false)
	band.rotation_degrees.y = angle_deg


func _crate(x: float, z: float, level: int) -> void:
	var size := 1.5
	_box(Vector3(x, size / 2 + level * size, z), Vector3(size, size, size) * 0.98, _mat("metal_accent" if int(x + z) % 2 == 0 else "metal_dark"))


func _street_light(base: Vector3, facing: Vector3) -> void:
	_cylinder(base + Vector3(0, 3, 0), 0.12, 6, _mat("metal_dark"))
	_mesh_box(base + Vector3(0, 6, 0) + facing * 0.8, Vector3(0.2, 0.15, 0.2) + facing.abs() * 1.4, _mat("metal_dark"))
	_mesh_box(base + Vector3(0, 5.88, 0) + facing * 1.3, Vector3(0.35, 0.06, 0.35) + facing.abs() * 0.3, _mat("lamp_warm"))


# =========================================================================== briques de base

func _mat(name: String) -> Material:
	if not _materials.has(name):
		_materials[name] = load("res://data/materials/%s.tres" % name)
	return _materials[name]


## Bloc solide (visuel + collision).
func _box(center: Vector3, size: Vector3, material: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	_root.add_child(body)
	body.position = center
	var mesh := BoxMesh.new()
	mesh.size = size
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	body.add_child(visual)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	return body


## Bloc décoratif (sans collision).
func _mesh_box(center: Vector3, size: Vector3, material: Material, cast_shadow := true) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	if not cast_shadow:
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(visual)
	visual.position = center
	return visual


## Collision seule (invisible).
func _collider_box(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	_root.add_child(body)
	body.position = center
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)


func _cylinder(center: Vector3, radius: float, height: float, material: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	_root.add_child(body)
	body.position = center
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 24
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	body.add_child(visual)
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	return body


func _mesh_cylinder(center: Vector3, radius: float, height: float, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 32
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(visual)
	visual.position = center


func _mesh_sphere(center: Vector3, radius: float, material: Material) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2
	mesh.radial_segments = 16
	mesh.rings = 8
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	_root.add_child(visual)
	visual.position = center


## Bande lumineuse (néon) : émissive, sans ombre ni collision.
func _neon(center: Vector3, size: Vector3, material_name: String) -> MeshInstance3D:
	return _mesh_box(center, size, _mat(material_name), false)


## Liseré néon autour d'un rectangle horizontal (4 bandes fines sur les bords).
func _neon_ring(center: Vector3, size_x: float, size_z: float, material_name: String) -> void:
	var t := 0.08
	_neon(center + Vector3(0, 0, size_z / 2), Vector3(size_x + t, t, t), material_name)
	_neon(center + Vector3(0, 0, -size_z / 2), Vector3(size_x + t, t, t), material_name)
	_neon(center + Vector3(size_x / 2, 0, 0), Vector3(t, t, size_z), material_name)
	_neon(center + Vector3(-size_x / 2, 0, 0), Vector3(t, t, size_z), material_name)


## Rampe dont la surface va de `bottom` à `top` (deux points au milieu de la rampe).
func _ramp(bottom: Vector3, top: Vector3, width: float, material: Material) -> void:
	var thickness := 0.4
	var forward := (top - bottom).normalized()
	var right := Vector3.UP.cross(forward).normalized()
	var up := forward.cross(right).normalized()
	var length := bottom.distance_to(top)
	var body := _box(Vector3.ZERO, Vector3(width, thickness, length), material)
	body.transform = Transform3D(Basis(right, up, forward), (bottom + top) / 2 - up * thickness / 2)


## Mur droit de `from` à `to` (au sol) avec des ouvertures [début, fin] le long du mur.
## Les ouvertures font `door_height` de haut, avec un linteau au-dessus.
func _wall_with_openings(from: Vector3, to: Vector3, height: float, thickness: float,
		openings: Array, door_height: float, material: Material) -> void:
	var along_x := absf(to.x - from.x) > absf(to.z - from.z)
	var a := from.x if along_x else from.z
	var b := to.x if along_x else to.z
	var fixed := from.z if along_x else from.x
	var cursor := a
	var segments := []
	for o in openings:
		segments.append([cursor, o[0], 0.0, height])          # mur plein avant la porte
		segments.append([o[0], o[1], door_height, height])    # linteau au-dessus
		_door_frame(along_x, fixed, o[0], o[1], door_height)
		cursor = o[1]
	segments.append([cursor, b, 0.0, height])
	for s in segments:
		var length: float = s[1] - s[0]
		if length <= 0.01:
			continue
		var mid: float = (s[0] + s[1]) / 2
		var y0: float = s[2]
		var y1: float = s[3]
		var center := Vector3(mid, (y0 + y1) / 2, fixed) if along_x else Vector3(fixed, (y0 + y1) / 2, mid)
		var size := Vector3(length, y1 - y0, thickness) if along_x else Vector3(thickness, y1 - y0, length)
		_box(center, size, material)


func _door_frame(along_x: bool, fixed: float, start: float, end: float, height: float) -> void:
	var neon_size := Vector3(end - start, 0.1, 0.7) if along_x else Vector3(0.7, 0.1, end - start)
	var mid := (start + end) / 2
	var top := Vector3(mid, height - 0.05, fixed) if along_x else Vector3(fixed, height - 0.05, mid)
	_neon(top, neon_size, "neon_orange")
	for p in [start, end]:
		var pos := Vector3(p, height / 2, fixed) if along_x else Vector3(fixed, height / 2, p)
		_mesh_box(pos, Vector3(0.12, height, 0.72) if along_x else Vector3(0.72, height, 0.12), _mat("hazard"), false)


## Taille d'un bloc plat orienté selon une direction horizontale (largeur en travers, profondeur le long).
func _oriented(dir: Vector3, across: float, height: float, along: float) -> Vector3:
	return Vector3(along, height, across) if absf(dir.x) > 0.5 else Vector3(across, height, along)
