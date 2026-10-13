extends Node3D
## Scène de jeu. Deux modes (choisis dans le menu, voir GameState.mode) :
##
##   "deathmatch"  Match à mort chacun pour soi : le joueur + des bots, chronomètre,
##                 fil des éliminations, tableau des scores (Tab), écran de fin.
##                 Le résultat est envoyé au back (équivalent de match.finished).
##   "training"    Entraînement : le joueur seul avec les mannequins, sans limite de temps.
##
## La map est une scène à part (scenes/maps/) : le futur serveur de jeu pourra
## charger exactement la même. Les bots utilisent un maillage de navigation calculé
## au chargement à partir des collisions de la map.

const RESPAWN_DELAY := 3.0
const MapScene := preload("res://scenes/maps/arena.tscn")
const PlayerScene := preload("res://scenes/player.tscn")
const TargetScene := preload("res://scenes/target_dummy.tscn")
const MatchUIScript := preload("res://scripts/ui/match_ui.gd")

const BOT_NAMES := ["NeoByte", "Gl1tch", "V0LT", "Cipher", "Kairo", "Nova", "Raven", "Hexa", "ZeroDay", "Proxy"]
const STREAK_BANNERS := {2: "DOUBLE ÉLIMINATION", 3: "TRIPLE ÉLIMINATION", 5: "SÉRIE x5 · INARRÊTABLE", 8: "SÉRIE x8 · LÉGENDAIRE"}

@onready var hud: CanvasLayer = $HUD

var map: ArenaMap
var player: CharacterBody3D             # joueur local
var players: Array = []                 # tous les joueurs (local + bots)
var roam_points: Array = []             # points de patrouille des bots
var nav_map: RID

var _ui: CanvasLayer
var _mode := "deathmatch"
var _time_left := 0.0
var _running := false
var _respawns := {}                     # joueur -> temps restant avant réapparition
var _match_time := 0.0
var _ping := randi_range(7, 14)          # ping simulé du joueur local


func _ready() -> void:
	_mode = GameState.mode
	map = MapScene.instantiate()
	add_child(map)
	_ui = MatchUIScript.new()
	add_child(_ui)
	_ui.play_again.connect(func() -> void: get_tree().reload_current_scene())
	_ui.back_to_menu.connect(_go_to_menu)

	player = _spawn_player(GameState.selected_class, Backend.username(), true)
	hud.bind(player)

	if _mode == "training":
		_spawn_targets()
		_ui.hide_timer()
	else:
		_bake_navigation()
		for i in GameState.bot_count:
			var cls: ClassData = GameState.CLASSES[randi() % GameState.CLASSES.size()]
			_spawn_player(cls, BOT_NAMES[i % BOT_NAMES.size()], false)
		_time_left = GameState.match_duration
		_running = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	# Réapparitions.
	for p in _respawns.keys():
		_respawns[p] -= delta
		if p == player:
			hud.set_respawn_countdown(_respawns[p])
		if _respawns[p] <= 0.0:
			_respawns.erase(p)
			if _running or _mode == "training":
				_respawn(p)

	if _mode == "deathmatch":
		if _running:
			_time_left -= delta
			_match_time += delta
			var leader: Dictionary = _scoreboard_rows()[0]
			_ui.set_time(_time_left, leader.name, leader.kills)
			if _time_left <= 0.0:
				_end_match()
		_ui.show_scoreboard(_scoreboard_rows(), _running and Input.is_action_pressed("scoreboard"), _server_subtitle())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("back_to_menu"):
		_go_to_menu()
	# Si la souris a été libérée (Alt+Tab…), un clic la recapture.
	elif event is InputEventMouseButton and event.pressed and (_running or _mode == "training") \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _go_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# ---------------------------------------------------------------- Joueurs

func _spawn_player(cls: ClassData, display_name: String, local: bool) -> CharacterBody3D:
	var p: CharacterBody3D = PlayerScene.instantiate()
	p.class_data = cls
	p.player_name = display_name
	p.is_local = local
	p.name = display_name
	if not local:
		var brain := BotBrain.new()
		brain.game = self
		brain.skill = randf_range(0.35, 0.75)
		p.brain = brain
	add_child(p)
	p.global_transform = _best_spawn(p)
	p.died.connect(_on_player_died.bind(p))
	p.add_to_group("players")   # utilisé par les caméras et capteurs de la map
	if not local:
		_add_name_tag(p)
	players.append(p)
	return p


## Nom au-dessus des bots (masqué par les murs, comme le personnage).
func _add_name_tag(p: CharacterBody3D) -> void:
	var tag := Label3D.new()
	tag.text = p.player_name
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.pixel_size = 0.004
	tag.font_size = 44
	tag.outline_size = 10
	tag.modulate = p.class_data.color.lightened(0.35)
	tag.font = UiTheme.FONT_BOLD
	tag.position.y = 2.15
	tag.name = "NameTag"
	p.add_child(tag)


## Point d'apparition le plus éloigné des adversaires vivants (un peu de hasard).
func _best_spawn(for_player: Node) -> Transform3D:
	var spawns := map.get_spawn_transforms()
	var scored := []
	for t in spawns:
		var nearest := INF
		for other in players:
			if other != for_player and other.alive:
				nearest = minf(nearest, t.origin.distance_to(other.global_position))
		scored.append([nearest + randf() * 8.0, t])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	return scored[0][1]


func _respawn(p: CharacterBody3D) -> void:
	var t := _best_spawn(p)
	p.respawn(t.origin, t.basis.get_euler().y)
	if p.brain:
		p.brain.reset()
	if p.has_node("NameTag"):
		p.get_node("NameTag").visible = true
	if p == player:
		hud.hide_death()


func _on_player_died(killer: Node, victim: CharacterBody3D) -> void:
	_respawns[victim] = RESPAWN_DELAY
	if victim.has_node("NameTag"):
		victim.get_node("NameTag").visible = false
	var killer_name := "Arène"
	var weapon_name := "—"
	if killer and killer != victim and killer in players:
		killer.add_kill()
		killer_name = killer.player_name
		weapon_name = killer.class_data.weapon.display_name
		if killer == player:
			var banner: String = STREAK_BANNERS.get(killer.streak, "ÉLIMINATION")
			_ui.show_banner("%s  +100" % banner)
	elif killer and killer.get("player_name") == null and killer != victim:
		killer_name = str(killer.name)
	if _mode == "deathmatch":
		_ui.add_kill(killer_name, victim.player_name, weapon_name, killer == player, victim == player)
	if victim == player:
		hud.show_death(killer_name if killer_name != "Arène" else "")


# ---------------------------------------------------------------- Partie

func _scoreboard_rows() -> Array:
	var rows := []
	for p in players:
		rows.append({
			"name": p.player_name, "cls": p.class_data.display_name, "class_color": p.class_data.color.lightened(0.3),
			"kills": p.kills, "deaths": p.deaths, "best_streak": p.best_streak,
			"ping": "%d ms" % _ping if p == player else "BOT", "local": p == player,
		})
	rows.sort_custom(func(a, b): return a.kills > b.kills or (a.kills == b.kills and a.deaths < b.deaths))
	return rows


func _server_subtitle() -> String:
	var server: Dictionary = Backend.current_server
	return "%s · MAP ARENA" % server.get("name", "Serveur local")


func _end_match() -> void:
	_running = false
	_time_left = 0.0
	_ui.set_time(0.0, "", 0)
	for p in players:
		p.set_physics_process(false)
		p.velocity = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var rows := _scoreboard_rows()
	var rank := 1
	for i in rows.size():
		if rows[i].local:
			rank = i + 1
	_ui.show_end_screen(rows, rank, "%s · %d joueurs · durée %d:%02d" % [_server_subtitle(), rows.size(), int(_match_time) / 60, int(_match_time) % 60])
	Backend.report_match({
		"kills": player.kills, "deaths": player.deaths, "won": rank == 1, "duration": _match_time,
		"class": player.class_data.display_name, "best_streak": player.best_streak,
	})


# ---------------------------------------------------------------- Entraînement

func _spawn_targets() -> void:
	var index := 0
	for point in ArenaMap.TARGET_POINTS:
		var target := TargetScene.instantiate()
		target.crouched = index % 3 == 2   # un mannequin sur trois est accroupi
		add_child(target)
		target.global_position = point
		target.rotation.y = randf() * TAU
		index += 1


# ---------------------------------------------------------------- Navigation des bots

## Calcule le maillage de navigation (zones où l'on peut marcher) à partir des
## collisions de la map, puis l'enregistre auprès du serveur de navigation.
func _bake_navigation() -> void:
	var navmesh := NavigationMesh.new()
	navmesh.agent_radius = 0.5
	navmesh.agent_height = 1.75
	navmesh.agent_max_climb = 0.25
	navmesh.agent_max_slope = 46.0
	navmesh.cell_size = 0.25
	navmesh.cell_height = 0.25
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navmesh.filter_baking_aabb = AABB(Vector3(-61, -1, -61), Vector3(122, 16, 122))
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(navmesh, source, map)
	NavigationServer3D.bake_from_source_geometry_data(navmesh, source)
	var region := NavigationRegion3D.new()
	region.navigation_mesh = navmesh
	add_child(region)
	nav_map = get_world_3d().navigation_map

	roam_points = []
	for p in ArenaMap.SPAWN_POINTS:
		roam_points.append(p)
	for p in ArenaMap.TARGET_POINTS:
		roam_points.append(p)
