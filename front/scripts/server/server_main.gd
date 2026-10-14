extends Node
## Point d'entrée du serveur dédié (scenes/server/server.tscn), choisi au
## démarrage par scripts/boot.gd. Pas de fenêtre : tout passe par la console.
##
## Deux modes :
##   LAN (par défaut)   pas de back ; les joueurs viennent par adresse IP et le
##                      premier connecté (le chef) règle et lance la partie.
##   Server List        --serverlist-url http://hôte:8002, avec la variable
##                      d'environnement GAME_SERVER_SECRET. Le serveur s'enregistre,
##                      un groupe le réserve, chaque joueur présente son ticket et la
##                      partie démarre seule quand le groupe est là (ou 30 s après la
##                      réservation). Les résultats partent au back (match.finished).
##
## Arguments (tous facultatifs) :
##   --port 24567                      port UDP d'écoute
##   --name "Arena TPS"                nom du serveur (liste des serveurs)
##   --public-address 1.2.3.4          adresse que la Server List donne aux joueurs
##   --region eu                       région annoncée à la Server List
##   --bots 2 --duration 180           réglages des parties (modifiables par le chef en LAN)
##   --serverlist-url http://…:8002    active le mode Server List
##
## Le serveur tourne sans fin, d'une partie à l'autre :
##   idle -> [reserved] -> in_progress (partie) -> ending (écran de fin) -> idle
## Ctrl+C l'arrête.

const ServerGameScript := preload("res://scripts/server/server_game.gd")
## Temps laissé aux joueurs sur l'écran de fin avant le retour au salon.
const ENDING_DELAY := 10.0
const HEARTBEAT_INTERVAL := 5.0
## Mode Server List : délai après la réservation au-delà duquel la partie démarre
## avec les joueurs déjà là, même si tout le groupe n'est pas connecté.
const RESERVED_START_DELAY := 30.0

var _link: BackendLink
var _game: Node3D
## Joueurs dans la partie en cours : identifiant réseau -> user_id (pour player.match).
var _in_match := {}
## Mode Server List : joueurs attendus (connectés + tickets pas encore utilisés)
## et temps écoulé depuis la réservation.
var _expected_players := 0
var _reserved_for := 0.0


func _ready() -> void:
	# Sans affichage, rien ne limite la boucle principale : on évite de
	# consommer tout un cœur du processeur pour rien.
	Engine.max_fps = 60
	var args := _parse_args()
	var port := int(args.get("port", Net.DEFAULT_PORT))

	var serverlist_url := str(args.get("serverlist-url", ""))
	if serverlist_url.is_empty():
		_link = LanLink.new()
	else:
		var secret := OS.get_environment("GAME_SERVER_SECRET")
		if secret.is_empty():
			_fail("Mode Server List : définis la variable d'environnement GAME_SERVER_SECRET (la même que dans le .env du back).")
			return
		_link = ServerListLink.new(serverlist_url, secret)
	add_child(_link)

	var error := Net.serve(port)
	if not error.is_empty():
		_fail(error)
		return
	error = await _link.start({
		"name": args.get("name", "Arena TPS"),
		"address": args.get("public-address", _first_address()),
		"port": port,
		"region": args.get("region", "eu"),
		"map": MatchRules.MAP_ID,
		"max_players": Net.MAX_PLAYERS,
		"build_version": Backend.BUILD_VERSION,
	})
	if not error.is_empty():
		Net.leave()
		_fail(error)
		return

	Net.lan_lobby = _link.is_lan()
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
	_link.reserved.connect(_on_reserved)
	_link.reservation_ended.connect(_on_reservation_ended)

	var heartbeat := Timer.new()
	heartbeat.wait_time = HEARTBEAT_INTERVAL
	heartbeat.autostart = true
	heartbeat.timeout.connect(_heartbeat)
	add_child(heartbeat)
	_heartbeat()

	print("")
	print("=== Arena TPS — serveur dédié (version %s) ===" % Backend.BUILD_VERSION)
	if _link.is_lan():
		print("Mode LAN. Les joueurs se connectent avec REJOINDRE et une de ces adresses :")
		for address in Net.local_addresses():
			print("    %s:%d" % [address, port])
		print("Le premier joueur connecté règle la partie et la lance. Ctrl+C pour arrêter.")
		print("(Pour les parties lancées depuis le jeu avec le vrai back : --serverlist-url http://<back>:8002")
		print(" et la variable d'environnement GAME_SERVER_SECRET, voir docs/LANCER.md section 7.)")
	else:
		print("Mode Server List (%s). Les groupes lancent leurs parties depuis le jeu." % serverlist_url)
		print("Adresse donnée aux joueurs : %s:%d. Ctrl+C pour arrêter." % [args.get("public-address", _first_address()), port])
	print("")


func _fail(message: String) -> void:
	printerr(message)
	get_tree().quit(1)


## Arrêt propre (fin de la boucle principale) : le serveur se désenregistre.
func _exit_tree() -> void:
	if is_instance_valid(_link):
		_link.stop()


func _heartbeat() -> void:
	await _link.report(Net.server_status, Net.human_count(), MatchRules.MAP_ID)
	if Net.server_status == "reserved":
		# Les tickets expirés ne comptent plus : on n'attend que les joueurs qui peuvent encore venir.
		_expected_players = Net.human_count() + _link.reserved_slots


func _process(delta: float) -> void:
	if Net.server_status != "reserved":
		return
	_reserved_for += delta
	var connected := Net.human_count()
	if connected > 0 and (connected >= _expected_players or _reserved_for >= RESERVED_START_DELAY):
		Net.log_line("SERVEUR : %d/%d joueur(s) du groupe connecté(s), lancement" % [connected, _expected_players])
		Net.start_match()


# ---------------------------------------------------------------- Réservation (Server List)

func _on_reserved(_party_id: String) -> void:
	if Net.server_status != "idle":
		return
	_reserved_for = 0.0
	_expected_players = Net.human_count() + _link.reserved_slots
	Net.set_status("reserved")


func _on_reservation_ended() -> void:
	if Net.server_status == "reserved":
		Net.set_status("idle")


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
	if not _link.is_lan():
		# Partie d'un groupe terminée : tout le monde retourne au menu et le
		# serveur redevient libre pour le prochain groupe.
		_link.party_id = null
		await Net.close_all("Partie terminée : retour au menu.")
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
