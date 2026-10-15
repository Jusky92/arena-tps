extends Node
## Multijoueur en ligne (autoload "Net"), commun au client et au serveur dédié.
##
##   SERVEUR DÉDIÉ (ArenaTPS_Server, sans fenêtre) = serveur ENet, ne joue pas.
##   CLIENTS (ArenaTPS)                            = se connectent au serveur par IP.
##
## Le même fichier tourne des deux côtés : Godot exige que les fonctions @rpc
## existent, à l'identique, sur le même nœud (/root/Net) chez tout le monde.
## `is_server()` dit de quel côté on est.
##
## Qui décide de quoi (première étape, voir project-context.md) :
##   - chaque client simule SON joueur (déplacement, saut, visée) et envoie son
##     état au serveur 20 fois par seconde ; le serveur le rediffuse aux autres ;
##   - le tireur détecte ses impacts et les signale : `hit()` ;
##   - le SERVEUR est seul juge du reste : points de vie, éliminations, score,
##     chronomètre, réapparitions, bots. Il diffuse le résultat à tout le monde.
## Plus tard, le serveur simulera tout à partir des commandes des joueurs
## (PlayerCommands) pour empêcher la triche.
##
## Les joueurs sont identifiés par leur `user_id` (compte Auth). Avec le vrai back,
## le client présente un ticket d'accès que le serveur fait vérifier par la
## Server List ; en LAN, le ticket est vide et le serveur accepte (voir
## scripts/server/backend_link.gd).
##
## États du serveur (comme dans la Server List) :
##   idle -> reserved -> in_progress -> ending -> idle
## En LAN, il n'y a pas de réservation : le premier joueur connecté (le « chef »)
## règle la partie et la lance, idle -> in_progress. Avec la Server List, un
## groupe réserve le serveur et la partie démarre seule quand il est connecté ;
## à la fin, le serveur renvoie tout le monde au menu et redevient libre.
##
## Protocole (toutes les fonctions marquées @rpc) :
##   client -> serveur  hello, set_class, request_settings, request_start, state, hit
##   serveur -> clients refuse, lobby, start_match, player_joined, player_left,
##                      states, health, hit, death, respawn, match_over
##
## Tirs : le client envoie seulement « j'ai touché telle cible, à tel endroit, avec
## telle arme ». Le serveur vérifie (arme, portée, ligne de vue, cadence), choisit
## la zone (tête ou corps) et calcule lui-même les dégâts (voir server_game.gd).
##
## Port par défaut : 24567 (UDP). Voir docs/RESEAU.md pour l'ouverture du port.

signal lobby_changed                      ## la liste des joueurs ou les réglages ont changé
signal joined                             ## client : le serveur nous a acceptés
signal match_starting                     ## la partie commence (ou on la rejoint en cours)
signal connection_failed(reason: String)
signal disconnected(reason: String)
signal remote_states(sender_id: int, states: Dictionary)
signal remote_spawned(peer_id: int, info: Dictionary)
signal remote_left(peer_id: int)
signal health_updated(peer_id: int, health: int, max_health: int)
signal player_died(victim_id: int, killer_id: int, weapon: String, headshot: bool)
## Un tir validé par le serveur (reçu seulement par la cible et le tireur).
signal hit_landed(target_id: int, shooter_id: int, damage: int, headshot: bool)
signal player_respawned(peer_id: int, position: Vector3, yaw: float, class_id: String)
signal match_over(rows: Array)
## Serveur : un joueur a passé la vérification d'accès / est parti.
signal player_accepted(peer_id: int)
## Serveur : le chef demande le lancement.
signal start_requested

const DEFAULT_PORT := 24567
## Joueurs humains par partie (max_players de la Server List). Le serveur dédié peut
## le changer avec --max-players ; une partie va de 1 humain (+ bots) à ce nombre.
var max_players := 16
const STATE_HZ := 20.0                    ## envois d'état par seconde
## Au-delà de ce délai sans réponse, on abandonne (client) ou on coupe (serveur).
const CONNECT_TIMEOUT := 6.0
## Journal réseau, utile pour comprendre un échec de connexion.
## Windows : %APPDATA%\Godot\app_userdata\Arena TPS\reseau.log
## Linux   : ~/.local/share/godot/app_userdata/Arena TPS/reseau.log
const LOG_PATH := "user://reseau.log"

## true dès qu'on est en ligne (serveur ou client).
var online := false
## Pseudo local (client).
var pseudo := "Joueur"
## Joueurs de la partie : id de pair -> {name, class_id, kills, deaths, bot, user_id}.
## Le serveur (pair 1) n'y figure pas : il ne joue pas. Les bots ont un id négatif.
var players := {}
## Réglages de la partie, choisis par le chef.
var settings := {"bots": 2, "duration": 180.0}
## true en LAN : le chef (premier joueur) règle et lance la partie. false avec
## la Server List : pas de chef, la partie démarre quand le groupe est connecté.
var lan_lobby := true
## Pair qui peut régler et lancer la partie (LAN uniquement, 0 = personne).
var leader_id := 0
## idle | reserved | in_progress | ending
var server_status := "idle"
## true pendant une partie.
var in_match := false
## Temps restant de la partie en cours. Tenu par le serveur ; un client qui
## rejoint en cours de partie le reçoit avec `start_match`.
var match_time_left := 0.0
## Serveur : vérifie le ticket d'un joueur. Reçoit (ticket, user_id annoncé) et
## renvoie le user_id vérifié, ou "" si l'accès est refusé. Peut être une coroutine.
var ticket_verifier: Callable = Callable()
## Serveur : arbitre un impact signalé par un tireur (rempli par server_game.gd).
## Reçoit (cible, tireur, point d'impact relatif à la cible, nom de l'arme).
var hit_resolver: Callable = Callable()

var _peer: ENetMultiplayerPeer
var _serving := false
var _state_timer := 0.0
var _last_state := {}
## Client : temps écoulé depuis la demande de connexion (-1 = pas en cours).
var _connect_elapsed := -1.0
var _target := ""
## Serveur : pairs connectés qui ne se sont pas encore présentés -> secondes écoulées.
var _unidentified := {}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func my_id() -> int:
	return multiplayer.get_unique_id() if online else 1


## true sur le serveur dédié.
func is_server() -> bool:
	return _serving


## true si ce client est le chef du salon (LAN uniquement).
func is_leader() -> bool:
	return online and not _serving and lan_lobby and leader_id == my_id()


## Serveur : ouvre l'écoute. Renvoie "" si tout va bien, sinon l'erreur.
func serve(port := DEFAULT_PORT) -> String:
	leave()
	log_line("SERVEUR : ouverture sur le port UDP %d (version %s)" % [port, Backend.BUILD_VERSION])
	# Deux places de plus que de joueurs : un joueur en trop doit pouvoir se
	# connecter le temps de recevoir le message « partie pleine ».
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, max_players + 2)
	if err != OK and err != ERR_ALREADY_IN_USE:
		# Certains Linux ont l'IPv6 désactivé : on réessaie en IPv4 seul.
		log_line("SERVEUR : échec en IPv4+IPv6 (code %d), nouvel essai en IPv4 seul" % err)
		_peer = ENetMultiplayerPeer.new()
		_peer.set_bind_ip("0.0.0.0")
		err = _peer.create_server(port, max_players + 2)
	if err != OK:
		_peer = null
		log_line("SERVEUR : impossible d'ouvrir le port (code %d)" % err)
		# ENet ne dit pas pourquoi il échoue : un port déjà pris donne souvent
		# ERR_CANT_CREATE plutôt que ERR_ALREADY_IN_USE.
		if err == ERR_ALREADY_IN_USE or err == ERR_CANT_CREATE:
			return "Le port %d est déjà utilisé sur ce PC (le serveur est peut-être lancé deux fois)." % port
		return "Impossible d'ouvrir le serveur (code %d)." % err
	multiplayer.multiplayer_peer = _peer
	# Tout passe par le serveur : les clients ne se parlent jamais directement.
	(multiplayer as SceneMultiplayer).server_relay = false
	online = true
	_serving = true
	server_status = "idle"
	log_line("SERVEUR : en écoute. Adresses à donner aux joueurs : %s" % ", ".join(local_addresses()))
	return ""


## Client : rejoint un serveur. `address` = IP ou nom d'hôte du PC serveur.
## `ticket` = ticket d'accès donné par le back (vide en LAN).
func join(address: String, player_name: String, port := DEFAULT_PORT, ticket := "") -> String:
	leave()
	_target = "%s:%d" % [address, port]
	log_line("CLIENT : connexion à %s (version %s)" % [_target, Backend.BUILD_VERSION])
	if not address.is_valid_ip_address():
		var resolved := IP.resolve_hostname(address, IP.TYPE_IPV4)
		if resolved.is_empty():
			log_line("CLIENT : adresse « %s » non reconnue" % address)
			return "Adresse « %s » non reconnue. Elle doit ressembler à 192.168.1.20" % address
		address = resolved
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address, port)
	if err != OK:
		_peer = null
		log_line("CLIENT : création du client impossible (code %d)" % err)
		return "Adresse invalide ou injoignable (code %d)." % err
	multiplayer.multiplayer_peer = _peer
	online = true
	pseudo = player_name
	_ticket = ticket
	_connect_elapsed = 0.0
	return ""


var _ticket := ""


## true pendant qu'un client attend la réponse du serveur.
func is_connecting() -> bool:
	return _connect_elapsed >= 0.0


## Secondes restantes avant d'abandonner la connexion.
func connect_time_left() -> float:
	return maxf(CONNECT_TIMEOUT - _connect_elapsed, 0.0)


## Ajoute une ligne horodatée au journal réseau (et dans la console).
func log_line(text: String) -> void:
	var line := "[%s] %s" % [Time.get_datetime_string_from_system(false, true), text]
	print(line)
	var file := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE if FileAccess.file_exists(LOG_PATH) else FileAccess.WRITE)
	if file:
		file.seek_end()
		file.store_line(line)


## Chemin du journal sur le disque, à montrer au joueur.
func log_file_path() -> String:
	return ProjectSettings.globalize_path(LOG_PATH)


## Ferme la connexion (retour au menu, déconnexion subie, arrêt du serveur).
func leave() -> void:
	_connect_elapsed = -1.0
	if _peer:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = null
	online = false
	_serving = false
	in_match = false
	server_status = "idle"
	leader_id = 0
	players = {}
	_last_state = {}
	_unidentified = {}


func player_name_of(peer_id: int) -> String:
	return players.get(peer_id, {}).get("name", "Joueur %d" % peer_id)


func class_path_of(peer_id: int) -> String:
	return players.get(peer_id, {}).get("class_id", GameState.CLASSES[0].resource_path)


func sorted_players() -> Array:
	var rows := []
	for id in players:
		var p: Dictionary = players[id]
		rows.append({"id": id, "name": p.name, "kills": p.kills, "deaths": p.deaths, "class_id": p.class_id})
	rows.sort_custom(func(a, b): return a.kills > b.kills or (a.kills == b.kills and a.deaths < b.deaths))
	return rows


func _new_player(name: String, class_id: String, user_id := "") -> Dictionary:
	return {"name": name, "class_id": class_id, "kills": 0, "deaths": 0, "bot": false, "user_id": user_id}


## true si cet identifiant est un bot (joué par le serveur).
func is_bot(id: int) -> bool:
	return id < 0


## Nombre de joueurs humains (les bots ne comptent pas).
func human_count() -> int:
	var count := 0
	for id in players:
		if not is_bot(id):
			count += 1
	return count


## true si cette machine fait jouer ce personnage (et doit donc envoyer son état) :
## le client son propre joueur, le serveur les bots.
func controls(id: int) -> bool:
	if _serving:
		return is_bot(id)
	return id == my_id()


func _lobby_info() -> Dictionary:
	return {"bots": settings.bots, "duration": settings.duration, "leader_id": leader_id, "status": server_status, "lan": lan_lobby}


func _apply_lobby_info(info: Dictionary) -> void:
	settings = {"bots": info.get("bots", 2), "duration": info.get("duration", 180.0)}
	leader_id = info.get("leader_id", 0)
	server_status = info.get("status", "idle")
	lan_lobby = info.get("lan", true)


# =========================================================================== connexion

func _on_peer_connected(id: int) -> void:
	if not _serving:
		return
	# Le client va se présenter avec `hello` ; sinon il est coupé (voir _process).
	log_line("SERVEUR : connexion du pair %d" % id)
	_unidentified[id] = 0.0


func _on_peer_disconnected(id: int) -> void:
	if not _serving:
		return
	_unidentified.erase(id)
	if not players.has(id):
		return
	log_line("SERVEUR : %s est parti (pair %d)" % [player_name_of(id), id])
	players.erase(id)
	if leader_id == id:
		leader_id = _first_human()
	remote_left.emit(id)
	if in_match:
		_player_left.rpc(id)
	lobby_changed.emit()
	_send_lobby()


func _first_human() -> int:
	var ids := players.keys().filter(func(i): return not is_bot(i))
	ids.sort()
	return ids[0] if not ids.is_empty() else 0


func _on_connected() -> void:
	# Le réseau passe : on se présente au serveur (compte, pseudo, classe, version).
	log_line("CLIENT : connexion ENet établie avec %s, présentation au serveur" % _target)
	_hello.rpc_id(1, Backend.user_id(), pseudo, GameState.selected_class.resource_path, _ticket, Backend.BUILD_VERSION)


func _on_connection_failed() -> void:
	_fail_connection()


func _on_server_disconnected() -> void:
	log_line("Connexion avec le serveur perdue")
	var was_connecting := is_connecting()
	leave()
	if was_connecting:
		connection_failed.emit("Le serveur a coupé la connexion avant d'accepter.")
	else:
		var reason := _close_reason if not _close_reason.is_empty() else "Le serveur a fermé la connexion."
		_close_reason = ""
		disconnected.emit(reason)


## Aucune réponse du serveur : on explique les causes possibles, dans l'ordre.
func _fail_connection() -> void:
	var target := _target
	log_line("CLIENT : aucune réponse de %s après %.0f s" % [target, CONNECT_TIMEOUT])
	leave()
	connection_failed.emit(
		("Aucune réponse de %s.\n" % target)
		+ "1. Le serveur (ArenaTPS_Server) doit être lancé sur le PC serveur.\n"
		+ "2. L'adresse doit être une de celles affichées par le serveur au démarrage.\n"
		+ ("3. Le pare-feu du PC serveur doit autoriser le port UDP %d (voir docs/RESEAU.md)." % DEFAULT_PORT))


# =========================================================================== salon

## Client -> serveur : je me présente.
@rpc("any_peer", "call_remote", "reliable")
func _hello(user_id: String, name: String, class_id: String, ticket: String, version: String) -> void:
	if not _serving:
		return
	var id := multiplayer.get_remote_sender_id()
	if not _unidentified.has(id):
		return              # déjà présenté (ou en cours de vérification)
	_unidentified.erase(id)
	log_line("SERVEUR : %s se présente (pair %d, version %s)" % [name, id, version])
	if version != Backend.BUILD_VERSION:
		_kick(id, "Versions différentes : le serveur a la %s, toi la %s. Réexportez le jeu depuis le même code." % [Backend.BUILD_VERSION, version])
		return
	if human_count() >= max_players:
		_kick(id, "La partie est pleine (%d joueurs)." % max_players)
		return
	if server_status == "ending":
		_kick(id, "La partie se termine, réessaie dans quelques secondes.")
		return
	# Vérification du ticket (appel à la Server List avec le vrai back).
	var verified := user_id
	if ticket_verifier.is_valid():
		verified = await ticket_verifier.call(ticket, user_id)
	if not multiplayer.get_peers().has(id):
		return              # parti pendant la vérification
	if verified.is_empty():
		_kick(id, "Accès refusé : ticket invalide ou expiré.")
		return
	for other in players.values():
		if other.user_id == verified:
			_kick(id, "Ce compte est déjà connecté à ce serveur.")
			return
	if human_count() >= max_players:
		_kick(id, "La partie est pleine (%d joueurs)." % max_players)
		return
	players[id] = _new_player(name.left(16), class_id, verified)
	if lan_lobby and leader_id == 0:
		leader_id = id
	player_accepted.emit(id)
	if in_match:
		# Arrivée en cours de partie : le nouveau reçoit tout, les autres l'ajoutent.
		_start_match.rpc_id(id, players, _lobby_info(), match_time_left)
		for other in players:
			if other != id and not is_bot(other):
				_player_joined.rpc_id(other, id, players[id])
		remote_spawned.emit(id, players[id])
	lobby_changed.emit()
	_send_lobby()


## Serveur : refuse un joueur avec un message, puis coupe sa connexion.
func _kick(id: int, reason: String) -> void:
	log_line("SERVEUR : pair %d refusé : %s" % [id, reason])
	_refuse.rpc_id(id, reason)
	get_tree().create_timer(1.0).timeout.connect(func() -> void:
		if _peer and multiplayer.get_peers().has(id):
			_peer.disconnect_peer(id))


## Serveur : envoie l'état du salon à tous les joueurs.
func _send_lobby() -> void:
	if _serving and not players.is_empty():
		_lobby.rpc(players, _lobby_info())


## Serveur -> clients : état du salon.
@rpc("authority", "call_remote", "reliable")
func _lobby(list: Dictionary, info: Dictionary) -> void:
	players = list
	_apply_lobby_info(info)
	if is_connecting():
		_connect_elapsed = -1.0
		log_line("CLIENT : accepté par le serveur (%d joueur(s))" % players.size())
		joined.emit()
	lobby_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _refuse(reason: String) -> void:
	log_line("Refusé par le serveur : " + reason)
	leave()
	connection_failed.emit(reason)


## Changement de classe depuis le salon ou le menu pause (appliqué à la
## prochaine apparition si la partie est en cours).
func set_class(class_id: String) -> void:
	if online and not _serving:
		_set_class.rpc_id(1, class_id)


@rpc("any_peer", "call_remote", "reliable")
func _set_class(class_id: String) -> void:
	if not _serving:
		return
	var id := multiplayer.get_remote_sender_id()
	if players.has(id):
		players[id].class_id = class_id
		if not in_match:
			lobby_changed.emit()
			_send_lobby()


## Chef : règle le nombre de bots et la durée.
func request_settings(bots: int, duration: float) -> void:
	if is_leader():
		_request_settings.rpc_id(1, bots, duration)


@rpc("any_peer", "call_remote", "reliable")
func _request_settings(bots: int, duration: float) -> void:
	if not _serving or not lan_lobby or multiplayer.get_remote_sender_id() != leader_id or in_match:
		return
	settings = {"bots": clampi(bots, 0, max_players - 1), "duration": clampf(duration, 60.0, 600.0)}
	lobby_changed.emit()
	_send_lobby()


## Chef : demande le lancement de la partie.
func request_start() -> void:
	if is_leader():
		_request_start.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_start() -> void:
	if _serving and lan_lobby and multiplayer.get_remote_sender_id() == leader_id and server_status == "idle":
		start_requested.emit()


## Noms des bots ajoutés par le serveur pour compléter la partie.
const BOT_NAMES := ["NeoByte", "Gl1tch", "V0LT", "Cipher", "Kairo", "Nova", "Raven", "Hexa",
	"ZeroDay", "Proxy", "Synth", "Kitsune", "Ronin", "Pixel", "Onyx"]


## Serveur : lance la partie pour tout le monde.
## Les bots entrent dans la même liste que les joueurs, avec un identifiant négatif :
## tout le monde les affiche, mais seul le serveur les fait jouer.
func start_match() -> void:
	if not _serving or in_match:
		return
	for id in players.keys():
		if is_bot(id):
			players.erase(id)
	for id in players:
		players[id].kills = 0
		players[id].deaths = 0
	var bots: int = clampi(settings.get("bots", 0), 0, max_players - players.size())
	for i in bots:
		var cls: ClassData = GameState.CLASSES[i % GameState.CLASSES.size()]
		players[-(i + 1)] = _new_player(BOT_NAMES[i % BOT_NAMES.size()], cls.resource_path)
		players[-(i + 1)]["bot"] = true
	in_match = true
	server_status = "in_progress"
	match_time_left = settings.get("duration", 180.0)
	log_line("SERVEUR : partie lancée (%d joueur(s), %d bot(s))" % [human_count(), bots])
	_start_match.rpc(players, _lobby_info(), match_time_left)
	match_starting.emit()


@rpc("authority", "call_remote", "reliable")
func _start_match(list: Dictionary, info: Dictionary, time_left: float) -> void:
	players = list
	_apply_lobby_info(info)
	match_time_left = time_left
	in_match = true
	if is_connecting():
		# Accepté directement dans une partie en cours : le menu principal, qui
		# attend `joined`, ouvre la partie au lieu du salon (Net.in_match).
		_connect_elapsed = -1.0
		log_line("CLIENT : accepté dans une partie en cours (%d joueur(s))" % players.size())
		joined.emit()
	else:
		match_starting.emit()


## Serveur -> clients déjà en partie : un joueur arrive en cours de partie.
@rpc("authority", "call_remote", "reliable")
func _player_joined(id: int, info: Dictionary) -> void:
	players[id] = info
	remote_spawned.emit(id, info)
	lobby_changed.emit()


## Serveur : retire un personnage de la partie (bot remplacé par un joueur).
func remove_player(id: int) -> void:
	if not _serving or not players.has(id):
		return
	players.erase(id)
	remote_left.emit(id)
	_player_left.rpc(id)
	lobby_changed.emit()


## Serveur -> clients : un joueur (ou un bot) quitte la partie.
@rpc("authority", "call_remote", "reliable")
func _player_left(id: int) -> void:
	players.erase(id)
	remote_left.emit(id)
	lobby_changed.emit()


## Serveur : change d'état (idle, reserved, in_progress, ending) et prévient.
func set_status(status: String) -> void:
	if not _serving or status == server_status:
		return
	server_status = status
	log_line("SERVEUR : état %s" % status)
	_send_lobby()


## Serveur : renvoie tous les joueurs au menu avec un message, puis coupe leur
## connexion (fin d'une partie réservée par un groupe : le serveur redevient libre).
func close_all(reason: String) -> void:
	if not _serving:
		return
	log_line("SERVEUR : déconnexion de tous les joueurs (%s)" % reason)
	_closing.rpc(reason)
	await get_tree().create_timer(0.5).timeout
	if _peer:
		for id in multiplayer.get_peers():
			_peer.disconnect_peer(id)
			# Retirés tout de suite : rien ne doit plus leur être envoyé pendant
			# que la déconnexion se termine (le départ est déjà compté).
			players.erase(id)
	leader_id = 0


var _close_reason := ""


## Serveur -> clients : la connexion va être coupée, voici pourquoi.
@rpc("authority", "call_remote", "reliable")
func _closing(reason: String) -> void:
	_close_reason = reason


## Serveur : fin de partie, retour au salon. Les bots sont retirés.
func back_to_lobby() -> void:
	if not _serving:
		return
	in_match = false
	for id in players.keys():
		if is_bot(id):
			players.erase(id)
	server_status = "idle"
	log_line("SERVEUR : retour au salon")
	lobby_changed.emit()
	_send_lobby()


# =========================================================================== en partie

func _process(delta: float) -> void:
	if is_connecting():
		_connect_elapsed += delta
		if _connect_elapsed > CONNECT_TIMEOUT:
			_fail_connection()
		return
	if _serving:
		for id in _unidentified.keys():
			_unidentified[id] += delta
			if _unidentified[id] > CONNECT_TIMEOUT:
				log_line("SERVEUR : pair %d coupé (pas de présentation)" % id)
				_unidentified.erase(id)
				_peer.disconnect_peer(id)
	if not online or not in_match or _last_state.is_empty():
		return
	_state_timer -= delta
	if _state_timer <= 0.0:
		_state_timer = 1.0 / STATE_HZ
		if _serving:
			_states.rpc(_last_state)
		else:
			_state.rpc_id(1, _last_state)


## Appelé par la scène de jeu à chaque image : le client donne l'état de son
## joueur, le serveur celui de tous les personnages (bots et joueurs).
## Clés = identifiants (pair pour les joueurs, négatif pour les bots).
func publish_state(states: Dictionary) -> void:
	_last_state = states


## Client -> serveur : état de mon joueur. Envoi NON fiable : si un paquet se
## perd, le suivant (50 ms plus tard) le remplace, inutile de le retransmettre.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _state(states: Dictionary) -> void:
	if not _serving:
		return
	var id := multiplayer.get_remote_sender_id()
	if states.has(id) and players.has(id):
		remote_states.emit(id, {id: states[id]})   # un client ne parle que pour lui


## Serveur -> clients : états de tous les personnages.
@rpc("authority", "call_remote", "unreliable_ordered")
func _states(states: Dictionary) -> void:
	remote_states.emit(1, states)


## Le tireur signale un impact. Seul le serveur décide s'il compte et combien il fait.
## `hit_offset` = point touché moins la position de la cible (vu par le tireur) :
## il sert à trouver la zone (tête / corps). `shooter_id` sert au serveur quand ce
## sont ses bots qui tirent ; un client est toujours le tireur de ses propres impacts.
func hit(target_id: int, hit_offset: Vector3, weapon: String, shooter_id: int) -> void:
	if not online or not in_match:
		return
	if _serving:
		_resolve_hit(target_id, shooter_id, hit_offset, weapon)
	else:
		_hit.rpc_id(1, target_id, hit_offset, weapon)


@rpc("any_peer", "call_remote", "reliable")
func _hit(target_id: int, hit_offset: Vector3, weapon: String) -> void:
	var shooter := multiplayer.get_remote_sender_id()
	if _serving and players.has(shooter):
		_resolve_hit(target_id, shooter, hit_offset, weapon)


func _resolve_hit(target_id: int, shooter_id: int, hit_offset: Vector3, weapon: String) -> void:
	if _serving and in_match and hit_resolver.is_valid():
		hit_resolver.call(target_id, shooter_id, hit_offset, weapon)


## Serveur -> cible et tireur : un tir validé (indicateur de provenance pour la
## cible, confirmation du tir à la tête pour le tireur).
func send_hit(target_id: int, shooter_id: int, damage: int, headshot: bool) -> void:
	for id in [target_id, shooter_id]:
		if id > 1 and players.has(id):
			push_hit.rpc_id(id, target_id, shooter_id, damage, headshot)


@rpc("authority", "call_remote", "reliable")
func push_hit(target_id: int, shooter_id: int, damage: int, headshot: bool) -> void:
	hit_landed.emit(target_id, shooter_id, damage, headshot)


## Serveur -> tous : nouvelle valeur de vie d'un joueur.
@rpc("authority", "call_local", "reliable")
func push_health(peer_id: int, health: int, max_health: int) -> void:
	health_updated.emit(peer_id, health, max_health)


## Serveur -> tous : élimination.
@rpc("authority", "call_local", "reliable")
func push_death(victim_id: int, killer_id: int, weapon: String, headshot: bool) -> void:
	if players.has(victim_id):
		players[victim_id].deaths += 1
	if players.has(killer_id) and killer_id != victim_id:
		players[killer_id].kills += 1
	player_died.emit(victim_id, killer_id, weapon, headshot)
	lobby_changed.emit()


## Serveur -> tous : réapparition (position et classe décidées par le serveur).
@rpc("authority", "call_local", "reliable")
func push_respawn(peer_id: int, position: Vector3, yaw: float, class_id: String) -> void:
	if players.has(peer_id):
		players[peer_id].class_id = class_id
	player_respawned.emit(peer_id, position, yaw, class_id)


## Serveur -> tous : fin de partie avec le classement.
@rpc("authority", "call_local", "reliable")
func push_match_over(rows: Array) -> void:
	in_match = false
	if _serving:
		server_status = "ending"
	match_over.emit(rows)


# =========================================================================== adresses

## Adresses IPv4 utiles de cette machine, les plus probables en premier.
##
## Un PC en expose souvent une dizaine (Wi-Fi, Ethernet, Docker, WSL, VirtualBox,
## Hyper-V, cartes sans adresse valide…). On écarte les interfaces virtuelles et on
## garde celles qu'un joueur peut vraiment utiliser, dans cet ordre :
##   1. Tailscale / ZeroTier (100.x)  : réseau privé, marche depuis n'importe où
##   2. réseau local classique (192.168.x)
##   3. autres réseaux privés (10.x, 172.16-31.x)
static func local_addresses(limit := 4) -> Array:
	var ranked := []
	for interface in IP.get_local_interfaces():
		if _is_virtual_interface(str(interface.get("name", "")) + " " + str(interface.get("friendly", ""))):
			continue
		for address in interface.get("addresses", []):
			if address.contains(":") or address.begins_with("127."):
				continue
			if address.begins_with("169.254."):
				continue                                  # adresse auto-attribuée : inutilisable
			var rank := 3
			if address.begins_with("100."):
				rank = 0                                  # Tailscale / ZeroTier
			elif address.begins_with("192.168."):
				rank = 1
			elif address.begins_with("10."):
				rank = 2
			ranked.append([rank, address])
	ranked.sort_custom(func(a, b): return a[0] < b[0])
	var result := []
	for entry in ranked:
		if not result.has(entry[1]):
			result.append(entry[1])
	return result.slice(0, limit)


## Interfaces des machines virtuelles et conteneurs : injoignables par les autres PC.
const VIRTUAL_INTERFACES := ["docker", "br-", "veth", "virbr", "vboxnet", "vmnet", "virtualbox",
	"vmware", "hyper-v", "wsl", "vethernet", "lxc", "lxd", "podman", "cni"]


static func _is_virtual_interface(names: String) -> bool:
	var lower := names.to_lower()
	for prefix in VIRTUAL_INTERFACES:
		if lower.begins_with(prefix) or lower.contains(" " + prefix) or lower.contains("(" + prefix):
			return true
	return false
