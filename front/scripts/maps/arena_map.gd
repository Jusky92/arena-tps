@tool
class_name ArenaMap
extends Node3D
## Map « NEO-EDO » : quartier japonais de 120 x 120 m pour 16 joueurs.
##
## Deux ambiances se répondent dans la même arène :
##   - un quartier TRADITIONNEL (sanctuaire, pagode, marché de bois, jardin sec) ;
##   - un quartier NÉO-TOKYO (laboratoire IoT, enseignes néon verticales,
##     distributeurs, rideaux métalliques).
##
## La map est construite par code à partir des listes ci-dessous (positions en mètres),
## ce qui la rend facile à modifier sans outil de modélisation. Grâce à @tool, elle
## s'affiche aussi dans l'éditeur Godot : ouvrir scenes/maps/arena.tscn, puis cliquer
## sur « Reconstruire la map » dans l'inspecteur après une modification.
##
## Repère : le centre de la map est (0, 0), le sol est à y = 0.
## x négatif = ouest, x positif = est, z négatif = nord, z positif = sud.
##
## Zones :
##   Centre        sanctuaire sur une estrade de 3 m, grand torii, 4 rampes
##   Nord-ouest    marché couvert : échoppes de bois, caisses et tonneaux de saké
##   Nord-est      IoT研究所 : laboratoire néon (bras robotiques, tapis, mezzanine)
##   Sud-ouest     pagode à cinq toits et tour de guet reliées par une passerelle à 5 m
##   Sud-est       jardin sec : gravier ratissé, bassin à carpes, pont rouge, cerisiers
##   Croix         deux ruelles commerçantes qui traversent la map
##
## Décor « CFA INSTA » et IoT : enseignes néon en kanji, bannières, caméras de
## surveillance fixées sur les lampadaires.

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

## Bonus (phase 4) : [Pickups.Kind, Vector3(x, hauteur de départ du rayon, z)].
## Le socle se pose sur la première surface sous ce point (voir PickupDirector).
const PICKUP_POINTS := [
	# Soins.
	[Pickups.Kind.HEAL, Vector3(-38, 2, -14)], [Pickups.Kind.HEAL, Vector3(32, 2, -13)],
	[Pickups.Kind.HEAL, Vector3(-36, 2, 16)], [Pickups.Kind.HEAL, Vector3(28, 2, 25)],
	[Pickups.Kind.HEAL, Vector3(0, 2, -30)], [Pickups.Kind.HEAL, Vector3(0, 2, 36)],
	# Armures.
	[Pickups.Kind.ARMOR, Vector3(-26, 2, -43)], [Pickups.Kind.ARMOR, Vector3(52, 2, -6)],
	[Pickups.Kind.ARMOR, Vector3(-52, 2, 34)],
	# Double saut et vitesse.
	[Pickups.Kind.DOUBLE_JUMP, Vector3(-14, 2, 22)], [Pickups.Kind.DOUBLE_JUMP, Vector3(16, 2, -44)],
	[Pickups.Kind.SPEED, Vector3(-20, 2, -4)], [Pickups.Kind.SPEED, Vector3(18, 2, -4)],
	# Armes spéciales.
	[Pickups.Kind.MINIGUN, Vector3(-40, 2, 50)], [Pickups.Kind.LASER_RIFLE, Vector3(40, 2, -50)],
	[Pickups.Kind.POWER_FIST, Vector3(-24, 2, -19)],
	# Super-pouvoirs : sur l'estrade du sanctuaire et la mezzanine du laboratoire.
	[Pickups.Kind.SUPER, Vector3(0, 4.5, -6)], [Pickups.Kind.SUPER, Vector3(49, 5.0, -39)],
]

## Emplacements des cibles d'entraînement (y = hauteur de la surface).
const TARGET_POINTS: Array[Vector3] = [
	Vector3(5.5, 3, 0), Vector3(-38, 2.6, -34), Vector3(34, 3.5, -46),
	Vector3(-46, 5, 25), Vector3(37.5, 0.6, 40), Vector3(0, 0, 30),
	Vector3(-30, 0, -30), Vector3(30, 0, -14),
]

# Étals du marché : [x, z, orienté selon x ?, étage (0 = au sol), style].
# Les étals du bas sont des échoppes couvertes, ceux du dessus des piles de
# caisses et de tonneaux : on peut grimper dessus, comme sur les anciens conteneurs.
const STALLS := [
	[-44, -50, true, 0, "indigo"], [-44, -50, true, 1, "barrels"], [-36, -50, true, 0, "red"],
	[-26, -50, true, 0, "green"], [-26, -50, true, 1, "crates"],
	[-50, -42, true, 0, "green"], [-33, -42, true, 0, "red"], [-33, -42, true, 1, "barrels"],
	[-46, -34, true, 0, "cream"], [-46, -34, true, 1, "crates"], [-38, -34, true, 0, "indigo"],
	[-22, -34, true, 0, "green"],
	[-55, -30, false, 0, "red"], [-28, -26, false, 0, "indigo"], [-28, -26, false, 1, "barrels"],
	[-16, -46, false, 0, "red"],
	[-48, -20, true, 0, "indigo"], [-38, -22, true, 0, "cream"],
]
const STALL_SIZE := Vector3(6.1, 2.6, 2.44)   # longueur, hauteur, largeur

# Bornes et bancs de pierre (couverture basse) : [x, z, angle en degrés].
const STONE_BLOCKS := [
	[0, 28, 0], [6, 40, 25], [-5, 50, -15], [28, 0, 90], [40, -5, 65], [50, 5, 100],
	[-28, 0, 90], [-40, 4, 115], [-50, -4, 80], [0, -28, 0], [-6, -40, -25], [5, -50, 15],
	[-52, 40, 30], [-36, 52, 0], [-18, 38, 70], [-40, 16, 0], [14, -18, 45], [-14, 18, 45],
]

# Caisses de bois : [x, z, étage].
const CRATES := [
	[24, -29, 0], [25.6, -29, 0], [24.8, -29, 1],
	[26, -47, 0], [27.6, -47, 0], [16, -20, 0], [16, -18.4, 0],
	[-14, -14, 0], [14, 14, 0], [15.6, 14, 0], [-12, 30, 0], [12, -32, 0], [12, -33.6, 0],
	[-20, 52, 0], [-21.6, 52, 0], [-20.8, 52, 1],
]

# Cerisiers du jardin : [x, z, hauteur].
const CHERRY_TREES := [[22, 40, 6.5], [46, 48, 7.5], [52, 34, 6.0], [26, 52, 7.0], [40, 56, 6.2]]

const TITLE_FONT := preload("res://assets/fonts/Orbitron.ttf")

var _root: Node3D
var _materials := {}

## Bouton dans l'inspecteur pour reconstruire la map après une modification du script.
@export_tool_button("Reconstruire la map") var rebuild_action := build


func _ready() -> void:
	build()


# =========================================================================== description de la map
# Questions posées par la partie (game.gd, server_game.gd, MatchRules). Une autre map
# (Hikari Mall) hérite de ce script et redéfinit ces fonctions et build().

## Identifiant (réseau, back) : voir MapCatalog.
func map_id() -> String:
	return "neo-edo"


func spawn_points() -> Array:
	return SPAWN_POINTS


## Bonus : [Pickups.Kind, Vector3(x, hauteur de départ du rayon, z)].
func pickup_points() -> Array:
	return PICKUP_POINTS


func target_points() -> Array:
	return TARGET_POINTS


## Zone où les bots peuvent circuler (calcul de la navigation).
func nav_aabb() -> AABB:
	return AABB(Vector3(-HALF - 1, -1, -HALF - 1), Vector3(HALF * 2 + 2, 16, HALF * 2 + 2))


## Positions d'apparition sous forme de Transform3D (position + orientation vers le centre).
func get_spawn_transforms() -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for p in spawn_points():
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
	_build_shrine()
	_build_market()
	_build_lab()
	_build_pagoda()
	_build_garden()
	_build_streets()
	_build_cfa_insta()
	_build_connected_decor()
	ArenaDressing.build_greenery(self, _root)
	ArenaDressing.build_cover(self, _root)


# =========================================================================== ambiance

func _build_environment() -> void:
	# Ciel de fin de journée : bleu profond en haut, horizon rose-orangé.
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.22, 0.34, 0.66)
	sky_material.sky_horizon_color = Color(0.92, 0.72, 0.68)
	sky_material.sky_curve = 0.14
	sky_material.ground_bottom_color = Color(0.17, 0.15, 0.18)
	sky_material.ground_horizon_color = Color(0.9, 0.72, 0.66)
	sky_material.sun_angle_max = 22.0

	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.64, 0.6, 0.6)
	env.ambient_light_sky_contribution = 0.5
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.tonemap_white = 6.0
	# Halo lumineux autour des néons et des lanternes uniquement (seuil élevé).
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.2
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	# Brume légère : profondeur, et les toits lointains se détachent moins.
	env.fog_enabled = true
	env.fog_light_color = Color(0.78, 0.72, 0.74)
	env.fog_density = 0.0014
	env.fog_sky_affect = 0.1
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.12

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_root.add_child(world_env)

	# Soleil bas de fin d'après-midi : lumière dorée, ombres longues.
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.86, 0.7)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.directional_shadow_max_distance = 110.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_root.add_child(sun)
	sun.rotation_degrees = Vector3(-26, -54, 0)


# =========================================================================== sol et murs

func _build_ground() -> void:
	# Une seule collision pour tout le sol (évite les accrocs entre dalles)...
	_collider_box(Vector3(0, -0.5, 0), Vector3(HALF * 2, 1, HALF * 2))
	# ...et des dalles visuelles de 10 m avec un revêtement par quartier.
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
		return _mat("floor_stone")             # parvis du sanctuaire
	if on_road_x or on_road_z:
		return _mat("floor_asphalt")           # ruelles commerçantes
	if x0 >= ROAD_HALF_WIDTH and z0 >= ROAD_HALF_WIDTH:
		return _mat("floor_gravel")            # jardin sec au sud-est
	if x0 < -ROAD_HALF_WIDTH and z0 < -ROAD_HALF_WIDTH:
		return _mat("floor_stone")             # marché au nord-ouest
	if x0 >= ROAD_HALF_WIDTH and z0 < -ROAD_HALF_WIDTH:
		return _mat("floor_concrete")          # quartier du laboratoire
	return _mat("floor_stone")


## Mur d'enceinte de temple : soubassement de pierre, enduit blanc, chapeau de tuiles.
## Une porte couverte au milieu de chaque côté marque les grandes entrées.
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
		var center: Vector3 = w[0]
		var size: Vector3 = w[1]
		_box(center, size, _mat("plaster_white"))
		# Soubassement de pierre sombre.
		_mesh_box(center + Vector3(0, -h / 2 + 0.6, 0), size * Vector3(1, 0, 1) + Vector3(0.2, 1.2, 0.2), _mat("stone_grey"))
		# Chapeau de tuiles débordant.
		_mesh_box(center + Vector3(0, h / 2 + 0.2, 0), size * Vector3(1, 0, 1) + Vector3(1.0, 0.45, 1.0), _mat("roof_tile_dark"))
		# Lisse de bois à mi-hauteur.
		_mesh_box(center + Vector3(0, 0.6, 0), size * Vector3(1, 0, 1) + Vector3(0.1, 0.22, 0.1), _mat("wood_dark"))

	# Poteaux de bois tous les 10 m, côté intérieur.
	var step := 10.0
	var s := -HALF + step
	while s < HALF - 1:
		for side in [-1.0, 1.0]:
			_mesh_box(Vector3(s, h / 2, side * (HALF - 0.35)), Vector3(0.5, h, 0.4), _mat("wood_dark"))
			_mesh_box(Vector3(side * (HALF - 0.35), h / 2, s), Vector3(0.4, h, 0.5), _mat("wood_dark"))
		s += step

	# Lanternes accrochées au mur, tous les 20 m : la nuit tombe, l'enceinte s'allume.
	var p := -HALF + 10.0
	while p < HALF:
		for side in [-1.0, 1.0]:
			_lantern(Vector3(p, 5.6, side * (HALF - 0.9)), 0.9, "祭", Color(1.0, 0.5, 0.25))
			_lantern(Vector3(side * (HALF - 0.9), 5.6, p), 0.9, "祭", Color(1.0, 0.5, 0.25))
		p += 20.0

	# Porte couverte au milieu de chaque côté (repère visuel pour les apparitions).
	for dir in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		var gate: Vector3 = dir * (HALF - 1.2)
		var yaw := atan2(dir.x, dir.z)
		_gate(gate, yaw)


## Petite porte de bois (mon) adossée au mur d'enceinte.
func _gate(pos: Vector3, yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	for side in [-2.2, 2.2]:
		_mesh_cylinder_at(pos + basis * Vector3(side, 2.2, 0), 0.26, 4.4, _mat("lacquer_red"))
	_mesh_box_rot(pos + Vector3(0, 4.5, 0), Vector3(6.4, 0.5, 1.6), _mat("wood_dark"), yaw)
	_roof(pos + Vector3(0, 5.2, 0), 7.6, 3.0, 1.4, yaw, "roof_tile_dark")
	_lantern(pos + basis * Vector3(0, 4.0, -0.9), 0.8, "門", Color(1.0, 0.55, 0.3))


## Toits de la ville autour de l'arène (décor sans collision) : tours néon au nord-est,
## toits traditionnels et pagodes au sud-ouest.
func _build_skyline() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7  # toujours la même ville
	var count := 28
	for i in count:
		var angle := TAU * i / count + rng.randf_range(-0.05, 0.05)
		var distance := rng.randf_range(85, 125)
		var pos_flat := Vector3(cos(angle) * distance, 0, sin(angle) * distance)
		# Côté nord-est : tours modernes. Ailleurs : maisons basses à toits de tuiles.
		var modern := pos_flat.x > -10.0 and pos_flat.z < 20.0
		if modern:
			var width := rng.randf_range(16, 30)
			var depth := rng.randf_range(16, 30)
			var height := rng.randf_range(26, 72)
			var pos := pos_flat + Vector3(0, height / 2 - 0.5, 0)
			var facade: String = ["facade", "facade_warm", "facade_dark"][i % 3]
			var building := _mesh_box(pos, Vector3(width, height, depth), _mat(facade), true)
			building.rotation.y = -angle
			if i % 3 == 0:
				var roof := pos + Vector3(0, height / 2 + 0.15, 0)
				var neon_name := "neon_pink" if i % 2 == 0 else "neon_cyan"
				_neon_ring(roof, width, depth, neon_name, -angle)
			# Enseigne verticale géante sur certaines tours.
			if i % 4 == 1:
				var sign_text: String = ["電気", "未来", "夜", "東京"][i % 4]
				var sign_pos := pos_flat + Vector3(0, height * 0.6, 0) - pos_flat.normalized() * (depth * 0.52)
				_vertical_sign(sign_text, sign_pos, -angle + PI, 3.0, height * 0.3,
					["neon_pink", "neon_cyan", "neon_gold"][i % 3])
		else:
			var width := rng.randf_range(14, 24)
			var depth := rng.randf_range(12, 20)
			var height := rng.randf_range(6, 14)
			var pos := pos_flat + Vector3(0, height / 2 - 0.5, 0)
			var house := _mesh_box(pos, Vector3(width, height, depth), _mat("plaster_white"), true)
			house.rotation.y = -angle
			_roof(pos + Vector3(0, height / 2 + 1.2, 0), width + 3.0, depth + 3.0, 2.6, -angle, "roof_tile_blue")
		# Quelques pagodes lointaines, pour la silhouette.
		if i % 9 == 4:
			_pagoda(pos_flat + Vector3(0, 0, 0), 5, 7.0, rng.randf_range(0, TAU), false)


# =========================================================================== centre : le sanctuaire

## Estrade de 3 m avec 4 rampes, surmontée d'un pavillon et d'un grand torii.
## Même géométrie que l'ancienne tour centrale : le jeu n'y perd rien.
func _build_shrine() -> void:
	var top := 3.0
	var half := 8.0
	_box(Vector3(0, top / 2, 0), Vector3(half * 2, top, half * 2), _mat("stone_grey"))
	# Plancher de bois sur l'estrade + bandeau de pierre.
	_mesh_box(Vector3(0, top - 0.02, 0), Vector3(half * 2 - 0.6, 0.06, half * 2 - 0.6), _mat("wood_warm"))
	_mesh_box(Vector3(0, top - 0.25, 0), Vector3(half * 2 + 0.2, 0.5, half * 2 + 0.2), _mat("stone_grey"))

	# Quatre escaliers de pierre (une par côté), largeur 4 m.
	for dir in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		var bottom: Vector3 = dir * (half + 9.5)
		var upper: Vector3 = dir * half + Vector3(0, top, 0)
		_ramp(bottom, upper, 4.0, _mat("floor_stone"))
		# Deux bornes de pierre au pied de l'escalier.
		var across := Vector3(dir.z, 0, dir.x)
		for side in [-1.0, 1.0]:
			_mesh_box(bottom + across * side * 2.6 + Vector3(0, 0.45, 0), Vector3(0.6, 0.9, 0.6), _mat("stone_grey"))

	# Balustrade de bois dans les coins (couverture), entrées des escaliers dégagées.
	var rail_h := 1.1
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var y := top + rail_h / 2
			_box(Vector3(sx * 5.75, y, sz * (half - 0.25)), Vector3(4.5, rail_h, 0.4), _mat("lacquer_red"))
			_box(Vector3(sx * (half - 0.25), y, sz * 5.75), Vector3(0.4, rail_h, 4.5), _mat("lacquer_red"))

	# Pavillon : 4 piliers vermillon et un toit de tuiles à deux niveaux.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_cylinder(Vector3(sx * 4.0, top + 2.5, sz * 4.0), 0.35, 5.0, _mat("lacquer_red"))
	_mesh_box(Vector3(0, top + 5.1, 0), Vector3(10.4, 0.35, 10.4), _mat("wood_dark"))
	_roof(Vector3(0, top + 5.5, 0), 13.0, 13.0, 1.8, 0.0, "roof_tile_blue")
	_roof(Vector3(0, top + 7.0, 0), 8.0, 8.0, 1.6, 0.0, "roof_tile_blue")
	# Faîtage doré et lanternes aux quatre coins du pavillon.
	_mesh_box(Vector3(0, top + 8.1, 0), Vector3(8.4, 0.25, 0.4), _mat("gold_trim"))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_lantern(Vector3(sx * 4.0, top + 4.6, sz * 4.0), 0.55, "福", Color(1.0, 0.5, 0.2))

	# Corde sacrée (shimenawa) et boîte à offrandes sous le pavillon.
	_mesh_cylinder_at(Vector3(0, top + 2.6, -3.9), 0.22, 7.6, _mat("cloth_indigo"), Vector3(0, 0, PI / 2))
	_box(Vector3(0, top + 0.45, -2.6), Vector3(2.4, 0.9, 1.1), _mat("wood_dark"))
	_mesh_box(Vector3(0, top + 0.92, -2.6), Vector3(2.5, 0.08, 1.2), _mat("gold_trim"))

	# Grand torii au sud de l'estrade, sur le parvis : le repère visuel de la map.
	_torii(Vector3(0, 0, 14.0), 0.0, 1.6, "神社")
	# Deux gardiens de pierre (komainu stylisés) de part et d'autre.
	for side in [-1.0, 1.0]:
		_komainu(Vector3(side * 4.6, 0, 11.0), side)
	# Allée de lanternes de pierre vers le torii.
	for i in 4:
		for side in [-1.0, 1.0]:
			_stone_lantern(Vector3(side * 5.2, 0, 17.0 + i * 5.0))


## Portique vermillon. `scale_factor` 1.0 = environ 5 m de haut.
func _torii(pos: Vector3, yaw: float, scale_factor := 1.0, plaque := "") -> void:
	var basis := Basis(Vector3.UP, yaw)
	var h := 5.0 * scale_factor
	var span := 3.2 * scale_factor
	var post := 0.3 * scale_factor
	for side in [-1.0, 1.0]:
		# Les piliers d'un torii sont légèrement inclinés vers l'intérieur.
		var pillar := _cylinder(pos + basis * Vector3(side * span, h / 2, 0), post, h, _mat("lacquer_red"))
		pillar.rotation.y = yaw
		pillar.rotation.z = -side * 0.025
		# Socle de pierre.
		_mesh_cylinder_at(pos + basis * Vector3(side * span, 0.25, 0), post * 1.5, 0.5, _mat("stone_grey"))
	# Linteau courbe (deux barres) + entretoise.
	_mesh_box_rot(pos + Vector3(0, h + 0.1 * scale_factor, 0),
		Vector3(span * 2.9, 0.42 * scale_factor, 0.55 * scale_factor), _mat("lacquer_red"), yaw)
	_mesh_box_rot(pos + Vector3(0, h + 0.45 * scale_factor, 0),
		Vector3(span * 3.1, 0.3 * scale_factor, 0.75 * scale_factor), _mat("lacquer_black"), yaw)
	_mesh_box_rot(pos + Vector3(0, h - 0.8 * scale_factor, 0),
		Vector3(span * 2.3, 0.3 * scale_factor, 0.4 * scale_factor), _mat("lacquer_red"), yaw)
	if not plaque.is_empty():
		_mesh_box_rot(pos + Vector3(0, h - 0.3 * scale_factor, 0),
			Vector3(1.5 * scale_factor, 1.1 * scale_factor, 0.16), _mat("lacquer_black"), yaw)
		var label := _jp_sign(plaque, pos + basis * Vector3(0, h - 0.3 * scale_factor, 0.12 * scale_factor),
			yaw, 70, 0.009 * scale_factor, Color(1.0, 0.86, 0.45))
		label.outline_size = 0


## Gardien de pierre à l'entrée du sanctuaire (forme stylisée, pas un modèle détaillé).
func _komainu(pos: Vector3, facing: float) -> void:
	var stone := _mat("stone_grey")
	_box(pos + Vector3(0, 0.45, 0), Vector3(1.5, 0.9, 1.0), stone)              # socle
	_mesh_box(pos + Vector3(0, 1.25, 0), Vector3(0.75, 0.8, 1.3), stone)        # corps
	_mesh_box(pos + Vector3(0, 1.95, -0.35), Vector3(0.6, 0.6, 0.6), stone)     # tête
	_mesh_box(pos + Vector3(0, 2.3, -0.45), Vector3(0.62, 0.12, 0.3), stone)    # crinière
	_mesh_cylinder_at(pos + Vector3(0, 1.6, 0.6), 0.1, 0.9, stone, Vector3(0.6, 0, 0))  # queue
	# Museau tourné vers l'allée centrale.
	_mesh_box(pos + Vector3(-facing * 0.2, 1.9, -0.65), Vector3(0.3, 0.3, 0.3), stone)


## Lanterne de pierre du jardin (tōrō).
func _stone_lantern(pos: Vector3) -> void:
	var stone := _mat("stone_grey")
	_cylinder(pos + Vector3(0, 0.3, 0), 0.34, 0.6, stone)
	_mesh_cylinder_at(pos + Vector3(0, 0.95, 0), 0.16, 0.8, stone)
	_mesh_box(pos + Vector3(0, 1.45, 0), Vector3(0.75, 0.18, 0.75), stone)
	# Chambre de la flamme, éclairée.
	var fire := StandardMaterial3D.new()
	fire.albedo_color = Color(1.0, 0.85, 0.6)
	fire.emission_enabled = true
	fire.emission = Color(1.0, 0.6, 0.25)
	fire.emission_energy_multiplier = 2.4
	_mesh_box(pos + Vector3(0, 1.75, 0), Vector3(0.44, 0.44, 0.44), fire)
	for side in [-1.0, 1.0]:
		_mesh_box(pos + Vector3(side * 0.26, 1.75, 0), Vector3(0.08, 0.5, 0.5), stone)
	_roof(pos + Vector3(0, 2.05, 0), 1.1, 1.1, 0.4, 0.0, "stone_grey")
	_mesh_sphere(pos + Vector3(0, 2.35, 0), 0.12, stone)


# =========================================================================== nord-ouest : le marché

func _build_market() -> void:
	for s in STALLS:
		_stall(s[0], s[1], s[2], s[3], s[4])
	for c in CRATES:
		_crate(c[0], c[1], c[2])

	# Portique d'entrée du marché + bannière.
	_torii(Vector3(-30, 0, -18), 0.0, 1.1, "市場")
	_nobori("商店街", Vector3(-24, 0, -20), 0.3, Color(0.72, 0.13, 0.1))
	_nobori("名物", Vector3(-36, 0, -20), -0.2, Color(0.09, 0.13, 0.26))

	# Grande halle ouverte : charpente de bois et toit de tuiles sur poteaux.
	var roof_y := 5.4
	for x in [-52.0, -42.0, -32.0, -22.0]:
		for z in [-56.0, -44.0, -32.0]:
			_cylinder(Vector3(x, roof_y / 2, z), 0.26, roof_y, _mat("wood_beam"))
	for z in [-56.0, -44.0, -32.0]:
		_mesh_box(Vector3(-37, roof_y, z), Vector3(32, 0.4, 0.6), _mat("wood_beam"))
	for x in [-52.0, -42.0, -32.0, -22.0]:
		_mesh_box(Vector3(x, roof_y + 0.3, -44), Vector3(0.5, 0.35, 26), _mat("wood_beam"))
	_roof(Vector3(-37, roof_y + 0.9, -44), 34.0, 28.0, 2.2, 0.0, "roof_tile_blue")

	# Guirlande de lanternes sous la halle.
	for i in 9:
		_lantern(Vector3(-54.0 + i * 4.0, roof_y - 0.1, -44.0), 1.1,
			["酒", "麺", "魚", "茶"][i % 4], Color(1.0, 0.45, 0.2))

	# Échoppe de ramen avec son noren et son comptoir.
	_shop(Vector3(-18, 0, -38), PI / 2, "ラーメン", "neon_gold", Color(0.72, 0.13, 0.1))
	_shop(Vector3(-18, 0, -52), PI / 2, "居酒屋", "neon_pink", Color(0.09, 0.13, 0.26))


## Étal du marché : échoppe couverte au sol, pile de caisses ou de tonneaux à l'étage.
## Mêmes dimensions que les anciens conteneurs : la couverture de jeu est identique.
func _stall(x: float, z: float, along_x: bool, level: int, style: String) -> void:
	var size := STALL_SIZE if along_x else Vector3(STALL_SIZE.z, STALL_SIZE.y, STALL_SIZE.x)
	var center := Vector3(x, STALL_SIZE.y / 2 + level * STALL_SIZE.y, z)
	if style == "barrels":
		# Rangée de tonneaux de saké, ceinturés de corde.
		_collider_box(center, size)
		var count := 4
		for i in count:
			var offset := (i - (count - 1) / 2.0) * (size.x if along_x else size.z) / count
			var p := center + (Vector3(offset, 0, 0) if along_x else Vector3(0, 0, offset))
			_mesh_cylinder_at(p, 0.78, size.y * 0.95, _mat("wood_warm"))
			for band in [-0.5, 0.0, 0.5]:
				_mesh_cylinder_at(p + Vector3(0, band * size.y * 0.7, 0), 0.82, 0.12, _mat("cloth_indigo"))
		return
	if style == "crates":
		# Pile de caisses de bois.
		_collider_box(center, size)
		var cols := 3 if along_x else 2
		for i in cols:
			for j in 2:
				var span := (size.x if along_x else size.z)
				var offset := (i - (cols - 1) / 2.0) * span / cols
				var p := center + (Vector3(offset, 0, 0) if along_x else Vector3(0, 0, offset))
				p.y = center.y - size.y / 2 + 0.65 + j * 1.3
				_mesh_box(p, Vector3(1.2, 1.25, 1.2), _mat("wood_warm"))
		return

	# Échoppe : comptoir de bois, toit de tuiles, rideau noren et lanterne.
	var cloth: Color = {
		"indigo": Color(0.09, 0.13, 0.26), "red": Color(0.6, 0.12, 0.12),
		"green": Color(0.1, 0.26, 0.2), "cream": Color(0.85, 0.8, 0.68),
	}.get(style, Color(0.09, 0.13, 0.26))
	_box(center, size, _mat("wood_warm"))
	_mesh_box(center + Vector3(0, size.y / 2 + 0.06, 0), size * Vector3(1, 0, 1) + Vector3(0.5, 0.12, 0.5), _mat("wood_dark"))
	_roof(center + Vector3(0, size.y / 2 + 0.5, 0), size.x + 1.4, size.z + 1.4, 0.9, 0.0, "roof_tile_dark")
	# Bandeau de tissu sur la face avant.
	var front := Vector3(0, 0, size.z / 2 + 0.05) if along_x else Vector3(size.x / 2 + 0.05, 0, 0)
	var cloth_material: StandardMaterial3D = _mat("cloth_indigo").duplicate()
	cloth_material.albedo_color = cloth
	_mesh_box(center + front + Vector3(0, size.y * 0.3, 0),
		Vector3(size.x * 0.95, 0.5, 0.06) if along_x else Vector3(0.06, 0.5, size.z * 0.95), cloth_material, false)
	if level == 0:
		_lantern(center + front * 1.2 + Vector3(0, size.y * 0.55, 0), 0.0, "", Color(1.0, 0.5, 0.25))


## Caisse de bois cerclée (couverture basse).
func _crate(x: float, z: float, level: int) -> void:
	var s := 1.6
	var center := Vector3(x, s / 2 + level * s, z)
	_box(center, Vector3(s, s, s), _mat("wood_warm"))
	for axis in [Vector3(1, 0, 0), Vector3(0, 0, 1)]:
		_mesh_box(center + axis * (s / 2 + 0.01), Vector3(s * 1.02, 0.14, s * 1.02) * (Vector3.ONE - axis) + axis * 0.02,
			_mat("wood_dark"), false)


## Petite boutique adossée : façade, rideau métallique, enseigne néon verticale.
func _shop(pos: Vector3, yaw: float, text: String, neon: String, cloth: Color) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var w := 7.0
	var d := 5.0
	var h := 4.2
	var body := _box(pos + Vector3(0, h / 2, 0), Vector3(w, h, d), _mat("plaster_white"))
	body.rotation.y = yaw
	_roof(pos + Vector3(0, h + 0.5, 0), w + 2.0, d + 2.0, 1.3, yaw, "roof_tile_dark")
	# Devanture : rideau métallique à moitié baissé + comptoir.
	_mesh_box_rot(pos + basis * Vector3(0, h * 0.72, -d / 2 - 0.06), Vector3(w * 0.8, h * 0.4, 0.1), _mat("shutter_metal"), yaw)
	_mesh_box_rot(pos + basis * Vector3(0, 0.55, -d / 2 - 0.5), Vector3(w * 0.8, 1.1, 0.9), _mat("wood_warm"), yaw)
	# Noren fendu au-dessus du comptoir.
	_noren(text, pos + basis * Vector3(0, h * 0.5, -d / 2 - 0.55), yaw, cloth)
	_vertical_sign(text, pos + basis * Vector3(w / 2 - 0.2, h * 0.6, -d / 2 - 0.35), yaw, 0.9, 2.6, neon)
	_lantern(pos + basis * Vector3(-w / 2 + 0.6, h * 0.62, -d / 2 - 0.5), 0.5, "", Color(1.0, 0.5, 0.25))


# =========================================================================== nord-est : le laboratoire IoT

## Bâtiment moderne du quartier néon : atelier au rez-de-chaussée (bras robotiques,
## tapis roulant), mezzanine accessible par une rampe, grand écran de supervision.
func _build_lab() -> void:
	var x0 := 18.0
	var x1 := 56.0
	var z0 := -56.0
	var z1 := -22.0
	var h := 7.0
	var cx := (x0 + x1) / 2
	var cz := (z0 + z1) / 2

	# Murs : béton côté extérieur, grandes ouvertures côté arène.
	_wall_with_openings(Vector3(x0, 0, z0), Vector3(x1, 0, z0), h, 0.6, [[26.0, 32.0], [44.0, 50.0]], 4.0, _mat("wall_concrete"))
	_wall_with_openings(Vector3(x0, 0, z1), Vector3(x1, 0, z1), h, 0.6, [[22.0, 30.0], [40.0, 48.0]], 4.5, _mat("wall_concrete"))
	_wall_with_openings(Vector3(x0, 0, z0), Vector3(x0, 0, z1), h, 0.6, [[-46.0, -40.0]], 4.5, _mat("wall_concrete"))
	_box(Vector3(x1, h / 2, cz), Vector3(0.6, h, z1 - z0), _mat("wall_concrete"))
	# Toit plat débordant + liseré néon tout autour.
	_mesh_box(Vector3(cx, h + 0.3, cz), Vector3(x1 - x0 + 2.4, 0.6, z1 - z0 + 2.4), _mat("metal_dark"))
	_neon_ring(Vector3(cx, h - 0.1, cz), x1 - x0 + 1.0, z1 - z0 + 1.0, "neon_cyan")

	# Équipements sur le toit (le bâtiment se voit de toute la map).
	for i in 3:
		_mesh_box(Vector3(x0 + 8 + i * 12, h + 1.4, cz - 6), Vector3(4.0, 1.6, 3.0), _mat("metal_light"))
		_mesh_box(Vector3(x0 + 8 + i * 12, h + 2.3, cz - 6), Vector3(3.4, 0.2, 2.4), _mat("metal_dark"))
		_neon(Vector3(x0 + 8 + i * 12, h + 0.75, cz + 6), Vector3(5.0, 0.1, 0.1), "neon_pink")
	_mesh_box(Vector3(x1 - 5, h + 2.6, cz + 8), Vector3(1.2, 4.0, 1.2), _mat("metal_dark"))
	_neon(Vector3(x1 - 5, h + 4.5, cz + 8), Vector3(1.4, 0.12, 1.4), "neon_pink")

	# Mezzanine au fond, accessible par une rampe.
	var mezz_y := 3.5
	_box(Vector3(x1 - 7, mezz_y, cz), Vector3(13, 0.4, 22), _mat("grating"))
	for side in [-1.0, 1.0]:
		_box(Vector3(x1 - 7, mezz_y + 0.6, cz + side * 11), Vector3(13, 1.1, 0.2), _mat("metal_light"))
	_box(Vector3(x1 - 13.4, mezz_y + 0.6, cz), Vector3(0.2, 1.1, 22), _mat("metal_light"))
	_stairs(Vector3(x0 + 7, 0, cz + 8), Vector3(x1 - 13, mezz_y, cz + 8), 3.4, _mat("grating"))

	# Atelier : deux bras robotiques de part et d'autre d'un tapis roulant.
	var conveyor := Conveyor.new()
	conveyor.length = 16.0
	_root.add_child(conveyor)
	conveyor.position = Vector3(cx - 4, 0.9, cz - 6)
	_box(Vector3(cx - 4, 0.45, cz - 6), Vector3(16, 0.9, 1.6), _mat("metal_dark"))
	for i in 2:
		var arm := RobotArm.new()
		arm.phase_offset = i * 0.5
		_root.add_child(arm)
		arm.position = Vector3(cx - 9 + i * 10, 0.0, cz - 8.4)
		arm.rotation.y = PI

	# Écran de supervision sur le mur du fond.
	var dashboard := IotDashboard.new()
	dashboard.size = Vector2(9.0, 3.4)
	_root.add_child(dashboard)
	dashboard.position = Vector3(cx + 2, 4.6, z0 + 0.8)
	dashboard.rotation.y = PI

	# Casiers et établis (couverture).
	for i in 4:
		_box(Vector3(x0 + 6 + i * 6, 1.0, z1 - 4), Vector3(3.6, 2.0, 1.2), _mat("metal_light"))
	_box(Vector3(x0 + 7, 0.5, cz + 2), Vector3(5.0, 1.0, 2.4), _mat("metal_dark"))

	# Enseignes : le nom du laboratoire, en japonais à l'extérieur.
	_vertical_sign("研究所", Vector3(x0 - 0.6, h - 1.0, z1 + 1.2), PI, 1.6, 5.0, "neon_cyan")
	_jp_sign("IoT 研究所", Vector3(cx, h + 1.6, z1 + 1.6), PI, 120, 0.028, Color(0.4, 2.2, 2.4))
	_sign("LAB IoT", Vector3(cx, h + 0.9, z1 + 1.6), PI, 90, 0.02, Color(1.6, 1.7, 1.9))


# =========================================================================== sud-ouest : la pagode

## Pagode à cinq toits (point haut de la map) et tour de guet en bois,
## reliées par une passerelle à 5 m. Remplace les anciens échafaudages.
func _build_pagoda() -> void:
	var pagoda_pos := Vector3(-46, 0, 25)
	var yagura_pos := Vector3(-26, 0, 25)
	var deck := 5.0

	# Socle de la pagode : on peut monter sur sa première toiture-terrasse.
	_pagoda(pagoda_pos, 5, 6.0, 0.0, true)
	# Escalier d'accès à la terrasse.
	_stairs(pagoda_pos + Vector3(0, 0, 16.0), pagoda_pos + Vector3(0, deck, 5.0), 3.2, _mat("wood_warm"))

	# Tour de guet (yagura) : plateforme de bois sur quatre poteaux.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_cylinder(yagura_pos + Vector3(sx * 3.4, deck / 2, sz * 3.4), 0.3, deck, _mat("wood_beam"))
			# Croix de contreventement.
			_mesh_box(yagura_pos + Vector3(sx * 3.4, deck * 0.5, 0), Vector3(0.18, 0.18, 7.2), _mat("wood_beam"))
	_box(yagura_pos + Vector3(0, deck, 0), Vector3(8.4, 0.4, 8.4), _mat("wood_warm"))
	for side in [-1.0, 1.0]:
		_box(yagura_pos + Vector3(side * 4.1, deck + 0.6, 0), Vector3(0.25, 1.1, 8.4), _mat("lacquer_red"))
		_box(yagura_pos + Vector3(0, deck + 0.6, side * 4.1), Vector3(8.4, 1.1, 0.25), _mat("lacquer_red"))
	_roof(yagura_pos + Vector3(0, deck + 3.4, 0), 9.6, 9.6, 1.6, 0.0, "roof_tile_dark")
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_cylinder(yagura_pos + Vector3(sx * 3.4, deck + 1.6, sz * 3.4), 0.18, 2.4, _mat("wood_beam"))
			_lantern(yagura_pos + Vector3(sx * 3.9, deck + 2.6, sz * 3.9), 0.5, "", Color(1.0, 0.45, 0.2))
	# Grand tambour sous la tour (décor).
	_mesh_cylinder_at(yagura_pos + Vector3(0, 1.1, 0), 1.1, 1.6, _mat("lacquer_red"), Vector3(0, 0, PI / 2))

	# Passerelle de bois entre la pagode et la tour, portée par des poteaux.
	_box(Vector3(-36, deck, 25), Vector3(20, 0.35, 3.2), _mat("wood_warm"))
	for x in [-40.0, -36.0, -32.0]:
		for side in [-1.0, 1.0]:
			_mesh_box(Vector3(x, deck / 2, 25 + side * 1.4), Vector3(0.24, deck, 0.24), _mat("wood_beam"))
	for side in [-1.0, 1.0]:
		_box(Vector3(-36, deck + 0.55, 25 + side * 1.7), Vector3(20, 1.0, 0.18), _mat("lacquer_red"))
	# Rampe d'accès depuis le sol, côté sud.
	_stairs(Vector3(-26, 0, 40.0), Vector3(-26, deck, 29.0), 3.2, _mat("wood_warm"))

	# Mur bas et bosquet de bambous autour du quartier.
	for i in 7:
		_bamboo(Vector3(-56 + i * 1.4, 0, 14.0), 5.2)
		_bamboo(Vector3(-56 + i * 1.4, 0, 38.0), 4.4)
	_nobori("弓", Vector3(-40, 0, 33), 0.1, Color(0.2, 0.35, 0.6))
	_nobori("影", Vector3(-52, 0, 33), -0.1, Color(0.4, 0.15, 0.45))


## Pagode à `levels` toits. `solid` ajoute la collision (celle de la map jouable).
func _pagoda(pos: Vector3, levels: int, base_half: float, yaw: float, solid: bool) -> void:
	var level_h := 3.0
	for i in levels:
		var half_size: float = base_half * (1.0 - i * 0.13)
		var y := 1.0 + i * level_h
		var body_size := Vector3(half_size * 1.5, level_h, half_size * 1.5)
		if solid and i == 0:
			var body := _box(pos + Vector3(0, y + level_h / 2 - 1.0, 0), body_size, _mat("plaster_white"))
			body.rotation.y = yaw
		else:
			var visual := _mesh_box(pos + Vector3(0, y + level_h / 2 - 1.0, 0), body_size, _mat("plaster_white"))
			visual.rotation.y = yaw
		# Piliers d'angle vermillon.
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var p := pos + Basis(Vector3.UP, yaw) * Vector3(sx * half_size * 0.72, y + level_h / 2 - 1.0, sz * half_size * 0.72)
				_mesh_box(p, Vector3(0.3, level_h, 0.3), _mat("lacquer_red"))
		# Toit débordant à chaque étage.
		_roof(pos + Vector3(0, y + level_h - 0.9, 0), half_size * 2.3, half_size * 2.3, 1.1, yaw, "roof_tile_blue")
		if i == 0 and solid:
			# La première toiture sert de terrasse : collision plate par-dessus.
			_collider_box(pos + Vector3(0, y + level_h - 0.35, 0), Vector3(half_size * 2.2, 0.4, half_size * 2.2))
	# Flèche dorée au sommet.
	var top := 1.0 + levels * level_h
	_mesh_cylinder_at(pos + Vector3(0, top + 1.2, 0), 0.12, 2.6, _mat("gold_trim"))
	for i in 3:
		_mesh_cylinder_at(pos + Vector3(0, top + 0.6 + i * 0.45, 0), 0.4 - i * 0.1, 0.1, _mat("gold_trim"))


# =========================================================================== sud-est : le jardin

func _build_garden() -> void:
	# Bassin à carpes au milieu du jardin, bordé de pierres.
	var pond := Vector3(34, 0, 38)
	var pond_size := Vector2(16.0, 11.0)
	var koi := KoiPond.new()
	koi.size = pond_size
	_root.add_child(koi)
	koi.position = pond + Vector3(0, 0.04, 0)
	# Margelle : quatre murets bas (on contourne le bassin).
	for side in [-1.0, 1.0]:
		_box(pond + Vector3(0, 0.2, side * (pond_size.y / 2 + 0.4)), Vector3(pond_size.x + 1.6, 0.4, 0.8), _mat("stone_grey"))
		_box(pond + Vector3(side * (pond_size.x / 2 + 0.4), 0.2, 0), Vector3(0.8, 0.4, pond_size.y + 1.6), _mat("stone_grey"))

	# Pont rouge arqué au-dessus du bassin (passage surélevé).
	_arched_bridge(pond + Vector3(0, 0, -pond_size.y / 2 - 2.0), pond + Vector3(0, 0, pond_size.y / 2 + 2.0), 3.0)

	# Pavillon de thé ouvert, dans l'angle du jardin.
	var tea := Vector3(50, 0, 52)
	_box(tea + Vector3(0, 0.35, 0), Vector3(8.0, 0.7, 8.0), _mat("stone_grey"))
	_mesh_box(tea + Vector3(0, 0.72, 0), Vector3(7.4, 0.08, 7.4), _mat("floor_tatami"))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_cylinder(tea + Vector3(sx * 3.2, 2.1, sz * 3.2), 0.18, 3.0, _mat("wood_beam"))
	# Cloisons de papier sur deux côtés.
	_mesh_box(tea + Vector3(0, 2.1, 3.3), Vector3(6.8, 2.6, 0.1), _mat("shoji_paper"))
	_mesh_box(tea + Vector3(3.3, 2.1, 0), Vector3(0.1, 2.6, 6.8), _mat("shoji_paper"))
	_roof(tea + Vector3(0, 3.9, 0), 9.6, 9.6, 1.8, 0.0, "roof_tile_blue")
	_jp_sign("茶室", tea + Vector3(0, 3.2, -3.5), 0.0, 60, 0.012, Color(0.2, 0.18, 0.15))

	# Cerisiers, lanternes de pierre et rochers.
	for t in CHERRY_TREES:
		_cherry(t[0], t[1], t[2])
	for p in [[18, 30], [44, 26], [26, 56], [54, 42], [38, 20]]:
		_stone_lantern(Vector3(p[0], 0, p[1]))
	for r in [[22, 24, 1.3], [48, 34, 1.0], [30, 48, 1.5], [18, 44, 0.9], [56, 24, 1.2]]:
		_rock(Vector3(r[0], 0, r[1]), r[2])

	# Bornes et bancs de pierre du jardin et des allées (couverture basse).
	for b in STONE_BLOCKS:
		_stone_block(b[0], b[1], b[2])

	# Haie de bambous le long du mur est.
	for i in 16:
		_bamboo(Vector3(57.0, 0, 20.0 + i * 2.2), 4.8)
	_nobori("庭園", Vector3(14, 0, 24), 0.0, Color(0.1, 0.26, 0.2))


## Pont de bois rouge en dos d'âne (trois segments, praticable).
func _arched_bridge(from: Vector3, to: Vector3, width: float) -> void:
	var direction := (to - from)
	var length := direction.length()
	var mid := (from + to) * 0.5
	var rise := 1.4
	var step := length / 3.0
	var dir := direction.normalized()
	_ramp(from, mid - dir * step * 0.5 + Vector3(0, rise, 0), width, _mat("lacquer_red"))
	_box(mid + Vector3(0, rise, 0), Vector3(width, 0.3, step) if absf(dir.z) > 0.5 else Vector3(step, 0.3, width), _mat("lacquer_red"))
	_ramp(to, mid + dir * step * 0.5 + Vector3(0, rise, 0), width, _mat("lacquer_red"))
	# Garde-corps : poteaux le long du tablier.
	for i in 5:
		var t := i / 4.0
		var p := from.lerp(to, t)
		var y := rise * sin(t * PI) + 0.8
		for side in [-1.0, 1.0]:
			var across: Vector3 = Vector3(dir.z, 0, dir.x) * (side as float) * width * 0.5
			_mesh_box(p + across + Vector3(0, y, 0), Vector3(0.16, 1.1, 0.16), _mat("lacquer_red"))


## Tige de bambou avec sa touffe de feuilles.
func _bamboo(pos: Vector3, height: float) -> void:
	_mesh_cylinder_at(pos + Vector3(0, height / 2, 0), 0.09, height, _mat("bamboo"))
	# Nœuds réguliers le long de la tige.
	for i in int(height / 1.2):
		_mesh_cylinder_at(pos + Vector3(0, 1.0 + i * 1.2, 0), 0.11, 0.06, _mat("wood_warm"))
	# Feuillage : quelques palettes fines en haut.
	for i in 4:
		var angle := TAU * i / 4.0 + randf() * 0.4
		var leaf := _mesh_box(pos + Vector3(cos(angle) * 0.35, height - 0.4 + i * 0.22, sin(angle) * 0.35),
			Vector3(0.9, 0.05, 0.22), _mat("foliage"), false)
		leaf.rotation = Vector3(0, -angle, 0.35)


## Rocher du jardin (forme irrégulière faite de deux blocs).
func _rock(pos: Vector3, scale_factor: float) -> void:
	var rock := _box(pos + Vector3(0, scale_factor * 0.45, 0), Vector3(1.6, 0.9, 1.3) * scale_factor, _mat("stone_grey"))
	rock.rotation.y = randf() * TAU
	var cap := _mesh_box(pos + Vector3(0, scale_factor * 0.95, 0), Vector3(1.1, 0.7, 0.9) * scale_factor, _mat("stone_grey"))
	cap.rotation = Vector3(0.1, randf() * TAU, 0.08)


## Borne / banc de pierre, à la place des anciennes barrières de béton.
func _stone_block(x: float, z: float, angle_deg: float) -> void:
	var body := _box(Vector3(x, 0.55, z), Vector3(2.6, 1.1, 0.8), _mat("stone_grey"))
	body.rotation.y = deg_to_rad(angle_deg)
	var cap := _mesh_box(Vector3(x, 1.14, z), Vector3(2.8, 0.12, 1.0), _mat("stone_grey"))
	cap.rotation.y = deg_to_rad(angle_deg)


# =========================================================================== les ruelles

## Les deux avenues deviennent des ruelles commerçantes : enseignes verticales,
## distributeurs, lampadaires de pierre et guirlandes de lanternes.
func _build_streets() -> void:
	var half := ROAD_HALF_WIDTH
	# Marquage central discret au sol.
	for axis in [0, 1]:
		var i := -HALF + 6.0
		while i < HALF - 2:
			var pos := Vector3(i, 0.02, 0) if axis == 0 else Vector3(0, 0.02, i)
			var size := Vector3(2.4, 0.02, 0.18) if axis == 0 else Vector3(0.18, 0.02, 2.4)
			if absf(i) > 18.0:
				_mesh_box(pos, size, _mat("paint_white"), false)
			i += 6.0

	# Lampadaires et guirlandes le long des deux axes.
	var s := -HALF + 12.0
	while s < HALF - 6:
		if absf(s) > 16.0:
			for side in [-1.0, 1.0]:
				_street_light(Vector3(s, 0, side * (half - 1.0)), Vector3(0, 0, -side))
				_street_light(Vector3(side * (half - 1.0), 0, s), Vector3(-side, 0, 0))
		s += 16.0

	# Enseignes verticales néon de part et d'autre de la ruelle nord.
	var shops := [
		["寿司", "neon_pink", -34.0], ["喫茶", "neon_cyan", -46.0],
		["電気", "neon_gold", -24.0], ["薬", "neon_green", -52.0],
	]
	for item in shops:
		for side in [-1.0, 1.0]:
			_vertical_sign(item[0], Vector3(side * (half - 1.4), 5.0, item[2]), -side * PI / 2, 1.4, 3.6, item[1])

	# Distributeurs de boissons adossés le long des ruelles.
	_vending(Vector3(-8.6, 0, -28.0), PI / 2, Color(0.85, 0.12, 0.18))
	_vending(Vector3(-8.6, 0, -30.0), PI / 2, Color(0.1, 0.35, 0.75))
	_vending(Vector3(8.6, 0, 32.0), -PI / 2, Color(0.95, 0.7, 0.1))
	_vending(Vector3(-28.0, 0, 8.6), PI, Color(0.2, 0.6, 0.35))
	_vending(Vector3(-30.0, 0, 8.6), PI, Color(0.85, 0.12, 0.18))

	# Panneaux d'information japonais aux carrefours.
	_info_panel("中央通り", Vector3(-7.0, 0, -24.0), 0.0, Color(0.95, 0.95, 1.0))
	_info_panel("立入禁止", Vector3(7.0, 0, 24.0), PI, Color(1.6, 0.5, 0.5))


## Panneau d'information sur poteau (texte japonais sur fond sombre).
func _info_panel(text: String, pos: Vector3, yaw: float, color: Color) -> void:
	var basis := Basis(Vector3.UP, yaw)
	_cylinder(pos + Vector3(0, 1.3, 0), 0.08, 2.6, _mat("wood_dark"))
	var panel := _mesh_box(pos + Vector3(0, 2.3, 0), Vector3(2.2, 0.9, 0.12), _mat("lacquer_black"))
	panel.rotation.y = yaw
	var label := _jp_sign(text, pos + Vector3(0, 2.3, 0) + basis * Vector3(0, 0, -0.08), yaw, 60, 0.009, color)
	label.outline_size = 0


## Lampadaire de pierre avec lanterne de papier.
func _street_light(base: Vector3, facing: Vector3) -> void:
	_cylinder(base + Vector3(0, 2.2, 0), 0.14, 4.4, _mat("stone_grey"))
	var head := base + Vector3(0, 4.4, 0) + facing * 0.5
	_mesh_box(base + Vector3(0, 4.4, 0) + facing * 0.25, Vector3(0.12, 0.12, 1.0) if absf(facing.z) > 0.5 else Vector3(1.0, 0.12, 0.12), _mat("wood_dark"))
	_lantern(head, 0.45, "", Color(1.0, 0.55, 0.3))


# =========================================================================== CFA INSTA

## Références à l'école, intégrées au décor : enseigne néon sur le laboratoire,
## plaque du sanctuaire, bannières et banderole d'arène.
func _build_cfa_insta() -> void:
	# Grande enseigne néon au-dessus du laboratoire (visible de toute la map).
	var panel := Vector3(37, 10.5, -21.0)
	_mesh_box(panel, Vector3(22, 4.2, 0.5), _mat("lacquer_black"))
	_neon_frame(panel + Vector3(0, 0, 0.3), 22.0, 4.2, "neon_pink")
	_sign("CFA INSTA", panel + Vector3(0, 0.7, 0.4), PI, 150, 0.021, Color(2.4, 1.0, 2.2))
	_jp_sign("シーエフエー インスタ", panel + Vector3(0, -0.9, 0.4), PI, 70, 0.012, Color(0.5, 2.0, 2.2))

	# Plaque gravée à l'entrée du sanctuaire.
	_jp_sign("ネオ江戸アリーナ", Vector3(0, 7.9, 13.4), PI, 80, 0.0075, Color(1.0, 0.9, 0.6))

	# Bannières de l'école de part et d'autre du parvis.
	for side in [-1.0, 1.0]:
		_nobori("インスタ", Vector3(side * 12.0, 0, 20.0), 0.0, Color(0.72, 0.13, 0.1))

	# Banderole au-dessus de la ruelle nord.
	var banner := Vector3(0, 6.2, -30.0)
	for side in [-1.0, 1.0]:
		_cylinder(banner + Vector3(side * 9.0, -3.1 + 0.0, 0), 0.16, 6.2, _mat("wood_beam"))
	_mesh_box(banner, Vector3(18.0, 1.8, 0.2), _mat("cloth_indigo"))
	_sign("CFA INSTA · ARENA", banner + Vector3(0, 0.25, 0.15), PI, 90, 0.013, Color(1.0, 0.92, 0.75))
	_jp_sign("アーキテクチャ", banner + Vector3(0, -0.5, 0.15), PI, 60, 0.009, Color(0.9, 0.82, 0.7))


# =========================================================================== décor connecté (IoT)

## Caméras de surveillance, fixées sur les lampadaires des ruelles par un petit bras
## (plus rien ne flotte : les anciens capteurs et drones ont été retirés).
## [position du pied du lampadaire, direction vers laquelle regarde la caméra]
const CAMERA_POLES := [
	[Vector3(-32, 0, -9), Vector3(0, 0, 1)], [Vector3(32, 0, 9), Vector3(0, 0, -1)],
	[Vector3(-9, 0, 32), Vector3(1, 0, 0)], [Vector3(9, 0, -32), Vector3(-1, 0, 0)],
	[Vector3(48, 0, -9), Vector3(0, 0, 1)], [Vector3(-48, 0, 9), Vector3(0, 0, -1)],
]


func _build_connected_decor() -> void:
	for c in CAMERA_POLES:
		var base: Vector3 = c[0]
		var facing: Vector3 = c[1]
		# Bras de fixation contre le poteau, côté opposé à la lanterne.
		var arm_end := base + Vector3(0, 4.0, 0) + facing * 0.45
		_mesh_box(base + Vector3(0, 4.0, 0) + facing * 0.22, Vector3(0.1, 0.1, 0.45) if absf(facing.z) > 0.5 else Vector3(0.45, 0.1, 0.1), _mat("stone_grey"))
		var cam := SecurityCamera.new()
		_root.add_child(cam)
		cam.position = arm_end + Vector3(0, 0.05, 0)
		cam.rotation.y = atan2(-facing.x, -facing.z) + PI


# =========================================================================== éléments japonais réutilisables

## Toit japonais : plusieurs couches décroissantes (pente), débord, faîtage et
## relevés d'angle. `size_x` / `size_z` = emprise au sol du toit.
func _roof(center: Vector3, size_x: float, size_z: float, height: float, yaw: float, material_name: String) -> void:
	var material := _mat(material_name)
	var layers := 5
	for i in layers:
		var t := float(i) / layers
		var shrink := 1.0 - t * 0.72
		var y := center.y + t * height
		var layer := _mesh_box(Vector3(center.x, y, center.z),
			Vector3(size_x * shrink, height / layers * 1.6, size_z * shrink), material)
		layer.rotation.y = yaw
	# Faîtage sombre au sommet.
	var ridge := _mesh_box(center + Vector3(0, height + 0.05, 0),
		Vector3(size_x * 0.32, 0.22, size_z * 0.32), _mat("lacquer_black"))
	ridge.rotation.y = yaw
	# Relevés d'angle : petits blocs inclinés qui donnent la courbe typique.
	var basis := Basis(Vector3.UP, yaw)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var corner := center + basis * Vector3(sx * size_x * 0.47, 0.12, sz * size_z * 0.47)
			var tip := _mesh_box(corner, Vector3(size_x * 0.16, 0.18, size_z * 0.16), material)
			tip.rotation = Vector3(sz * 0.3, yaw, -sx * 0.3)


## Enseigne verticale lumineuse (caractères empilés sur un panneau).
func _vertical_sign(text: String, pos: Vector3, yaw: float, width: float, height: float, neon_material: String) -> void:
	var panel := _mesh_box(pos, Vector3(width, height, 0.18), _mat("lacquer_black"))
	panel.rotation.y = yaw
	var glow := _mesh_box(pos + Basis(Vector3.UP, yaw) * Vector3(0, 0, -0.1), Vector3(width * 0.94, height * 0.96, 0.05), _mat(neon_material), false)
	glow.rotation.y = yaw
	# Texte vertical : un caractère par ligne.
	var vertical := ""
	for i in text.length():
		vertical += text[i]
		if i < text.length() - 1:
			vertical += "\n"
	# Un caractère occupe environ 1,3 fois sa hauteur de police : on en déduit la taille.
	var font_size := 96
	var pixel: float = height / (maxi(text.length(), 1) * font_size * 1.32)
	var label := _jp_sign(vertical, pos + Basis(Vector3.UP, yaw) * Vector3(0, 0, -0.16), yaw, font_size, pixel, Color(0.05, 0.03, 0.05))
	label.outline_size = 0


## Lanterne de papier (prop animé) suspendue à `pos`.
func _lantern(pos: Vector3, cord: float, text: String, color: Color) -> void:
	var lantern := PaperLantern.new()
	lantern.cord = cord
	lantern.text = text
	lantern.color = color
	lantern.phase = randf() * TAU
	# Une lanterne sur deux éclaire vraiment : on limite le nombre de lumières.
	lantern.with_light = _root.get_child_count() % 2 == 0
	_root.add_child(lantern)
	lantern.position = pos


## Rideau fendu d'échoppe.
func _noren(text: String, pos: Vector3, yaw: float, color: Color) -> void:
	var noren := FabricBanner.new()
	noren.kind = FabricBanner.Kind.NOREN
	noren.size = Vector2(5.0, 1.1)
	noren.color = color
	noren.text = text
	noren.phase = randf() * TAU
	_root.add_child(noren)
	noren.position = pos
	noren.rotation.y = yaw + PI


## Bannière verticale sur hampe.
func _nobori(text: String, pos: Vector3, yaw: float, color: Color) -> void:
	var banner := FabricBanner.new()
	banner.kind = FabricBanner.Kind.NOBORI
	banner.size = Vector2(0.9, 3.4)
	banner.color = color
	banner.text = text
	banner.phase = randf() * TAU
	_root.add_child(banner)
	banner.position = pos + Vector3(0, 2.6, 0)
	banner.rotation.y = yaw


## Cerisier en fleurs (prop animé avec ses pétales).
func _cherry(x: float, z: float, height: float) -> void:
	var tree := CherryTree.new()
	tree.height = height
	tree.seed_value = int(absf(x * 13 + z * 7))
	_root.add_child(tree)
	tree.position = Vector3(x, 0, z)
	# Tronc solide : on ne traverse pas l'arbre.
	_collider_box(Vector3(x, height * 0.3, z), Vector3(0.7, height * 0.6, 0.7))


## Distributeur de boissons (prop animé, avec sa collision).
func _vending(pos: Vector3, yaw: float, color: Color) -> void:
	var machine := VendingMachine.new()
	machine.body_color = color
	_root.add_child(machine)
	machine.position = pos
	machine.rotation.y = yaw


# =========================================================================== outils de construction

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


## Bloc décoratif tourné autour de l'axe vertical.
func _mesh_box_rot(center: Vector3, size: Vector3, material: Material, yaw: float) -> MeshInstance3D:
	var visual := _mesh_box(center, size, material)
	visual.rotation.y = yaw
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
	mesh.radial_segments = 16
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


## Cylindre décoratif, éventuellement incliné (rotation en radians).
func _mesh_cylinder_at(center: Vector3, radius: float, height: float, material: Material, rotation_rad := Vector3.ZERO) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 14
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	_root.add_child(visual)
	visual.position = center
	visual.rotation = rotation_rad
	return visual


func _mesh_sphere(center: Vector3, radius: float, material: Material) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2
	mesh.radial_segments = 14
	mesh.rings = 7
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	_root.add_child(visual)
	visual.position = center


## Bande lumineuse (néon) : émissive, sans ombre ni collision.
func _neon(center: Vector3, size: Vector3, material_name: String) -> MeshInstance3D:
	return _mesh_box(center, size, _mat(material_name), false)


## Liseré néon autour d'un rectangle horizontal (4 bandes fines sur les bords).
## Cadre néon rectangulaire (bord d'un toit, d'un panneau). `yaw` : rotation du
## support, pour que le cadre reste collé à ses bords.
func _neon_ring(center: Vector3, size_x: float, size_z: float, material_name: String, yaw := 0.0) -> void:
	var t := 0.08
	var basis := Basis(Vector3.UP, yaw)
	var edges := [
		[Vector3(0, 0, size_z / 2), Vector3(size_x + t, t, t)], [Vector3(0, 0, -size_z / 2), Vector3(size_x + t, t, t)],
		[Vector3(size_x / 2, 0, 0), Vector3(t, t, size_z)], [Vector3(-size_x / 2, 0, 0), Vector3(t, t, size_z)],
	]
	for e in edges:
		var piece := _neon(center + basis * (e[0] as Vector3), e[1], material_name)
		if piece:
			piece.rotation.y = yaw


## Cadre néon vertical (contour d'un panneau dans le plan x / y).
func _neon_frame(center: Vector3, width: float, height: float, material_name: String) -> void:
	var t := 0.08
	_neon(center + Vector3(0, height / 2, 0), Vector3(width + t, t, t), material_name)
	_neon(center + Vector3(0, -height / 2, 0), Vector3(width + t, t, t), material_name)
	_neon(center + Vector3(width / 2, 0, 0), Vector3(t, height, t), material_name)
	_neon(center + Vector3(-width / 2, 0, 0), Vector3(t, height, t), material_name)


## Escalier de bois posé sur des piliers : même surface qu'une rampe, mais il ne
## flotte pas en l'air. Utilisé pour tous les accès en hauteur.
func _stairs(bottom: Vector3, top: Vector3, width: float, material: Material) -> void:
	_ramp(bottom, top, width, material)
	var posts := maxi(2, int(bottom.distance_to(top) / 3.0))
	var across := (top - bottom)
	across = Vector3(across.z, 0, across.x).normalized()
	for i in range(1, posts + 1):
		var t := float(i) / (posts + 1)
		var p := bottom.lerp(top, t)
		if p.y < 0.6:
			continue
		for side in [-1.0, 1.0]:
			var foot: Vector3 = p + across * (side as float) * (width * 0.5 - 0.25)
			_mesh_box(Vector3(foot.x, p.y * 0.5, foot.z), Vector3(0.22, p.y, 0.22), _mat("wood_beam"))
	# Garde-corps le long des deux bords.
	for side in [-1.0, 1.0]:
		var a: Vector3 = bottom + across * (side as float) * width * 0.5
		var b: Vector3 = top + across * (side as float) * width * 0.5
		for i in 4:
			var t := i / 3.0
			var p: Vector3 = a.lerp(b, t)
			if p.y < 0.4:
				continue
			_mesh_box(p + Vector3(0, 0.55, 0), Vector3(0.14, 1.1, 0.14), _mat("lacquer_red"))


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
func _wall_with_openings(from: Vector3, to: Vector3, height: float, thickness: float,
		openings: Array, door_height: float, material: Material) -> void:
	var along_x := absf(to.x - from.x) > absf(to.z - from.z)
	var a := from.x if along_x else from.z
	var b := to.x if along_x else to.z
	var fixed := from.z if along_x else from.x
	var cursor := a
	var segments := []
	for o in openings:
		segments.append([cursor, o[0], 0.0, height])          # mur plein avant l'ouverture
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


## Encadrement d'une ouverture : montants de bois et néon au linteau.
func _door_frame(along_x: bool, fixed: float, start: float, end: float, height: float) -> void:
	var neon_size := Vector3(end - start, 0.1, 0.7) if along_x else Vector3(0.7, 0.1, end - start)
	var mid := (start + end) / 2
	var top := Vector3(mid, height - 0.05, fixed) if along_x else Vector3(fixed, height - 0.05, mid)
	_neon(top, neon_size, "neon_cyan")
	for p in [start, end]:
		var pos := Vector3(p, height / 2, fixed) if along_x else Vector3(fixed, height / 2, p)
		_mesh_box(pos, Vector3(0.18, height, 0.72) if along_x else Vector3(0.72, height, 0.18), _mat("wood_dark"), false)


## Texte 3D en alphabet latin (Orbitron), posé sur un mur ou une enseigne.
func _sign(text: String, pos: Vector3, yaw: float, font_size: int, pixel: float, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = TITLE_FONT
	label.font_size = font_size
	label.pixel_size = pixel
	label.modulate = color
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	_root.add_child(label)
	label.position = pos
	label.rotation.y = yaw + PI
	return label


## Texte 3D en japonais (Noto Sans JP).
func _jp_sign(text: String, pos: Vector3, yaw: float, font_size: int, pixel: float, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = JapaneseFont.font()
	label.font_size = font_size
	label.pixel_size = pixel
	label.modulate = color
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(label)
	label.position = pos
	label.rotation.y = yaw + PI
	return label
