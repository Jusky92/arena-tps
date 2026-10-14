extends Node3D
## Partie en cours sur le serveur dédié (sans affichage). Créée par server_main.gd
## au lancement de la partie, libérée au retour au salon.
##
## Le serveur ne joue pas : il arbitre.
##   - les joueurs humains sont des pantins qui suivent l'état envoyé par leur client ;
##   - les bots sont simulés ici (BotBrain) et diffusés comme les joueurs ;
##   - il applique les dégâts signalés par les tireurs, annonce les éliminations,
##     décide des réapparitions et tient le chronomètre ;
##   - à la fin, il envoie les résultats au back (match.finished) via BackendLink.

const MapScene := preload("res://scenes/maps/arena.tscn")
const PlayerScene := preload("res://scenes/player.tscn")

## Lien vers le back (donné par server_main.gd avant l'ajout à l'arbre).
var link: BackendLink

# Lus par BotBrain (scripts/bots/bot_brain.gd) à travers `brain.game`.
var map: ArenaMap
var players: Array = []                 # tous les personnages (pantins + bots)
var roam_points: Array = []
var nav_map: RID

var _nodes := {}                        # identifiant réseau -> personnage
var _human_states := {}                 # identifiant -> dernier état reçu du client
var _respawns := {}                     # identifiant -> temps restant avant réapparition
## Scores par user_id (bots : "bot:<id>"), gardés même quand le joueur part :
## match.finished inclut les joueurs partis en cours de route, une seule fois
## chacun, même s'ils sont revenus avec un autre identifiant réseau.
var _results := {}
var _result_keys := {}                  # identifiant réseau -> clé dans _results
var _match_id := ""
var _started_at := ""
var _running := false


func _ready() -> void:
	map = MapScene.instantiate()
	add_child(map)
	nav_map = MatchRules.bake_navigation(self, map)
	roam_points = MatchRules.roam_points()
	for id in Net.players:
		_spawn(id)
	_match_id = Uuid.v4()
	_started_at = _now_iso()
	_running = true

	Net.health_provider = _apply_damage
	Net.remote_states.connect(_on_remote_states)
	Net.player_died.connect(_on_death)
	Net.player_respawned.connect(_on_respawn)
	Net.remote_spawned.connect(_on_joined)
	Net.remote_left.connect(_on_left)


func _exit_tree() -> void:
	Net.health_provider = Callable()


func _process(delta: float) -> void:
	if not _running:
		return
	_publish_states()
	for id in _respawns.keys():
		_respawns[id] -= delta
		if _respawns[id] <= 0.0:
			_respawns.erase(id)
			_respawn(id)
	Net.match_time_left -= delta
	if Net.match_time_left <= 0.0:
		_end_match()


# ---------------------------------------------------------------- Personnages

func _spawn(id: int) -> CharacterBody3D:
	var info: Dictionary = Net.players[id]
	var bot := Net.is_bot(id)
	var p: CharacterBody3D = PlayerScene.instantiate()
	p.class_data = load(info.class_id)
	p.player_name = info.name
	p.is_local = false
	p.is_remote = not bot           # un humain suit l'état envoyé par son client
	p.peer_id = id
	if bot:
		var brain := BotBrain.new()
		brain.game = self
		brain.skill = randf_range(0.35, 0.75)
		p.brain = brain
	p.name = "Net_%d" % id
	add_child(p)
	# Un humain choisit son point d'apparition et le pantin s'y replace dès le
	# premier état reçu ; un bot apparaît loin des autres.
	p.global_transform = MatchRules.best_spawn(map, players, p)
	p.add_to_group("players")       # utilisé par les caméras et capteurs de la map
	p.start_spawn_protection()
	players.append(p)
	_nodes[id] = p
	var user_id: String = "" if bot else info.get("user_id", "")
	var key := ("bot:%d" % id) if bot else (user_id if not user_id.is_empty() else "pair:%d" % id)
	_result_keys[id] = key
	if not _results.has(key):
		_results[key] = {"user_id": user_id, "bot": bot, "kills": 0, "deaths": 0}
	return p


func _remove_node(id: int) -> void:
	var node = _nodes.get(id)
	if is_instance_valid(node):
		players.erase(node)
		node.remove_from_group("players")
		node.queue_free()
	_nodes.erase(id)
	_human_states.erase(id)
	_respawns.erase(id)


## Un joueur arrive en cours de partie. S'il n'y a plus de place, un bot lui cède la sienne.
func _on_joined(id: int, _info: Dictionary) -> void:
	if _nodes.has(id) or not Net.players.has(id):
		return
	_spawn(id)
	if _nodes.size() > Net.MAX_PLAYERS:
		var bots := _nodes.keys().filter(func(i): return Net.is_bot(i))
		if not bots.is_empty():
			bots.sort()
			Net.remove_player(bots[0])


## Un joueur est parti (ou un bot a été retiré). Ses scores restent dans _results.
func _on_left(id: int) -> void:
	_remove_node(id)
	if _running and Net.human_count() == 0:
		Net.log_line("SERVEUR : plus aucun joueur, fin de la partie")
		_end_match()


# ---------------------------------------------------------------- Réseau

## Diffuse l'état de tous les personnages : les bots simulés ici, et les
## humains tels que leur client les a envoyés (sans le lissage du pantin).
func _publish_states() -> void:
	var states := {}
	for id in _nodes:
		var node: CharacterBody3D = _nodes[id]
		if not is_instance_valid(node):
			continue
		if Net.is_bot(id):
			states[id] = node.net_state()
		elif _human_states.has(id):
			states[id] = _human_states[id]
	Net.publish_state(states)


func _on_remote_states(_sender_id: int, states: Dictionary) -> void:
	for id in states:
		var node = _nodes.get(id)
		if is_instance_valid(node) and node.is_remote:
			node.apply_net_state(states[id])
			_human_states[id] = states[id]


## Un tireur signale un impact : on applique les dégâts et on diffuse.
func _apply_damage(target_id: int, damage: int, shooter_id: int, weapon: String) -> void:
	var node = _nodes.get(target_id)
	if not is_instance_valid(node) or not node.alive or node.is_protected():
		return
	node.health = maxi(node.health - MatchRules.damage_taken(node, damage), 0)
	var shooter = _nodes.get(shooter_id)
	if node.brain and is_instance_valid(shooter):
		node.brain.on_damaged(node, shooter)
	Net.push_health.rpc(target_id, node.health, node.class_data.max_health)
	if node.health == 0:
		Net.push_death.rpc(target_id, shooter_id, weapon)


## Élimination (annoncée par push_death, qui s'exécute aussi ici).
func _on_death(victim_id: int, killer_id: int, _weapon: String) -> void:
	var victim = _nodes.get(victim_id)
	if is_instance_valid(victim):
		victim.net_die()
	var victim_key: String = _result_keys.get(victim_id, "")
	var killer_key: String = _result_keys.get(killer_id, "")
	if _results.has(victim_key):
		_results[victim_key].deaths += 1
	if _results.has(killer_key) and killer_id != victim_id:
		_results[killer_key].kills += 1
	_respawns[victim_id] = MatchRules.RESPAWN_DELAY


## Réapparition décidée ici, avec la classe choisie par le joueur (Net.set_class).
func _respawn(id: int) -> void:
	var node = _nodes.get(id)
	if not is_instance_valid(node):
		return
	var t := MatchRules.best_spawn(map, players, node)
	Net.push_respawn.rpc(id, t.origin, t.basis.get_euler().y, Net.class_path_of(id))


## Réapparition (annoncée par push_respawn, qui s'exécute aussi ici).
func _on_respawn(id: int, position: Vector3, yaw: float, class_id: String) -> void:
	var node = _nodes.get(id)
	if not is_instance_valid(node):
		return
	if node.class_data.resource_path != class_id:
		_remove_node(id)
		node = _spawn(id)
	node.respawn(position, yaw)
	node.teleport(position, yaw)
	if node.brain:
		node.brain.reset()


# ---------------------------------------------------------------- Fin de partie

func _end_match() -> void:
	if not _running:
		return
	_running = false
	Net.match_time_left = 0.0
	link.match_finished(_match_result())
	Net.push_match_over.rpc(Net.sorted_players())


## Résultat au format de l'événement match.finished (voir BackendLink.match_finished).
## Le classement compte les bots, mais seuls les joueurs humains sont envoyés.
func _match_result() -> Dictionary:
	var rows := []
	for key in _results:
		rows.append(_results[key].duplicate())
	MatchRules.rank(rows)
	var results := []
	for row in rows:
		if not row.bot and not row.user_id.is_empty():
			results.append({"user_id": row.user_id, "kills": row.kills, "deaths": row.deaths, "placement": row.placement})
	return {
		"match_id": _match_id,
		"server_id": link.server_id,
		"party_id": link.party_id,
		"map": MatchRules.MAP_ID,
		"started_at": _started_at,
		"ended_at": _now_iso(),
		"players": results,
	}


static func _now_iso() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"
