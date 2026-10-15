@tool
class_name MallMap
extends ArenaMap
## Map « Hikari Mall » (ひかりモール) : centre commercial abandonné, 100 x 100 m,
## deux niveaux, au crépuscule. Pour 16 joueurs.
##
## Hérite d'ArenaMap pour ses outils de construction (_box, _neon, _ramp, _sign…) ;
## build() et la description de la map (points d'apparition, bonus…) sont redéfinis.
## Comme NEO-EDO, tout est construit par code : ouvrir scenes/maps/mall.tscn et cliquer
## sur « Reconstruire la map » dans l'inspecteur après une modification.
##
## Repère : centre (0, 0), sol à y = 0, étage à y = 5. x = ouest (-) / est (+),
## z = nord (-) / sud (+).
##
##   Centre      atrium vide sur deux niveaux, fontaine à sec, verrière éventrée
##   Ouest       supermarché (rayons = couverts), balcon effondré à l'étage
##   Est         food court (comptoirs, tables), salon à l'étage
##   Nord        hall d'entrée ; boutiques à l'étage
##   Sud         quai de livraison (camions, palettes) ; réserve à l'étage
##   Coins       boutiques ; à l'étage : cinéma (nord-ouest), arcade néon (nord-est)
##   Accès       2 escalators et 2 escaliers dans l'atrium, 2 escaliers dans les
##               coins sud-ouest et nord-est, trous dans le plancher pour sauter

const H := 50.0              # demi-côté (100 m)
const LEVEL := 5.0           # hauteur du sol de l'étage
const SLAB := 0.4            # épaisseur du plancher
const ROOF := 10.5           # hauteur du toit
const ATRIUM := 18.0         # demi-côté du vide central
const RING := 26.0           # limite de la galerie autour de l'atrium

## Trous dans le plancher de l'étage : [x0, z0, x1, z1] (multiples de 2 m).
const HOLES := [
	[-18, -18, 18, 18],      # atrium
	[-40, -6, -34, 0],       # plafond effondré au-dessus du supermarché
	[34, 4, 40, 10],         # plafond effondré au-dessus du food court
	[-48, 24, -44, 36],      # escalier du coin sud-ouest
	[44, -36, 48, -24],      # escalier du coin nord-est
]

const MALL_SPAWNS: Array[Vector3] = [
	# Rez-de-chaussée.
	Vector3(-44, 0, -44), Vector3(44, 0, -44), Vector3(-44, 0, 44), Vector3(44, 0, 44),
	Vector3(-48.5, 0, 0), Vector3(40, 0, -20), Vector3(0, 0, -46), Vector3(0, 0, 46),
	# Étage.
	Vector3(-46, 5, -30), Vector3(44, 5, -30), Vector3(-46, 5, -14), Vector3(46, 5, 12),
	Vector3(0, 5, -46), Vector3(0, 5, 44), Vector3(-40, 5, 44), Vector3(40, 5, 44),
]

const MALL_PICKUPS := [
	[Pickups.Kind.SUPER, Vector3(0, 2, 0)],                 # fontaine de l'atrium : exposé
	[Pickups.Kind.LASER_RIFLE, Vector3(-29, 7, -47)],       # cabine de projection du cinéma
	[Pickups.Kind.MINIGUN, Vector3(0, 2, 36)],              # quai de livraison
	[Pickups.Kind.POWER_FIST, Vector3(32, 2, -18)],         # food court
	[Pickups.Kind.HEAL, Vector3(-39.5, 2, 0)], [Pickups.Kind.HEAL, Vector3(43, 2, -2)],
	[Pickups.Kind.HEAL, Vector3(-20, 2, -40)], [Pickups.Kind.HEAL, Vector3(20, 2, 40)],
	[Pickups.Kind.HEAL, Vector3(-30, 7, 10)], [Pickups.Kind.HEAL, Vector3(31, 7, -16)],
	[Pickups.Kind.ARMOR, Vector3(-44, 2, -32)], [Pickups.Kind.ARMOR, Vector3(44, 2, 32)],
	[Pickups.Kind.ARMOR, Vector3(0, 7, -34)],
	[Pickups.Kind.DOUBLE_JUMP, Vector3(-22, 7, -22)], [Pickups.Kind.DOUBLE_JUMP, Vector3(22, 7, 22)],
	[Pickups.Kind.SPEED, Vector3(-22, 2, 0)], [Pickups.Kind.SPEED, Vector3(22, 2, 0)],
]

const MALL_TARGETS: Array[Vector3] = [
	Vector3(-38, 0, 10), Vector3(36, 0, 14), Vector3(-10, 0, -40), Vector3(10, 0, 38),
	Vector3(-30, 5, 0), Vector3(30, 5, -8), Vector3(0, 5, -34), Vector3(-8, 0, 10),
]

## Couleurs de lumière du crépuscule et des néons.
const DUSK := Color(1.0, 0.62, 0.38)
const NEON_PINK := Color(1.0, 0.35, 0.8)
const NEON_CYAN := Color(0.3, 0.9, 1.0)


# =========================================================================== description

func map_id() -> String:
	return "hikari-mall"


func spawn_points() -> Array:
	return MALL_SPAWNS


func pickup_points() -> Array:
	return MALL_PICKUPS


func target_points() -> Array:
	return MALL_TARGETS


func nav_aabb() -> AABB:
	return AABB(Vector3(-H - 1, -1, -H - 1), Vector3(H * 2 + 2, 12, H * 2 + 2))


# =========================================================================== construction

func build() -> void:
	if _root and is_instance_valid(_root):
		_root.free()
	_root = Node3D.new()
	_root.name = "Generated"
	add_child(_root)

	_mall_environment()
	_mall_shell()
	_mall_level()
	_mall_access()
	_mall_atrium()
	_mall_supermarket()
	_mall_food_court()
	_mall_entrance()
	_mall_loading_bay()
	_mall_corner_shops()
	_mall_cinema()
	_mall_arcade()
	_mall_upper_floor()
	_mall_lights()
	_mall_city()


# --------------------------------------------------------------------------- ambiance

## Crépuscule : soleil très bas et orangé qui entre par la verrière et les vitres
## brisées, ciel violet en haut, brume dorée de poussière.
func _mall_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.2, 0.18, 0.4)
	sky_material.sky_horizon_color = Color(1.0, 0.56, 0.34)
	sky_material.sky_curve = 0.2
	sky_material.ground_bottom_color = Color(0.12, 0.1, 0.12)
	sky_material.ground_horizon_color = Color(0.95, 0.52, 0.34)
	sky_material.sun_angle_max = 30.0
	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.5, 0.5)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.75
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.fog_enabled = true
	env.fog_light_color = Color(0.85, 0.58, 0.45)
	env.fog_density = 0.006
	env.fog_sky_affect = 0.15
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.15
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_root.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.light_color = DUSK
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	sun.shadow_blur = 1.4
	sun.directional_shadow_max_distance = 120.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_root.add_child(sun)
	sun.rotation_degrees = Vector3(-24, -125, 0)     # soleil bas, à l'ouest-sud-ouest


# --------------------------------------------------------------------------- enveloppe

## Sol, murs extérieurs (vitres brisées à l'étage), toit troué au-dessus de l'atrium.
func _mall_shell() -> void:
	# Sol : une seule collision, dallage poli à l'intérieur, béton au quai.
	_collider_box(Vector3(0, -0.5, 0), Vector3(H * 2, 1, H * 2))
	_mesh_box(Vector3(0, -0.5, -6), Vector3(H * 2, 1, H * 2 - 12 - 20), _mat("floor_plaza"), true)
	_mesh_box(Vector3(0, -0.5, 38), Vector3(H * 2, 1, 24), _mat("floor_concrete"), true)
	_mesh_box(Vector3(0, -0.5, -47), Vector3(H * 2, 1, 6), _mat("floor_plaza"), true)
	_mesh_box(Vector3(0, -0.56, 0), Vector3(500, 1, 500), _mat("floor_asphalt"), false)

	# Murs extérieurs : collision pleine sur toute la hauteur (on ne sort pas), et en
	# visuel un mur plein en bas, des fenêtres aux vitres brisées à l'étage.
	for side in [-1.0, 1.0]:
		for along_x in [true, false]:
			var center := Vector3(0, ROOF / 2, side * (H + 0.5)) if along_x else Vector3(side * (H + 0.5), ROOF / 2, 0)
			var size := Vector3(H * 2 + 2, ROOF, 1) if along_x else Vector3(1, ROOF, H * 2 + 2)
			_collider_box(center, size)
			_facade_wall(side, along_x)

	# Toit : tout sauf l'atrium (verrière éventrée, voir _mall_atrium).
	var roof_parts := [
		[Vector3(0, ROOF + 0.3, -(ATRIUM + H) / 2), Vector3(H * 2, 0.6, H - ATRIUM)],
		[Vector3(0, ROOF + 0.3, (ATRIUM + H) / 2), Vector3(H * 2, 0.6, H - ATRIUM)],
		[Vector3(-(ATRIUM + H) / 2, ROOF + 0.3, 0), Vector3(H - ATRIUM, 0.6, ATRIUM * 2)],
		[Vector3((ATRIUM + H) / 2, ROOF + 0.3, 0), Vector3(H - ATRIUM, 0.6, ATRIUM * 2)],
	]
	for r in roof_parts:
		_box(r[0], r[1], _mat("wall_concrete"))

	# Piliers porteurs autour de l'atrium et dans les grandes salles.
	for p in [Vector2(-18, -18), Vector2(18, -18), Vector2(-18, 18), Vector2(18, 18),
			Vector2(-18, -10), Vector2(18, 10), Vector2(-10, 18), Vector2(10, -18),
			Vector2(-38, -14), Vector2(-38, 14), Vector2(38, -12), Vector2(38, 18)]:
		_cylinder(Vector3(p.x, ROOF / 2, p.y), 0.55, ROOF, _mat("wall_concrete"))


## Façade intérieure d'un mur extérieur : mur plein jusqu'à 6 m, fenêtres (cadres et
## éclats de verre) de 6 à 9 m, bandeau au-dessus. Ouvertures : entrée (nord), quai (sud).
func _facade_wall(side: float, along_x: bool) -> void:
	var inner := side * (H - 0.05)
	var wall_len := H * 2
	var lower_h := 6.0
	var mat := _mat("wall_concrete")
	var is_north := along_x and side < 0
	var is_south := along_x and side > 0
	# Partie basse (avec la porte d'entrée au nord et les portes du quai au sud).
	var gaps := []
	if is_north:
		gaps = [[-6.0, 6.0]]
	elif is_south:
		gaps = [[-18.0, -8.0], [8.0, 18.0]]
	var cursor := -H
	for g in gaps + [[H, H]]:
		var a: float = cursor
		var b: float = g[0]
		if b - a > 0.05:
			var mid := (a + b) / 2
			var c := Vector3(mid, lower_h / 2, inner) if along_x else Vector3(inner, lower_h / 2, mid)
			var s := Vector3(b - a, lower_h, 0.3) if along_x else Vector3(0.3, lower_h, b - a)
			_mesh_box(c, s, mat)
		cursor = g[1]
	for g in gaps:
		# Linteau au-dessus des portes, et rideau / portes vitrées fermant l'ouverture.
		var mid: float = (g[0] + g[1]) / 2
		var w: float = g[1] - g[0]
		_mesh_box(Vector3(mid, 5.0, inner), Vector3(w, 2.0, 0.3), mat)
		if is_north:
			_mesh_box(Vector3(mid, 2.0, inner + 0.3), Vector3(w, 4.0, 0.08), _mat("glass"), false)
			_neon(Vector3(mid, 4.05, inner + 0.25), Vector3(w, 0.1, 0.1), "neon_cyan")
		else:
			# Rideau métallique à moitié levé : on voit dehors en bas, mais on ne passe pas.
			_mesh_box(Vector3(mid, 2.8, inner + 0.1), Vector3(w, 2.4, 0.12), _mat("shutter_metal"))
			_mesh_box(Vector3(mid, 0.8, inner + 0.25), Vector3(w, 0.15, 0.2), _mat("paint_yellow"), false)
	# Fenêtres de l'étage : piliers tous les 6 m, éclats de verre.
	var x := -H + 1.0
	while x < H:
		var c := Vector3(x, 7.5, inner) if along_x else Vector3(inner, 7.5, x)
		_mesh_box(c, Vector3(1.2, 3.0, 0.4) if along_x else Vector3(0.4, 3.0, 1.2), mat)
		var pane := Vector3(x + 3.0, 7.5, inner + side * -0.05) if along_x else Vector3(inner + side * -0.05, 7.5, x + 3.0)
		if int(x) % 12 != 1:    # certaines vitres ont disparu, d'autres restent en éclats
			var shard := _mesh_box(pane + Vector3(0, -0.6, 0), Vector3(4.6, 1.6, 0.05) if along_x else Vector3(0.05, 1.6, 4.6), _mat("glass"), false)
			shard.rotation.z = 0.05
		x += 6.0
	var band := Vector3(0, 9.7, inner) if along_x else Vector3(inner, 9.7, 0)
	_mesh_box(band, Vector3(wall_len, 1.6, 0.4) if along_x else Vector3(0.4, 1.6, wall_len), mat)
	_mesh_box(band + Vector3(0, -0.82, 0), Vector3(wall_len, 0.08, 0.5) if along_x else Vector3(0.5, 0.08, wall_len), _mat("metal_dark"), false)


# --------------------------------------------------------------------------- étage

## Plancher de l'étage avec ses trous (atrium, effondrements, escaliers) : découpé en
## rectangles par une grille de 2 m, puis garde-corps autour de l'atrium.
func _mall_level() -> void:
	for r in _slab_rects():
		var x0: float = r[0]
		var z0: float = r[1]
		var x1: float = r[2]
		var z1: float = r[3]
		_box(Vector3((x0 + x1) / 2, LEVEL - SLAB / 2, (z0 + z1) / 2), Vector3(x1 - x0, SLAB, z1 - z0), _mat("floor_plaza"))
	# Bord de l'atrium : nez de dalle métallique et garde-corps vitré (ouvert aux escalators).
	var a := ATRIUM
	var gaps := {"n": [-6.0, -2.0], "s": [2.0, 6.0], "w": [2.0, 6.0], "e": [-6.0, -2.0]}
	for edge in ["n", "s", "w", "e"]:
		var along_x: bool = edge in ["n", "s"]
		var fixed: float = -a if edge in ["n", "w"] else a
		var gap: Array = gaps[edge]
		for seg in [[-a, gap[0]], [gap[1], a]]:
			_railing(along_x, fixed, seg[0], seg[1], LEVEL)
	# Garde-corps cassés autour des effondrements (on peut sauter par les trous).
	_railing(true, -6.0, -40.0, -36.0, LEVEL)
	_railing(false, -34.0, -6.0, -2.0, LEVEL)
	_railing(true, 10.0, 36.0, 40.0, LEVEL)
	_railing(false, 34.0, 4.0, 8.0, LEVEL)


## Rectangles pleins du plancher : grille de 2 m, cellules hors des trous, fusion des
## bandes identiques d'une rangée à l'autre (une vingtaine de blocs au lieu de 2 500).
func _slab_rects() -> Array:
	var cells := int(H)                 # 50 cellules de 2 m
	var open := {}                      # (ligne, x0, x1) -> rectangle en cours
	var done := []
	for row in cells:
		var z0 := -H + row * 2.0
		var runs := []
		var start := -1
		for col in cells + 1:
			var solid := false
			if col < cells:
				var cx := -H + col * 2.0 + 1.0
				var cz := z0 + 1.0
				solid = not HOLES.any(func(h): return cx > h[0] and cx < h[2] and cz > h[1] and cz < h[3])
			if solid and start < 0:
				start = col
			elif not solid and start >= 0:
				runs.append([-H + start * 2.0, -H + col * 2.0])
				start = -1
		var next_open := {}
		for run in runs:
			var key := "%s|%s" % [run[0], run[1]]
			if open.has(key):
				var rect: Array = open[key]
				rect[3] = z0 + 2.0
				next_open[key] = rect
			else:
				next_open[key] = [run[0], z0, run[1], z0 + 2.0]
		for key in open:
			if not next_open.has(key):
				done.append(open[key])
		open = next_open
	done.append_array(open.values())
	return done


## Garde-corps : muret de verre (collision 1,1 m) avec main courante et poteaux.
func _railing(along_x: bool, fixed: float, from: float, to: float, y: float) -> void:
	var length := to - from
	if length <= 0.1:
		return
	var mid := (from + to) / 2
	var center := Vector3(mid, y + 0.55, fixed) if along_x else Vector3(fixed, y + 0.55, mid)
	var size := Vector3(length, 1.1, 0.12) if along_x else Vector3(0.12, 1.1, length)
	_collider_box(center, size)
	_mesh_box(center, size, _mat("glass"), false)
	var rail := Vector3(length, 0.08, 0.14) if along_x else Vector3(0.14, 0.08, length)
	_mesh_box(center + Vector3(0, 0.58, 0), rail, _mat("metal_light"), false)
	var t := from
	while t <= to + 0.01:
		var post := Vector3(t, y + 0.55, fixed) if along_x else Vector3(fixed, y + 0.55, t)
		_mesh_box(post, Vector3(0.08, 1.1, 0.08), _mat("metal_light"), false)
		t += 2.0


## Escalators en panne et escaliers : rampes praticables avec rambardes et néon.
func _mall_access() -> void:
	_escalator(Vector3(-4, 0, -6), Vector3(-4, LEVEL, -18.6), 3.6)      # nord
	_escalator(Vector3(4, 0, 6), Vector3(4, LEVEL, 18.6), 3.6)          # sud
	_escalator(Vector3(-6, 0, 4), Vector3(-18.6, LEVEL, 4), 3.6)        # ouest
	_escalator(Vector3(6, 0, -4), Vector3(18.6, LEVEL, -4), 3.6)        # est
	_escalator(Vector3(-46, 0, 22), Vector3(-46, LEVEL, 36.2), 3.6)     # coin sud-ouest
	_escalator(Vector3(46, 0, -22), Vector3(46, LEVEL, -36.2), 3.6)     # coin nord-est


func _escalator(bottom: Vector3, top: Vector3, width: float) -> void:
	_ramp(bottom, top, width, _mat("grating"))
	var forward := (top - bottom).normalized()
	var across := Vector3(forward.z, 0, -forward.x).normalized()
	for side in [-1.0, 1.0]:
		# Rambarde pleine (collision) le long de chaque bord, avec un néon rose.
		var a: Vector3 = bottom + across * (side as float) * (width / 2 + 0.1)
		var b: Vector3 = top + across * (side as float) * (width / 2 + 0.1)
		var mid := (a + b) / 2 + Vector3(0, 0.6, 0)
		var length := a.distance_to(b)
		var balustrade := _box(mid, Vector3(0.15, 1.1, length), _mat("metal_dark"))
		balustrade.look_at_from_position(mid, mid + (b - a), Vector3.UP)
		var neon := _neon(mid + Vector3(0, 0.56, 0), Vector3(0.08, 0.06, length), "neon_pink")
		neon.look_at_from_position(mid + Vector3(0, 0.56, 0), mid + Vector3(0, 0.56, 0) + (b - a), Vector3.UP)
	# Pied de l'escalator : caisson métallique.
	_mesh_box(bottom + Vector3(0, 0.25, 0) - forward * 0.6, Vector3(width + 0.4, 0.5, 1.2) if absf(forward.z) > 0.5 else Vector3(1.2, 0.5, width + 0.4), _mat("metal_dark"))


# --------------------------------------------------------------------------- atrium

## Atrium : fontaine à sec, bancs, plantes mortes, verrière éventrée et rayons de soleil.
func _mall_atrium() -> void:
	# Fontaine : bassin circulaire (muret de 0,8 m), fond craquelé.
	var r := 4.6
	for i in 16:
		var a := TAU * i / 16.0
		var p := Vector3(cos(a) * r, 0.4, sin(a) * r)
		var seg := _box(p, Vector3(1.9, 0.8, 0.5), _mat("stone_grey"))
		seg.rotation.y = -a + PI / 2
	_mesh_cylinder_at(Vector3(0, 0.05, 0), r - 0.2, 0.1, _mat("floor_concrete"))
	_neon_ring(Vector3(0, 0.82, 0), r * 1.45, r * 1.45, "neon_cyan", PI / 4)
	# Bancs et jardinières autour.
	for p in [Vector3(-10, 0, -10), Vector3(10, 0, 10), Vector3(-10, 0, 12), Vector3(12, 0, -10)]:
		_box(p + Vector3(0, 0.25, 0), Vector3(3.0, 0.5, 0.9), _mat("wood_warm"))
	for p in [Vector3(-13, 0, 0), Vector3(13, 0, 0), Vector3(0, 0, 13), Vector3(0, 0, -13)]:
		_box(p + Vector3(0, 0.45, 0), Vector3(2.0, 0.9, 2.0), _mat("stone_grey"))
		_mesh_box(p + Vector3(0, 1.2, 0), Vector3(1.4, 0.8, 1.4), _mat("bark"), false)
	# Verrière éventrée : poutres métalliques en grille, quelques vitres restantes.
	var a := ATRIUM
	for i in 7:
		var t := -a + i * a * 2 / 6.0
		_mesh_box(Vector3(t, ROOF + 0.2, 0), Vector3(0.35, 0.5, a * 2), _mat("metal_dark"))
		_mesh_box(Vector3(0, ROOF + 0.2, t), Vector3(a * 2, 0.5, 0.35), _mat("metal_dark"))
	for pane in [Vector2(-12, -12), Vector2(6, -12), Vector2(-12, 6), Vector2(12, 12), Vector2(0, 6)]:
		var glass := _mesh_box(Vector3(pane.x, ROOF + 0.4, pane.y), Vector3(5.8, 0.05, 5.8), _mat("glass"), false)
		glass.rotation.x = 0.06
	# Rayons de soleil poussiéreux qui tombent de la verrière (lumière orangée).
	for shaft in [Vector3(-6, 0, 4), Vector3(5, 0, -6), Vector3(-2, 0, -12)]:
		_light_shaft(shaft, 16.0, 4.5)
	# Grande enseigne au-dessus de l'atrium, côté nord.
	_mesh_box(Vector3(0, 8.6, -ATRIUM + 0.4), Vector3(16, 2.6, 0.4), _mat("lacquer_black"))
	_neon_frame(Vector3(0, 8.6, -ATRIUM + 0.65), 16.0, 2.6, "neon_pink")
	_sign("HIKARI MALL", Vector3(0, 8.95, -ATRIUM + 0.7), PI, 130, 0.018, Color(2.6, 1.0, 2.2))
	_jp_sign("ひかりモール", Vector3(0, 8.0, -ATRIUM + 0.7), PI, 80, 0.012, Color(0.6, 2.2, 2.4))


## Rayon de lumière : boîte translucide additive, inclinée dans le sens du soleil.
func _light_shaft(floor_point: Vector3, height: float, width: float) -> void:
	var shaft := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, height, width * 0.6)
	shaft.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(DUSK, 0.07)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	shaft.material_override = material
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(shaft)
	shaft.position = floor_point + Vector3(2.0, height / 2, 1.2)
	shaft.rotation_degrees = Vector3(14, -35, -12)


# --------------------------------------------------------------------------- rez-de-chaussée

## Supermarché (ouest) : rangées de rayonnages (couverts debout), caisses, gravats
## sous le plafond effondré.
func _mall_supermarket() -> void:
	for x in [-46.0, -41.0, -31.0]:
		for z_range in [[-20.0, -3.5], [3.5, 20.0]]:
			_shelf(Vector3(x, 0, (z_range[0] + z_range[1]) / 2), z_range[1] - z_range[0])
	# Rangée du milieu : un rayon renversé.
	_shelf(Vector3(-36.0, 0, -12.0), 10.0)
	var fallen := _box(Vector3(-36.0, 0.6, 12.0), Vector3(1.2, 1.2, 9.0), _mat("metal_light"))
	fallen.rotation.z = 1.2
	# Caisses enregistreuses côté galerie.
	for z in [-14.0, -4.0, 6.0, 16.0]:
		_box(Vector3(-28.0, 0.55, z), Vector3(1.4, 1.1, 3.2), _mat("metal_dark"))
		_mesh_box(Vector3(-28.0, 1.25, z - 1.0), Vector3(0.6, 0.3, 0.6), _mat("screen"), false)
	# Gravats sous le trou du plafond.
	_rubble(Vector3(-37.0, 0, -3.0))
	# Enseigne.
	_vertical_sign("スーパー", Vector3(-27.0, 3.2, -22.0), PI / 2, 1.3, 3.4, "neon_green")
	_sign("SUPER", Vector3(-38.0, 4.2, -25.7), PI, 90, 0.02, Color(0.6, 2.2, 0.9))


## Rayonnage de supermarché (2 m de haut) avec quelques produits colorés.
func _shelf(center: Vector3, length: float) -> void:
	_box(center + Vector3(0, 1.0, 0), Vector3(1.2, 2.0, length), _mat("metal_light"))
	var colors := ["container_red", "container_blue", "container_orange", "container_teal", "container_green"]
	var z := center.z - length / 2 + 0.8
	var i := 0
	while z < center.z + length / 2 - 0.6:
		for level in [0.55, 1.15, 1.75]:
			if (i + int(level * 10)) % 3 != 0:
				_mesh_box(Vector3(center.x, level, z), Vector3(1.3, 0.35, 0.7), _mat(colors[(i + int(level * 7)) % colors.size()]), false)
		z += 1.0
		i += 1


func _rubble(center: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(center.x * 31 + center.z * 7))
	for i in 7:
		var s := Vector3(rng.randf_range(0.8, 2.2), rng.randf_range(0.3, 0.9), rng.randf_range(0.8, 2.2))
		var piece := _box(center + Vector3(rng.randf_range(-2.5, 2.5), s.y / 2, rng.randf_range(-2.5, 2.5)), s, _mat("wall_concrete"))
		piece.rotation = Vector3(rng.randf_range(-0.3, 0.3), rng.randf(), rng.randf_range(-0.3, 0.3))


## Food court (est) : comptoirs néon le long du mur, tables et tabourets, tables renversées.
func _mall_food_court() -> void:
	var stalls := [["ラーメン", "neon_orange", -16.0], ["寿司", "neon_pink", -6.0],
		["BURGER", "neon_gold", 4.0], ["喫茶", "neon_cyan", 14.0]]
	for s in stalls:
		var z: float = s[2]
		_box(Vector3(46.5, 0.6, z), Vector3(3.0, 1.2, 7.0), _mat("wood_warm"))
		_mesh_box(Vector3(49.0, 2.4, z), Vector3(1.6, 4.8, 7.0), _mat("facade_dark"))
		_mesh_box(Vector3(47.0, 3.6, z), Vector3(0.3, 0.9, 6.0), _mat("lacquer_black"))
		_neon(Vector3(46.8, 4.1, z), Vector3(0.08, 0.06, 6.0), s[1])
		if s[0] == "BURGER":
			_sign(s[0], Vector3(46.8, 3.6, z), PI / 2, 80, 0.012, Color(2.2, 1.8, 0.6))
		else:
			_jp_sign(s[0], Vector3(46.8, 3.6, z), PI / 2, 80, 0.012, Color(2.2, 1.6, 1.4))
	# Tables rondes et tabourets (couverts bas), quelques-unes renversées.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for x in [30.0, 36.0, 41.0]:
		for z in [-15.0, -8.0, -1.0, 13.0, 19.0]:
			if x == 36.0 and z > 2.0 and z < 12.0:
				continue
			if rng.randf() < 0.25:
				var tipped := _box(Vector3(x, 0.6, z), Vector3(1.8, 1.2, 0.2), _mat("metal_light"))
				tipped.rotation.y = rng.randf() * PI
				continue
			_cylinder(Vector3(x, 0.38, z), 0.9, 0.08, _mat("metal_light"))
			_cylinder(Vector3(x, 0.38, z), 0.08, 0.75, _mat("metal_dark"))
			_collider_box(Vector3(x, 0.4, z), Vector3(1.6, 0.8, 1.6))
			for k in 3:
				var a := TAU * k / 3.0 + rng.randf()
				_mesh_cylinder_at(Vector3(x + cos(a) * 1.4, 0.25, z + sin(a) * 1.4), 0.3, 0.5, _mat("lacquer_red"))
	_rubble(Vector3(37.0, 0, 7.0))
	_sign("FOOD COURT", Vector3(38.0, 4.2, -25.7), PI, 90, 0.02, Color(2.2, 1.4, 0.6))


## Hall d'entrée (nord) : comptoir d'accueil, plan du centre, jardinières.
func _mall_entrance() -> void:
	_box(Vector3(0, 0.55, -36), Vector3(6.0, 1.1, 2.2), _mat("lacquer_black"))
	_neon(Vector3(0, 1.12, -34.85), Vector3(6.0, 0.06, 0.06), "neon_cyan")
	_sign("ACCUEIL", Vector3(0, 1.6, -34.8), 0.0, 60, 0.01, Color(0.6, 2.2, 2.4))
	# Plan du centre sur pied.
	_box(Vector3(-12, 1.2, -30), Vector3(2.4, 2.4, 0.3), _mat("metal_dark"))
	_mesh_box(Vector3(-12, 1.4, -29.82), Vector3(2.1, 1.6, 0.05), _mat("screen"), false)
	for p in [Vector3(-16, 0, -44), Vector3(16, 0, -44), Vector3(-8, 0, -46), Vector3(8, 0, -46)]:
		_box(p + Vector3(0, 0.45, 0), Vector3(2.0, 0.9, 2.0), _mat("stone_grey"))
		_mesh_box(p + Vector3(0, 1.3, 0), Vector3(1.2, 1.0, 1.2), _mat("foliage"), false)
	# Panneaux de sortie de secours (vert).
	_jp_sign("非常口", Vector3(0, 4.55, -H + 0.5), 0.0, 60, 0.008, Color(0.4, 2.0, 0.6))


## Quai de livraison (sud) : deux camions reculés aux portes, palettes, chariot élévateur.
func _mall_loading_bay() -> void:
	# Mur de séparation avec la galerie, deux grands passages.
	_wall_at(0.0, Vector3(-RING, 0, RING), Vector3(RING, 0, RING), LEVEL, 0.4, [[-14.0, -6.0], [6.0, 14.0]], 4.0, _mat("wall_concrete"))
	for x in [-13.0, 13.0]:
		_truck(Vector3(x, 0, 42.0))
	# Palettes chargées (caisses) et chariot élévateur.
	for c in [[-4, 34, 0], [-2.4, 34, 0], [-3.2, 34, 1], [5, 30, 0], [22, 32, 0], [-22, 30, 0], [-20.4, 30, 0]]:
		_crate(c[0], c[1], c[2])
	_box(Vector3(4, 0.8, 44), Vector3(1.4, 1.6, 2.4), _mat("paint_yellow"))
	_mesh_box(Vector3(4, 1.8, 42.6), Vector3(1.2, 2.2, 0.15), _mat("metal_dark"))
	_jp_sign("搬入口", Vector3(0, 4.4, RING - 0.25), PI, 70, 0.012, Color(2.2, 1.6, 0.5))
	# Marquage au sol.
	for x in [-13.0, 13.0]:
		_mesh_box(Vector3(x, 0.02, 44.0), Vector3(4.6, 0.02, 10.0), _mat("hazard"), false)


func _truck(rear: Vector3) -> void:
	_box(rear + Vector3(0, 1.6, -4.0), Vector3(3.0, 3.2, 8.0), _mat("container_white"))      # remorque
	_box(rear + Vector3(0, 0.5, -4.0), Vector3(2.8, 1.0, 7.6), _mat("metal_dark"))
	for z in [-6.5, -1.5]:
		for side in [-1.0, 1.0]:
			_mesh_cylinder_at(rear + Vector3(side * 1.45, 0.5, z), 0.5, 0.35, _mat("metal_dark"), Vector3(0, 0, PI / 2))


## Boutiques des quatre coins (rez-de-chaussée) : vitrines aux rideaux à moitié baissés.
func _mall_corner_shops() -> void:
	var shops := [
		# [côté x, côté z, enseigne, néon]
		[-1.0, -1.0, "電気", "neon_cyan"], [1.0, -1.0, "未来", "neon_pink"],
		[-1.0, 1.0, "東京", "neon_gold"], [1.0, 1.0, "夜", "neon_magenta"],
	]
	for s in shops:
		var sx: float = s[0]
		var sz: float = s[1]
		# Façade vers le hall / le quai (x = ±26), deux boutiques séparées à z = ±38.
		var front := sx * RING
		var z_near := sz * RING
		var z_far := sz * (H - 0.3)
		var z_lo := minf(z_near, z_far)
		var z_hi := maxf(z_near, z_far)
		var openings := [[z_lo + 4.0, z_lo + 9.0], [z_hi - 9.0, z_hi - 4.0]]
		_wall_at(0.0, Vector3(front, 0, z_lo), Vector3(front, 0, z_hi), LEVEL, 0.4, openings, 3.0, _mat("facade_warm"))
		_box(Vector3((front + sx * H) / 2, LEVEL / 2, sz * 38.0), Vector3(H - RING, LEVEL, 0.3), _mat("wall_concrete"))
		# Cloison avec le supermarché / le food court (une porte ; deux au coin des escaliers).
		var doors := [[-44.0, -40.0]] if sx < 0 else [[40.0, 44.0]]
		if (sx < 0 and sz > 0) or (sx > 0 and sz < 0):
			doors = [[-48.6, -43.6], [-36.0, -32.0]] if sx < 0 else [[32.0, 36.0], [43.6, 48.6]]
		var from_x := minf(sx * RING, sx * H)
		var to_x := maxf(sx * RING, sx * H)
		_wall_at(0.0, Vector3(from_x, 0, z_near), Vector3(to_x, 0, z_near), LEVEL, 0.4, doors, 3.0, _mat("wall_concrete"))
		# Enseigne verticale et néon sur la façade.
		_vertical_sign(s[2], Vector3(front - sx * 0.4, 3.0, sz * 32.0), -sx * PI / 2, 1.2, 2.6, s[3])
		_vertical_sign(s[2], Vector3(front - sx * 0.4, 3.0, sz * 44.0), -sx * PI / 2, 1.2, 2.6, s[3])
		# Rayonnages, comptoir et caisses à l'intérieur (couverts).
		_box(Vector3(sx * 36.0, 0.55, sz * 32.0), Vector3(3.0, 1.1, 1.2), _mat("wood_dark"))
		_box(Vector3(sx * 44.0, 1.0, sz * 46.0), Vector3(5.0, 2.0, 1.0), _mat("metal_light"))
		_crate(sx * 40.0, sz * 42.0, 0)


# --------------------------------------------------------------------------- étage

## Cinéma (étage, nord-ouest) : salle sombre éclairée par l'écran, rangées de fauteuils,
## cabine de projection (fusil laser).
func _mall_cinema() -> void:
	var y := LEVEL
	_wall_at(y, Vector3(-H, 0, -RING), Vector3(-RING, 0, -RING), ROOF - LEVEL, 0.4, [[-36.0, -31.0]], 3.0, _mat("facade_dark"))
	_wall_at(y, Vector3(-RING, 0, -H), Vector3(-RING, 0, -RING), ROOF - LEVEL, 0.4, [[-36.0, -31.0]], 3.0, _mat("facade_dark"))
	# Écran contre le mur ouest, lumineux.
	_mesh_box(Vector3(-H + 0.6, y + 3.0, -38.0), Vector3(0.1, 3.6, 16.0), _mat("screen"), false)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.5, 0.7, 1.0)
	glow.light_energy = 2.0
	glow.omni_range = 16.0
	_root.add_child(glow)
	glow.position = Vector3(-46.0, y + 3.0, -38.0)
	# Rangées de fauteuils (couverts accroupis), en gradins légers.
	# L'écran est à l'ouest : assise basse, dossier côté est, accoudoirs tous les 1,1 m.
	for i in 4:
		var x := -44.0 + i * 4.0
		_box(Vector3(x - 0.1, y + 0.25, -39.0), Vector3(0.9, 0.5, 13.0), _mat("lacquer_red"))
		_box(Vector3(x + 0.45, y + 0.6, -39.0), Vector3(0.25, 1.2, 13.0), _mat("lacquer_red"))
		for k in 13:
			_mesh_box(Vector3(x - 0.1, y + 0.6, -45.0 + k * 1.0), Vector3(0.8, 0.2, 0.12), _mat("metal_dark"), false)
	# Cabine de projection au fond (sud-est de la salle), avec une fenêtre.
	_box(Vector3(-27.5, y + 2.0, -42.0), Vector3(0.3, 4.0, 3.0), _mat("wall_concrete"))
	_box(Vector3(-29.0, y + 2.0, -43.4), Vector3(3.0, 4.0, 0.3), _mat("wall_concrete"))
	_vertical_sign("CINÉMA", Vector3(-RING + 0.4, y + 3.2, -33.5), PI / 2, 1.2, 3.2, "neon_magenta")


## Arcade néon (étage, nord-est) : bornes de jeu lumineuses en rangées.
func _mall_arcade() -> void:
	var y := LEVEL
	_wall_at(y, Vector3(RING, 0, -RING), Vector3(H, 0, -RING), ROOF - LEVEL, 0.4, [[31.0, 36.0]], 3.0, _mat("facade_dark"))
	_wall_at(y, Vector3(RING, 0, -H), Vector3(RING, 0, -RING), ROOF - LEVEL, 0.4, [[-36.0, -31.0]], 3.0, _mat("facade_dark"))
	var screens := ["neon_cyan", "neon_pink", "neon_gold", "neon_green", "neon_magenta"]
	var i := 0
	for x in [31.0, 36.0, 41.0]:
		for z in [-46.0, -42.0, -38.0, -34.0, -30.0]:
			_box(Vector3(x, y + 1.0, z), Vector3(1.1, 2.0, 0.9), _mat("lacquer_black"))
			_neon(Vector3(x - 0.56, y + 1.35, z), Vector3(0.04, 0.6, 0.7), screens[i % screens.size()])
			i += 1
	for c in [Color(1.0, 0.35, 0.8), Color(0.3, 0.9, 1.0)]:
		var light := OmniLight3D.new()
		light.light_color = c
		light.light_energy = 1.6
		light.omni_range = 12.0
		_root.add_child(light)
		light.position = Vector3(36.0 if c.r > 0.5 else 42.0, y + 3.5, -40.0 if c.r > 0.5 else -32.0)
	_vertical_sign("ゲーム", Vector3(RING - 0.4, y + 3.2, -38.0), -PI / 2, 1.2, 3.2, "neon_cyan")


## Reste de l'étage : boutiques au nord, réserve au sud, salon à l'est, balcon à l'ouest.
func _mall_upper_floor() -> void:
	var y := LEVEL
	# Nord : rangée de boutiques le long du mur (cloisons et rideaux mi-hauts).
	for x in [-18.0, -10.0, -2.0, 6.0, 14.0, 22.0]:
		_box(Vector3(x, y + 2.0, -46.0), Vector3(0.3, 4.0, 8.0), _mat("wall_concrete"))
	for x in [-14.0, -6.0, 2.0, 10.0, 18.0]:
		_mesh_box(Vector3(x, y + 3.2, -42.1), Vector3(7.6, 1.6, 0.12), _mat("shutter_metal"))
		_box(Vector3(x - 2.0, y + 0.5, -44.5), Vector3(2.4, 1.0, 1.0), _mat("wood_dark"))
	# Sud : réserve avec rayonnages hauts (3 m) et caisses.
	for x in [-14.0, -6.0, 6.0, 14.0]:
		_box(Vector3(x, y + 1.5, 40.0), Vector3(1.2, 3.0, 10.0), _mat("metal_light"))
	for c in [[-10, 46, 0], [-8.4, 46, 0], [10, 34, 0], [0, 40, 0]]:
		_box(Vector3(c[0], y + 0.8, c[1]), Vector3(1.6, 1.6, 1.6), _mat("wood_warm"))
	# Coins sud : boutiques (cloisons).
	for sx in [-1.0, 1.0]:
		_box(Vector3(sx * 38.0, y + 2.0, 40.0), Vector3(0.3, 4.0, 12.0), _mat("wall_concrete"))
		_box(Vector3(sx * 32.0, y + 0.55, 46.0), Vector3(3.0, 1.1, 1.2), _mat("wood_dark"))
	# Est : salon avec canapés (couverts bas) au-dessus du food court.
	for p in [Vector3(30, 0, -14), Vector3(44, 0, -4), Vector3(30, 0, 16), Vector3(44, 0, 20)]:
		_box(p + Vector3(0, y + 0.45, 0), Vector3(3.0, 0.9, 1.2), _mat("cloth_indigo"))
	# Ouest : balcon au-dessus du supermarché, jardinières (couverts).
	for p in [Vector3(-30, 0, -16), Vector3(-44, 0, 6), Vector3(-30, 0, 18)]:
		_box(p + Vector3(0, y + 0.5, 0), Vector3(2.4, 1.0, 2.4), _mat("stone_grey"))
		_mesh_box(p + Vector3(0, y + 1.4, 0), Vector3(1.8, 0.9, 1.8), _mat("foliage"), false)


## Mur droit de `from` à `to` (x / z), posé à la hauteur `base_y`, avec des ouvertures
## [début, fin] (passage de `door_height`, linteau au-dessus, liseré néon).
func _wall_at(base_y: float, from: Vector3, to: Vector3, height: float, thickness: float,
		openings: Array, door_height: float, material: Material) -> void:
	var along_x := absf(to.x - from.x) > absf(to.z - from.z)
	var a := from.x if along_x else from.z
	var b := to.x if along_x else to.z
	var fixed := from.z if along_x else from.x
	var segments := []
	var cursor := a
	for o in openings:
		segments.append([cursor, o[0], 0.0, height])
		segments.append([o[0], o[1], door_height, height])
		var mid: float = (o[0] + o[1]) / 2.0
		var neon_size := Vector3(o[1] - o[0], 0.08, thickness + 0.1) if along_x else Vector3(thickness + 0.1, 0.08, o[1] - o[0])
		_neon(Vector3(mid, base_y + door_height - 0.04, fixed) if along_x else Vector3(fixed, base_y + door_height - 0.04, mid), neon_size, "neon_cyan")
		cursor = o[1]
	segments.append([cursor, b, 0.0, height])
	for seg in segments:
		var length: float = seg[1] - seg[0]
		if length <= 0.01:
			continue
		var mid: float = (seg[0] + seg[1]) / 2.0
		var y0: float = base_y + seg[2]
		var y1: float = base_y + seg[3]
		var center := Vector3(mid, (y0 + y1) / 2, fixed) if along_x else Vector3(fixed, (y0 + y1) / 2, mid)
		var size := Vector3(length, y1 - y0, thickness) if along_x else Vector3(thickness, y1 - y0, length)
		_box(center, size, material)


# --------------------------------------------------------------------------- lumières

## Lumières intérieures : lampes chaudes des boutiques, éclairages de secours, et
## quelques néons qui grésillent (clignotent au hasard).
func _mall_lights() -> void:
	var warm := Color(1.0, 0.72, 0.45)
	var spots := [
		[Vector3(-38, 3.6, 0), warm, 1.4, 16.0], [Vector3(38, 3.6, 0), warm, 1.4, 16.0],
		[Vector3(0, 3.8, -38), warm, 1.2, 14.0], [Vector3(0, 3.8, 38), Color(1.0, 0.5, 0.3), 1.2, 14.0],
		[Vector3(-38, 3.4, -38), NEON_CYAN, 1.0, 10.0], [Vector3(38, 3.4, -38), NEON_PINK, 1.0, 10.0],
		[Vector3(-38, 3.4, 38), warm, 1.0, 10.0], [Vector3(38, 3.4, 38), NEON_PINK, 1.0, 10.0],
		[Vector3(0, 8.4, -40), warm, 1.0, 14.0], [Vector3(0, 8.4, 40), warm, 0.9, 14.0],
		[Vector3(-38, 8.4, 8), DUSK, 1.0, 14.0], [Vector3(38, 8.4, 4), warm, 1.0, 14.0],
		[Vector3(-38, 8.4, 40), warm, 0.9, 12.0], [Vector3(38, 8.4, 40), NEON_CYAN, 0.9, 12.0],
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for i in spots.size():
		var s: Array = spots[i]
		var light := OmniLight3D.new()
		light.light_color = s[1]
		light.light_energy = s[2]
		light.omni_range = s[3]
		_root.add_child(light)
		light.position = s[0]
		if i % 4 == 1 and not Engine.is_editor_hint():
			_flicker(light, rng)
	# Bandeaux néon sous le plafond de la galerie (nord et sud).
	for z in [-RING + 0.3, RING - 0.3]:
		_neon(Vector3(0, LEVEL - SLAB - 0.1, z), Vector3(RING * 2, 0.08, 0.08), "neon_pink" if z < 0 else "neon_cyan")


## Néon qui grésille : la lumière s'éteint par instants, au hasard.
func _flicker(light: OmniLight3D, rng: RandomNumberGenerator) -> void:
	var base := light.light_energy
	var tween := light.create_tween().set_loops()
	tween.tween_interval(rng.randf_range(1.5, 4.0))
	tween.tween_property(light, "light_energy", 0.1, 0.05)
	tween.tween_property(light, "light_energy", base, 0.05)
	tween.tween_property(light, "light_energy", 0.2, 0.08)
	tween.tween_property(light, "light_energy", base, 0.06)


# --------------------------------------------------------------------------- dehors

## Ville au crépuscule autour du centre commercial (décor sans collision).
func _mall_city() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	for i in 22:
		var angle := TAU * i / 22.0 + rng.randf_range(-0.06, 0.06)
		var distance := rng.randf_range(80, 120)
		var pos := Vector3(cos(angle) * distance, 0, sin(angle) * distance)
		var w := rng.randf_range(14, 26)
		var h := rng.randf_range(18, 60)
		var building := _mesh_box(pos + Vector3(0, h / 2 - 0.5, 0), Vector3(w, h, w * rng.randf_range(0.7, 1.2)),
			_mat(["facade", "facade_warm", "facade_dark"][i % 3]), true)
		building.rotation.y = -angle
		if i % 3 == 0:
			_neon_ring(pos + Vector3(0, h - 0.3, 0), w, w, "neon_pink" if i % 2 == 0 else "neon_cyan", -angle)
