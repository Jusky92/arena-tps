extends Node3D
## Scène de jeu. Deux modes (choisis dans le menu, voir GameState.mode) :
##
##   "deathmatch"  Match à mort chacun pour soi : le joueur + des bots, chronomètre,
##                 fil des éliminations, tableau des scores (Tab), écran de fin.
##                 Hors ligne, rien n'est envoyé au back : seules les parties sur
##                 serveur dédié comptent dans les statistiques.
##   "training"    Entraînement : le joueur seul avec les mannequins, sans limite de temps.
##
## Le match à mort se joue hors ligne (contre des bots) ou EN LIGNE sur un serveur
## dédié : voir scripts/net/net.gd. En ligne, chaque client simule son propre
## joueur ; le serveur (scripts/server/server_game.gd) fait jouer les bots et
## arbitre la vie, les éliminations, le chronomètre et les réapparitions.
##
## Échap ouvre le menu pause du joueur local : la partie continue pour les autres
## (bots, futurs joueurs en ligne) ; seul le joueur local perd le contrôle de son
## personnage. Depuis ce menu, il peut changer de classe pour sa prochaine apparition.
##
## Chaque apparition donne quelques secondes de protection (voir player.gd).
##
## La map est une scène à part (scenes/maps/) : le serveur dédié charge exactement
## la même. Hors ligne, les bots utilisent un maillage de navigation calculé au
## chargement à partir des collisions de la map (MatchRules.bake_navigation).

const LOBBY := "res://scenes/lobby.tscn"
const PlayerScene := preload("res://scenes/player.tscn")
const TargetScene := preload("res://scenes/target_dummy.tscn")
const MatchUIScene := preload("res://scenes/ui/match_ui.tscn")
const PauseMenuScript := preload("res://scripts/ui/pause_menu.gd")

const BOT_NAMES := ["NeoByte", "Gl1tch", "V0LT", "Cipher", "Kairo", "Nova", "Raven", "Hexa", "ZeroDay", "Proxy",
	"Synth", "Kitsune", "Ronin", "Pixel", "Onyx"]
const STREAK_BANNERS := {2: "DOUBLE ÉLIMINATION", 3: "TRIPLE ÉLIMINATION", 5: "SÉRIE x5 · INARRÊTABLE", 8: "SÉRIE x8 · LÉGENDAIRE"}

@onready var hud: CanvasLayer = $HUD

var map: Node3D                         # ArenaMap ou une map qui en hérite (voir MapCatalog)
var player: CharacterBody3D             # joueur local
var players: Array = []                 # tous les joueurs (local + bots)
var roam_points: Array = []             # points de patrouille des bots
var nav_map: RID

var _ui: CanvasLayer
var _pause: CanvasLayer
var _mode := "deathmatch"
var _time_left := 0.0
var _running := false
var _respawns := {}                     # joueur -> temps restant avant réapparition
var _match_time := 0.0
var _ping := randi_range(7, 14)          # ping simulé du joueur local
var _pending_class: ClassData = null    # spécialiste choisi pour la prochaine apparition
var _pending_loadout := false           # classe (équipement) changée pour la prochaine apparition
var _net_projectiles := {}              # en ligne : identifiant -> projectile affiché
## Bonus de la map : qui fait foi hors ligne, affichage seulement en ligne.
var pickups: PickupDirector
var _online := false                    # partie sur le serveur dédié (voir Net)
var _net_nodes := {}                    # identifiant réseau -> personnage


func _ready() -> void:
	_mode = GameState.mode
	var map_id: String = Net.settings.get("map", MapCatalog.DEFAULT_ID) if Net.online and Net.in_match else GameState.map_id
	map = MapCatalog.scene_of(map_id).instantiate()
	add_child(map)
	_ui = MatchUIScene.instantiate()
	add_child(_ui)
	_ui.play_again.connect(_play_again)
	_ui.back_to_menu.connect(_go_to_menu)

	_pause = PauseMenuScript.new()
	add_child(_pause)
	_pause.resumed.connect(_close_pause)
	_pause.quit_requested.connect(_go_to_menu)
	_pause.class_selected.connect(_on_class_selected)
	_pause.loadout_selected.connect(_on_loadout_selected)
	add_to_group("projectile_host")
	_start_ambience()

	_online = Net.online and Net.in_match and _mode == "deathmatch"
	pickups = PickupDirector.new()
	pickups.name = "Pickups"
	add_child(pickups)
	pickups.setup(map.pickup_points(), not _online)
	if _online:
		pickups.apply_snapshot(Net.pickup_states)
	else:
		pickups.players_provider = func() -> Array: return players
		pickups.picked.connect(_on_pickup_offline)
	if _online:
		_start_online_match()
	else:
		player = _spawn_player(GameState.selected_class, Backend.username(), true)
		_bind_player(player)
		if _mode == "training":
			_spawn_targets()
			_ui.hide_timer()
		else:
			nav_map = MatchRules.bake_navigation(self, map)
			roam_points = MatchRules.roam_points(map)
			for point in map.pickup_points():
				var p: Vector3 = point[1]
				roam_points.append(Vector3(p.x, 0, p.z))      # les bots passent par les bonus
			for i in GameState.bot_count:
				var cls: ClassData = GameState.CLASSES[randi() % GameState.CLASSES.size()]
				_spawn_player(cls, BOT_NAMES[i % BOT_NAMES.size()], false, WeaponCatalog.random_loadout())
			_time_left = GameState.match_duration
			_running = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if _online:
		_publish_states()
	# Réapparitions. En ligne, c'est le serveur qui décide : le compte à rebours
	# ne sert qu'à l'affichage, la réapparition arrive par le réseau.
	for p in _respawns.keys():
		_respawns[p] -= delta
		if p == player:
			hud.set_respawn_countdown(_respawns[p])
		if _respawns[p] <= 0.0:
			_respawns.erase(p)
			if not _online and (_running or _mode == "training"):
				_respawn(p)

	if _mode == "deathmatch":
		if _running:
			# En ligne, le chronomètre ne sert qu'à l'affichage : c'est le serveur
			# qui annonce la fin de la partie.
			_time_left = maxf(_time_left - delta, 0.0)
			_match_time += delta
			var rows := _scoreboard_rows()
			if not rows.is_empty():           # vide un instant après une déconnexion
				_ui.set_time(_time_left, rows[0].name, rows[0].kills)
			if _time_left <= 0.0 and not _online:
				_finish_match()
		var show_board: bool = _running and not _pause.is_open() and Input.is_action_pressed("scoreboard")
		_ui.show_scoreboard(_scoreboard_rows(), show_board, _server_subtitle())

	if _pause.is_open():
		_pause.set_info(_pause_info())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if _pause.is_open():
			_pause.back()
		elif _running or _mode == "training":
			_open_pause()
		get_viewport().set_input_as_handled()
	# Si la souris a été libérée (Alt+Tab…), un clic la recapture.
	elif event is InputEventMouseButton and event.pressed and not _pause.is_open() \
			and (_running or _mode == "training") and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## En ligne, on reste connecté au serveur et on retourne au salon.
## Si le serveur a déjà fermé la connexion (fin d'une partie de groupe), retour au menu.
func _play_again() -> void:
	if _online:
		get_tree().change_scene_to_file(LOBBY if Net.online else "res://scenes/main_menu.tscn")
	else:
		get_tree().reload_current_scene()


func _go_to_menu() -> void:
	if Net.online:
		Net.leave()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# ---------------------------------------------------------------- Menu pause

## Pause locale : le joueur lâche les commandes, le reste de la partie continue.
func _open_pause() -> void:
	player.input_enabled = false
	hud.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.ui("ui_open")
	_pause.open(player.class_data, _pending_class, _pending_loadout)
	_pause.set_info(_pause_info())


func _close_pause() -> void:
	_pause.close()
	hud.visible = true
	player.input_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Sfx.ui("ui_close")


func _pause_info() -> String:
	var lines := []
	if _mode == "deathmatch":
		lines.append("%s · %d joueurs" % [_server_subtitle(), players.size()])
		lines.append("Temps restant : %d:%02d" % [int(_time_left) / 60, int(_time_left) % 60])
		lines.append("Ton score : %d élim. · %d morts" % [player.kills, player.deaths])
	else:
		lines.append("Entraînement · NEO-EDO")
	if not player.alive:
		lines.append("Réapparition en cours…")
	return "\n".join(lines)


## Spécialiste choisi dans le menu pause : appliqué à la prochaine apparition.
func _on_class_selected(cls: ClassData) -> void:
	GameState.select_specialist(cls)      # gardé aussi pour les prochaines parties
	_pending_class = null if cls == player.class_data else cls
	_announce_next_spawn()


## Classe (équipement) choisie dans le menu pause : appliquée à la prochaine apparition.
func _on_loadout_selected(index: int) -> void:
	GameState.select_loadout(index)
	var l := GameState.current_loadout()
	_pending_loadout = player.weapons[0].data.id != l.primary or player.weapons[1].data.id != l.secondary
	_announce_next_spawn()


## Prévient le serveur et affiche dans le HUD ce qui changera à la prochaine apparition.
func _announce_next_spawn() -> void:
	var cls: ClassData = _pending_class if _pending_class else player.class_data
	var l := GameState.current_loadout()
	if _online:
		Net.set_loadout(cls.resource_path, l.primary, l.secondary)
	if _pending_class or _pending_loadout:
		hud.set_next_class("%s · %s" % [cls.display_name, l.name], cls.color)
	else:
		hud.set_next_class("")


## Remplace le joueur local par un nouveau personnage de la classe choisie,
## en conservant son score. Appelé au moment de la réapparition.
func _replace_local_player(cls: ClassData) -> void:
	var old := player
	players.erase(old)
	old.remove_from_group("players")
	var fresh := _spawn_player(cls, old.player_name, true)
	fresh.kills = old.kills
	fresh.deaths = old.deaths
	fresh.best_streak = old.best_streak
	fresh.input_enabled = not _pause.is_open()
	player = fresh
	_bind_player(fresh)
	hud.hide_death()
	old.queue_free()
	_pending_class = null
	_pending_loadout = false
	hud.set_next_class("")
	Sfx.play("spawn", -8.0)


# ---------------------------------------------------------------- Partie en ligne
#
# Répartition des rôles (voir scripts/net/net.gd) :
#   - chaque client simule SON joueur et envoie son état 20 fois par seconde ;
#   - le serveur fait jouer les bots et rediffuse l'état de tout le monde ;
#   - le serveur arbitre : vie, éliminations, score, chronomètre, réapparitions.

## Crée la partie en réseau à partir de la liste de joueurs reçue du serveur.
func _start_online_match() -> void:
	for id in Net.players:
		_spawn_net_player(id)
	player = _net_nodes.get(Net.my_id())
	if player:
		player.camera.make_current()   # toujours MA caméra, quel que soit l'ordre d'apparition
		_bind_player(player)
	# Si on rejoint une partie en cours, le serveur donne le temps restant.
	_time_left = Net.match_time_left
	_running = true

	Net.remote_states.connect(_on_remote_states)
	Net.player_died.connect(_on_net_death)
	Net.player_respawned.connect(_on_net_respawn)
	Net.health_updated.connect(_on_net_health)
	Net.hit_landed.connect(_on_net_hit)
	Net.projectile_spawned.connect(_on_net_projectile)
	Net.projectile_exploded.connect(_on_net_explosion)
	Net.effect_received.connect(_on_net_effect)
	Net.pickup_changed.connect(func(pad_id: int, available: bool) -> void: pickups.set_available(pad_id, available))
	Net.pickups_snapshot.connect(func(states: Dictionary) -> void: pickups.apply_snapshot(states))
	Net.special_given.connect(_on_net_special)
	Net.aura_started.connect(_on_net_aura)
	Net.match_over.connect(_on_net_match_over)
	Net.remote_spawned.connect(_on_net_joined)
	Net.remote_left.connect(_on_net_left)
	Net.disconnected.connect(_on_net_disconnected)


## Crée le personnage d'un joueur (ou d'un bot) de la partie en réseau.
## Seul MON joueur est simulé ici : les autres, bots compris, sont des pantins
## qui suivent l'état diffusé par le serveur.
func _spawn_net_player(id: int) -> CharacterBody3D:
	var info: Dictionary = Net.players.get(id, {})
	var cls: ClassData = load(info.get("class_id", GameState.CLASSES[0].resource_path))
	var is_me := id == Net.my_id()
	var p: CharacterBody3D = PlayerScene.instantiate()
	p.class_data = cls
	p.loadout = Net.loadout_of(id)
	p.player_name = info.get("name", "Joueur")
	p.is_local = is_me
	p.peer_id = id
	p.is_remote = not is_me
	p.name = "Net_%d" % id
	add_child(p)
	p.global_transform = MatchRules.best_spawn(map, players, p)
	p.died.connect(_on_player_died.bind(p))
	p.add_to_group("players")
	p.start_spawn_protection()
	if not is_me:
		_add_name_tag(p)
	players.append(p)
	_net_nodes[id] = p
	return p


## Envoie l'état de mon joueur au serveur.
func _publish_states() -> void:
	var id := Net.my_id()
	var node = _net_nodes.get(id)
	if is_instance_valid(node):
		Net.publish_state({id: node.net_state()})


## États diffusés par le serveur.
func _on_remote_states(_sender_id: int, states: Dictionary) -> void:
	for id in states:
		var node = _net_nodes.get(id)
		if is_instance_valid(node) and node.is_remote:
			node.apply_net_state(states[id])


## Nouvelle valeur de vie reçue (diffusée par le serveur).
func _on_net_health(peer_id: int, health: int, max_health: int) -> void:
	var node = _net_nodes.get(peer_id)
	if not is_instance_valid(node):
		return
	node.health = health
	node.rig.flash()
	node.health_changed.emit(health, max_health)


## Tir validé par le serveur, reçu seulement par la cible et le tireur : la cible
## affiche d'où vient le tir (le flash rouge et l'indicateur de provenance).
func _on_net_hit(target_id: int, shooter_id: int, damage: int, _headshot: bool) -> void:
	if target_id != Net.my_id() or not is_instance_valid(player):
		return
	var shooter = _net_nodes.get(shooter_id)
	player.damaged.emit(damage, shooter.global_position if is_instance_valid(shooter) else Vector3.INF)


## Élimination annoncée par le serveur : animation, fil des éliminations, écran de mort.
func _on_net_death(victim_id: int, killer_id: int, weapon: String, headshot: bool) -> void:
	var victim = _net_nodes.get(victim_id)
	if not is_instance_valid(victim):
		return
	if victim.alive:
		victim.net_die()
	var killer_name := Net.player_name_of(killer_id) if killer_id != victim_id else "Arène"
	_ui.add_kill(killer_name, victim.player_name, weapon, killer_id == Net.my_id(), victim_id == Net.my_id(), headshot)
	if killer_id == Net.my_id() and killer_id != victim_id:
		var streak: int = Net.players.get(killer_id, {}).get("kills", 1)
		_ui.show_banner(_kill_banner(streak, headshot))
		Sfx.play("kill", -2.0)
		if headshot:
			Sfx.play("headshot", -3.0)
	if victim_id == Net.my_id():
		hud.show_death(killer_name if killer_name != "Arène" else "")
		# Compte à rebours affiché ; la réapparition viendra du serveur.
		_respawns[victim] = MatchRules.RESPAWN_DELAY
	if victim.has_node("NameTag"):
		victim.get_node("NameTag").visible = false


## Réapparition annoncée par le serveur (pour tout le monde).
func _on_net_respawn(peer_id: int, position: Vector3, yaw: float, class_id: String, loadout: Dictionary) -> void:
	var node = _net_nodes.get(peer_id)
	if not is_instance_valid(node):
		return
	# Autre spécialiste ou autre classe : on remplace le personnage en gardant le score.
	if MatchRules.needs_rebuild(node, class_id, loadout):
		node = _replace_net_player(peer_id, class_id)
	node.respawn(position, yaw)
	node.teleport(position, yaw)
	if node.brain:
		node.brain.reset()
	if node.has_node("NameTag"):
		node.get_node("NameTag").visible = true
	if peer_id == Net.my_id():
		hud.hide_death()
		_pending_class = null
		_pending_loadout = false
		hud.set_next_class("")


## Remplace le personnage d'un joueur par un autre de classe différente.
func _replace_net_player(peer_id: int, class_id: String) -> CharacterBody3D:
	var old = _net_nodes.get(peer_id)
	if is_instance_valid(old):
		players.erase(old)
		old.remove_from_group("players")
		old.queue_free()
	Net.players[peer_id]["class_id"] = class_id
	var fresh := _spawn_net_player(peer_id)
	if peer_id == Net.my_id():
		player = fresh
		fresh.input_enabled = not _pause.is_open()
		_bind_player(fresh)
	return fresh


## Un joueur arrive en cours de partie.
func _on_net_joined(peer_id: int, _info: Dictionary) -> void:
	if _net_nodes.has(peer_id):
		return
	_spawn_net_player(peer_id)
	_ui.show_banner("%s a rejoint la partie" % Net.player_name_of(peer_id), UiTheme.MUTED)


## Un joueur s'est déconnecté (ou un bot lui a cédé sa place) : on retire son personnage.
func _on_net_left(peer_id: int) -> void:
	var node = _net_nodes.get(peer_id)
	if not is_instance_valid(node):
		_net_nodes.erase(peer_id)
		return
	players.erase(node)
	_respawns.erase(node)
	_ui.show_banner("%s a quitté la partie" % node.player_name, UiTheme.MUTED)
	node.queue_free()
	_net_nodes.erase(peer_id)


## Fin de partie annoncée par le serveur.
func _on_net_match_over(_rows: Array) -> void:
	if _running:
		_finish_match()


## Tableau des scores en ligne : les compteurs tenus par le serveur font foi.
func _net_scoreboard_rows() -> Array:
	var rows := []
	for entry in Net.sorted_players():
		var cls: ClassData = load(entry.class_id)
		var is_bot: bool = Net.is_bot(entry.id)
		rows.append({
			"name": entry.name, "cls": cls.display_name, "class_color": cls.color.lightened(0.3),
			"kills": entry.kills, "deaths": entry.deaths,
			"best_streak": 0,
			"ping": "BOT" if is_bot else ("%d ms" % _ping if entry.id == Net.my_id() else "—"),
			"local": entry.id == Net.my_id(),
		})
	return rows


## Le serveur a fermé la connexion, ou elle est tombée.
func _on_net_disconnected(reason: String) -> void:
	_running = false
	_ui.show_banner(reason, UiTheme.RED)
	await get_tree().create_timer(2.5).timeout
	_go_to_menu()


# ---------------------------------------------------------------- Joueurs

## `loadout` vide pour le joueur local : il prend la classe choisie dans le menu.
func _spawn_player(cls: ClassData, display_name: String, local: bool, loadout := {}) -> CharacterBody3D:
	var p: CharacterBody3D = PlayerScene.instantiate()
	p.class_data = cls
	p.loadout = loadout
	p.player_name = display_name
	p.is_local = local
	p.name = display_name   # Godot ajoute un suffixe si le nom est déjà pris
	if not local:
		var brain := BotBrain.new()
		brain.game = self
		brain.skill = randf_range(0.35, 0.75)
		p.brain = brain
	add_child(p)
	p.global_transform = MatchRules.best_spawn(map, players, p)
	p.died.connect(_on_player_died.bind(p))
	p.add_to_group("players")   # utilisé par les caméras et capteurs de la map
	p.start_spawn_protection()
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


func _respawn(p: CharacterBody3D) -> void:
	if p == player and (_pending_class or _pending_loadout):
		_replace_local_player(_pending_class if _pending_class else player.class_data)
		return
	var t := MatchRules.best_spawn(map, players, p)
	p.respawn(t.origin, t.basis.get_euler().y)
	if p.brain:
		p.brain.reset()
	if p.has_node("NameTag"):
		p.get_node("NameTag").visible = true
	if p == player:
		hud.hide_death()


func _on_player_died(killer: Node, victim: CharacterBody3D) -> void:
	if _online:
		return      # en ligne, le serveur annonce les éliminations (voir _on_net_death)
	_respawns[victim] = MatchRules.RESPAWN_DELAY
	if victim.has_node("NameTag"):
		victim.get_node("NameTag").visible = false
	var killer_name := "Arène"
	var weapon_name := "—"
	if killer and killer != victim and killer in players:
		killer.add_kill()
		killer_name = killer.player_name
		weapon_name = killer.weapon.data.display_name
		if killer == player:
			_ui.show_banner(_kill_banner(killer.streak, victim.last_headshot))
	elif killer and killer.get("player_name") == null and killer != victim:
		killer_name = str(killer.name)
	if _mode == "deathmatch":
		_ui.add_kill(killer_name, victim.player_name, weapon_name, killer == player, victim == player, victim.last_headshot)
	if victim == player:
		hud.show_death(killer_name if killer_name != "Arène" else "")


## Bannière d'élimination : série en cours, sinon tir à la tête, sinon simple élimination.
func _kill_banner(streak: int, headshot: bool) -> String:
	var text: String = STREAK_BANNERS.get(streak, "TIR À LA TÊTE" if headshot else "ÉLIMINATION")
	return "%s  +100" % text


# ---------------------------------------------------------------- Partie

func _scoreboard_rows() -> Array:
	if _online:
		return _net_scoreboard_rows()
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
	if _online:
		return "Serveur dédié · %d joueurs · %s" % [Net.players.size(), MapCatalog.name_of(map.map_id())]
	return "Hors ligne · %s" % MapCatalog.name_of(map.map_id())


func _finish_match() -> void:
	_running = false
	_time_left = 0.0
	if _pause.is_open():
		_pause.close()
		hud.visible = true
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
	# Les statistiques ne comptent que les parties en ligne : c'est le serveur de
	# jeu qui envoie les résultats au back (match.finished), jamais le jeu.


# ---------------------------------------------------------------- Entraînement

func _spawn_targets() -> void:
	var index := 0
	for point in map.target_points():
		var target := TargetScene.instantiate()
		target.crouched = index % 3 == 2   # un mannequin sur trois est accroupi
		add_child(target)
		target.global_position = point
		target.rotation.y = randf() * TAU
		index += 1


# ---------------------------------------------------------------- Projectiles et effets

## Hors ligne : crée un projectile qui fait foi (Projectile.launch, groupe "projectile_host").
func launch_projectile(data: WeaponData, shooter: Node, origin: Vector3, velocity: Vector3) -> void:
	var projectile := Projectile.new()
	projectile.setup(data, shooter, origin, velocity, true)
	projectile.exploded.connect(_on_projectile_exploded)
	add_child(projectile)


## Hors ligne : explosion d'un projectile, dégâts de zone et effets appliqués ici.
func _on_projectile_exploded(projectile: Projectile, position: Vector3, direct_target: Node) -> void:
	var shooter: Node = projectile.shooter if is_instance_valid(projectile.shooter) else null
	_offline_explosion(position, projectile.data, shooter, direct_target)


## Hors ligne : explosion (roquette, grenade, lance-caca, onde de choc).
func _offline_explosion(position: Vector3, data: WeaponData, shooter: Node, direct_target: Node) -> void:
	_explosion_fx(position, data)
	var multiplier: float = shooter.damage_multiplier() if shooter and shooter.has_method("damage_multiplier") else 1.0
	var any_hit := false
	var any_kill := false
	for victim in MatchRules.explosion_victims(get_world_3d(), position, data, shooter, direct_target):
		var node: Node = victim.node
		if node != shooter:
			any_hit = true
		var killed: bool = node.take_damage(int(round(victim.damage * multiplier)), shooter)
		any_kill = any_kill or (killed and node != shooter)
		if node.has_method("apply_effect"):
			if data.knockback > 0.0:
				node.apply_effect("knockback", data.knockback, 0.0, victim.direction, shooter)
			if data.slow_time > 0.0:
				node.apply_effect("slow", data.slow_factor, data.slow_time, Vector3.ZERO, shooter)
			if data.splat_time > 0.0:
				node.apply_effect("splat", 1.0, data.splat_time, Vector3.ZERO, shooter)
	if shooter == player and any_hit:
		player.hit_confirmed.emit(any_kill, false)


## En ligne : projectile annoncé par le serveur, affiché ici (sans dégâts).
func _on_net_projectile(projectile_id: int, weapon_id: String, origin: Vector3, velocity: Vector3, shooter_id: int) -> void:
	var data := WeaponCatalog.find(weapon_id)
	if data == null:
		return
	var projectile := Projectile.new()
	projectile.setup(data, _net_nodes.get(shooter_id), origin, velocity, false)
	add_child(projectile)
	_net_projectiles[projectile_id] = projectile


## En ligne : explosion annoncée par le serveur (la position fait foi).
func _on_net_explosion(projectile_id: int, position: Vector3, weapon_id: String) -> void:
	var projectile = _net_projectiles.get(projectile_id)
	_net_projectiles.erase(projectile_id)
	if is_instance_valid(projectile):
		projectile.finish(position)
	var data := WeaponCatalog.find(weapon_id)
	if data:
		_explosion_fx(position, data)


## En ligne : effet subi par mon joueur (ralentissement, tache, recul), décidé par le serveur.
func _on_net_effect(kind: String, value: float, duration: float, direction: Vector3) -> void:
	if is_instance_valid(player):
		player.apply_effect(kind, value, duration, direction, null)


## Fond sonore de NEO-EDO en boucle (rumeur de la ville, vent, néons), très discret.
func _start_ambience() -> void:
	var loop := Sfx.looping("ambience")
	if loop == null:
		return
	var player_node := AudioStreamPlayer.new()
	player_node.name = "Ambience"
	player_node.stream = loop
	player_node.bus = Settings.SFX_BUS
	player_node.volume_db = -16.0
	player_node.autoplay = true
	add_child(player_node)


func _explosion_fx(position: Vector3, data: WeaponData) -> void:
	var cartoon := data.model == WeaponData.Model.POOP
	Effects.explosion(self, position, data.splash_radius, data.tracer_color, cartoon)
	if data == Pickups.SHOCKWAVE:
		Effects.shockwave(self, position, data.splash_radius)
	if cartoon:
		Sfx.play_at("poop_splat", position, 0.0, 1.0, 60.0)
	else:
		Sfx.play_at("explosion", position, 6.0, 1.0, 160.0)


# ---------------------------------------------------------------- Bonus de la map

## Relie le HUD au joueur local, et la bannière des bonus ramassés.
func _bind_player(p: CharacterBody3D) -> void:
	hud.bind(p)
	if not p.bonus_picked.is_connected(_on_bonus_picked):
		p.bonus_picked.connect(_on_bonus_picked)


func _on_bonus_picked(kind: int) -> void:
	var text := Pickups.name_of(kind).to_upper()
	match kind:
		Pickups.Kind.HEAL:
			text = "+%d PV" % Pickups.HEAL_AMOUNT
		Pickups.Kind.ARMOR:
			text = "ARMURE +%d" % Pickups.ARMOR_AMOUNT
		Pickups.Kind.SUPER:
			if player.super_power >= 0:
				text = "%s  ·  %s" % [Pickups.SUPER_INFO[player.super_power].name.to_upper(), Inputs.hint("super")]
	_ui.show_banner(text, Pickups.color_of(kind))
	Sfx.play("powerup" if kind == Pickups.Kind.SUPER else "pickup", -4.0)


## Hors ligne : un personnage (joueur ou bot) a ramassé un bonus.
func _on_pickup_offline(_pad_id: int, kind: int, node: Node) -> void:
	match kind:
		Pickups.Kind.HEAL:
			node.health = mini(node.health + Pickups.HEAL_AMOUNT, node.class_data.max_health)
			node.health_changed.emit(node.health, node.class_data.max_health)
		Pickups.Kind.ARMOR:
			node.apply_effect("armor", mini(node.armor + Pickups.ARMOR_AMOUNT, Pickups.ARMOR_MAX), 0.0)
		Pickups.Kind.DOUBLE_JUMP:
			node.apply_effect("double_jump", 0.0, Pickups.DOUBLE_JUMP_TIME)
		Pickups.Kind.SPEED:
			node.apply_effect("speed", Pickups.SPEED_BONUS, Pickups.SPEED_TIME)
		Pickups.Kind.SUPER:
			node.set_super(Pickups.random_super())
		_:
			var data := WeaponCatalog.find(Pickups.weapon_of(kind))
			if data:
				node.give_special(data)
	node.apply_effect("picked", kind, 0.0)


## Hors ligne : déclenche le super-pouvoir en réserve (appelé par player.use_super).
func activate_super(node: Node) -> void:
	var power: int = node.super_power
	if power < 0 or not node.alive:
		return
	node.set_super(-1)
	match power:
		Pickups.Super.OVERLOAD:
			node.apply_aura(power, Pickups.OVERLOAD_TIME)
		Pickups.Super.INVISIBILITY:
			node.apply_aura(power, Pickups.INVISIBILITY_TIME)
		Pickups.Super.SHOCKWAVE:
			_offline_explosion(node.chest_position(), Pickups.SHOCKWAVE, node, null)


## En ligne : arme spéciale donnée à un joueur (annoncée par le serveur).
func _on_net_special(peer_id: int, weapon_id: String) -> void:
	var node = _net_nodes.get(peer_id)
	var data := WeaponCatalog.find(weapon_id)
	if is_instance_valid(node) and data:
		node.give_special(data)


## En ligne : effet de super-pouvoir d'un joueur (Surcharge, invisibilité).
func _on_net_aura(peer_id: int, kind: int, duration: float) -> void:
	var node = _net_nodes.get(peer_id)
	if is_instance_valid(node):
		node.apply_aura(kind, duration)
