extends Node
## Point d'entrée du serveur dédié (scenes/server/server.tscn), choisi au
## démarrage par scripts/boot.gd. Pas de fenêtre : tout passe par la console.
##
## Arguments (tous facultatifs) :
##   --port 24567              port UDP d'écoute
##   --name "Arena TPS"        nom du serveur (liste des serveurs)
##   --public-address 1.2.3.4  adresse que les joueurs utilisent (pour le back)
##   --bots 2 --duration 180   réglages par défaut du salon (modifiables par le chef)
##
## Le serveur tourne sans fin, d'une partie à l'autre :
##   idle (salon) -> in_progress (partie) -> ending (écran de fin) -> idle
## Ctrl+C l'arrête.

const ServerGameScript := preload("res://scripts/server/server_game.gd")
## Temps laissé aux joueurs sur l'écran de fin avant le retour au salon.
const ENDING_DELAY := 10.0
const HEARTBEAT_INTERVAL := 5.0

var _link: BackendLink
var _game: Node3D
## Joueurs dans la partie en cours : identifiant réseau -> user_id (pour player.match).
var _in_match := {}


func _ready() -> void:
	# Sans affichage, rien ne limite la boucle principale : on évite de
	# consommer tout un cœur du processeur pour rien.
	Engine.max_fps = 60
	var args := _parse_args()
	var port := int(args.get("port", Net.DEFAULT_PORT))

	_link = LanLink.new()
	add_child(_link)
	var error := Net.serve(port)
	if not error.is_empty():
		printerr(error)
		get_tree().quit(1)
		return
	error = _link.start({
		"name": args.get("name", "Arena TPS"),
		"address": args.get("public-address", _first_address()),
		"port": port,
		"map": MatchRules.MAP_ID,
		"max_players": Net.MAX_PLAYERS,
		"build_version": Backend.BUILD_VERSION,
	})
	if not error.is_empty():
		printerr(error)
		Net.leave()
		get_tree().quit(1)
		return

	Net.settings = {
		"bots": clampi(int(args.get("bots", 2)), 0, Net.MAX_PLAYERS - 1),
		"duration": clampf(float(args.get("duration", 180.0)), 60.0, 600.0),
	}
	Net.ticket_verifier = _link.verify
	Net.start_requested.connect(Net.start_match)
	Net.match_starting.connect(_on_match_starting)
	Net.match_over.connect(_on_match_over)
	Net.player_accepted.connect(_on_player_accepted)
	Net.remote_left.connect(_on_player_left)

	var heartbeat := Timer.new()
	heartbeat.wait_time = HEARTBEAT_INTERVAL
	heartbeat.autostart = true
	heartbeat.timeout.connect(_heartbeat)
	add_child(heartbeat)

	print("")
	print("=== Arena TPS — serveur dédié (version %s) ===" % Backend.BUILD_VERSION)
	print("Les joueurs se connectent avec REJOINDRE et une de ces adresses :")
	for address in Net.local_addresses():
		print("    %s:%d" % [address, port])
	print("Le premier joueur connecté règle la partie et la lance. Ctrl+C pour arrêter.")
	print("")


## Arrêt propre (fin de la boucle principale) : le serveur se désenregistre.
func _exit_tree() -> void:
	if is_instance_valid(_link):
		_link.stop()


func _heartbeat() -> void:
	_link.report(Net.server_status, Net.human_count(), MatchRules.MAP_ID)


# ---------------------------------------------------------------- Partie

func _on_match_starting() -> void:
	_game = ServerGameScript.new()
	_game.link = _link
	_game.name = "Match"
	add_child(_game)
	for id in Net.players:
		if not Net.is_bot(id):
			_player_joined_match(id)
	_heartbeat()          # « mise à jour immédiate sur un changement important »


func _on_match_over(_rows: Array) -> void:
	for id in _in_match.keys():
		_link.player_match(_in_match[id], "left")
	_in_match.clear()
	_heartbeat()
	await get_tree().create_timer(ENDING_DELAY).timeout
	if is_instance_valid(_game):
		_game.queue_free()
	_game = null
	Net.back_to_lobby()
	_heartbeat()


func _on_player_accepted(id: int) -> void:
	if Net.in_match:
		_player_joined_match(id)
		_heartbeat()


func _on_player_left(id: int) -> void:
	if _in_match.has(id):
		_link.player_match(_in_match[id], "left")
		_in_match.erase(id)
		_heartbeat()


func _player_joined_match(id: int) -> void:
	var user_id: String = Net.players[id].get("user_id", "")
	if user_id.is_empty() or _in_match.has(id):
		return
	_in_match[id] = user_id
	_link.player_match(user_id, "joined")


# ---------------------------------------------------------------- Arguments

## Lit "--clé valeur" et "--clé=valeur", qu'ils soient donnés directement à
## l'exécutable ou après "--" (lancement depuis l'éditeur ou `godot --path`).
static func _parse_args() -> Dictionary:
	var result := {}
	var all := Array(OS.get_cmdline_args()) + Array(OS.get_cmdline_user_args())
	var i := 0
	while i < all.size():
		var arg: String = all[i]
		if arg.begins_with("--") and arg.length() > 2:
			if arg.contains("="):
				result[arg.substr(2).get_slice("=", 0)] = arg.get_slice("=", 1)
			elif i + 1 < all.size() and not String(all[i + 1]).begins_with("--"):
				result[arg.substr(2)] = all[i + 1]
				i += 1
			else:
				result[arg.substr(2)] = true
		i += 1
	return result


func _first_address() -> String:
	var addresses := Net.local_addresses(1)
	return addresses[0] if not addresses.is_empty() else "127.0.0.1"
