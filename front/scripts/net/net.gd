extends Node
## Multijoueur en ligne (autoload "Net").
##
## Modèle retenu pour cette première version jouable à deux :
##
##   HÔTE (le PC de Julien)        = serveur ENet + joueur. On dit « serveur d'écoute ».
##   CLIENT (le PC d'Elian)        = client lourd qui se connecte par IP.
##
## Qui décide de quoi :
##   - chaque machine simule SON joueur (déplacement, saut, visée) et envoie son
##     état aux autres 20 fois par seconde : le jeu reste parfaitement réactif ;
##   - le tireur détecte ses impacts et envoie les dégâts : `hit()` ;
##   - l'HÔTE est seul juge du reste : points de vie, éliminations, score,
##     chronomètre, réapparitions. Il diffuse le résultat à tout le monde.
##
## C'est le compromis habituel des petits jeux de tir en LAN : simple, nerveux,
## suffisant à deux. Un serveur de jeu dédié (celui prévu avec Elian) déplacerait
## toute la simulation côté serveur pour empêcher la triche ; la séparation
## entrées / simulation (PlayerCommands) est déjà prête pour ça.
##
## Protocole (toutes les fonctions marquées @rpc) :
##   client -> hôte    hello, set_class, state, hit, request_respawn
##   hôte   -> clients welcome, lobby, start_match, state, health, died, score, match_over
##
## Port par défaut : 24567 (UDP). Voir docs/RESEAU.md pour l'ouverture du port.

signal lobby_changed                      ## la liste des joueurs a changé
signal joined                             ## client : l'hôte nous a acceptés dans le salon
signal match_starting                     ## l'hôte a lancé la partie
signal connection_failed(reason: String)
signal disconnected(reason: String)
signal remote_states(sender_id: int, states: Dictionary)
signal remote_spawned(peer_id: int, info: Dictionary)
signal remote_left(peer_id: int)
signal health_updated(peer_id: int, health: int, max_health: int)
signal player_died(victim_id: int, killer_id: int, weapon: String)
signal player_respawned(peer_id: int, position: Vector3, yaw: float, class_id: String)
signal match_over(rows: Array)

const DEFAULT_PORT := 24567
const MAX_PLAYERS := 8
const STATE_HZ := 20.0                    ## envois d'état par seconde
## Au-delà de ce délai sans réponse de l'hôte, on abandonne avec un diagnostic.
const CONNECT_TIMEOUT := 6.0
## Journal réseau, utile pour comprendre un échec de connexion.
## Windows : %APPDATA%\Godot\app_userdata\Arena TPS\reseau.log
## Linux   : ~/.local/share/godot/app_userdata/Arena TPS/reseau.log
const LOG_PATH := "user://reseau.log"

## true dès qu'on est en ligne (hôte ou client).
var online := false
## true si cette machine héberge la partie.
var hosting := false
## Pseudo local.
var pseudo := "Joueur"
## Joueurs connectés : id de pair -> {name, class_id, kills, deaths, ready, ping}
var players := {}
## Réglages de la partie, choisis par l'hôte.
var settings := {"bots": 2, "duration": 180.0}
## true quand la partie est lancée (on n'accepte plus de nouveaux joueurs).
var in_match := false

var _peer: ENetMultiplayerPeer
var _state_timer := 0.0
var _last_state := {}
## Client : temps écoulé depuis la demande de connexion (-1 = pas en cours).
var _connect_elapsed := -1.0
var _target := ""


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func my_id() -> int:
	return multiplayer.get_unique_id() if online else 1


func is_host() -> bool:
	return hosting


## Ouvre une partie sur cette machine. Renvoie "" si tout va bien, sinon l'erreur.
func host(player_name: String, port := DEFAULT_PORT, bots := 2, duration := 180.0) -> String:
	leave()
	log_line("HÔTE : ouverture du serveur sur le port UDP %d (version %s)" % [port, Backend.BUILD_VERSION])
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, MAX_PLAYERS)
	if err != OK and err != ERR_ALREADY_IN_USE:
		# Certains Linux ont l'IPv6 désactivé : on réessaie en IPv4 seul.
		log_line("HÔTE : échec en IPv4+IPv6 (code %d), nouvel essai en IPv4 seul" % err)
		_peer = ENetMultiplayerPeer.new()
		_peer.set_bind_ip("0.0.0.0")
		err = _peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		_peer = null
		log_line("HÔTE : impossible d'ouvrir le serveur (code %d)" % err)
		if err == ERR_ALREADY_IN_USE:
			return "Le port %d est déjà utilisé sur ce PC (le jeu est peut-être ouvert deux fois)." % port
		return "Impossible d'ouvrir le serveur (code %d)." % err
	log_line("HÔTE : en écoute. Adresses à donner : %s" % ", ".join(local_addresses()))
	multiplayer.multiplayer_peer = _peer
	online = true
	hosting = true
	in_match = false
	pseudo = player_name
	settings = {"bots": bots, "duration": duration}
	players = {1: _new_player(player_name, GameState.selected_class.resource_path)}
	lobby_changed.emit()
	return ""


## Rejoint une partie. `address` = IP ou nom d'hôte de l'hôte.
func join(address: String, player_name: String, port := DEFAULT_PORT) -> String:
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
	hosting = false
	in_match = false
	pseudo = player_name
	players = {}
	_connect_elapsed = 0.0
	return ""


## true pendant qu'un client attend la réponse de l'hôte.
func is_connecting() -> bool:
	return _connect_elapsed >= 0.0


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


## Ferme la connexion (retour au menu, ou déconnexion subie).
func leave() -> void:
	_connect_elapsed = -1.0
	if _peer:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = null
	online = false
	hosting = false
	in_match = false
	players = {}
	_last_state = {}


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


func _new_player(name: String, class_id: String) -> Dictionary:
	return {"name": name, "class_id": class_id, "kills": 0, "deaths": 0, "bot": false}


## true si cet identifiant est un bot de l'hôte.
func is_bot(id: int) -> bool:
	return id < 0


## true si cette machine fait jouer ce personnage (et doit donc envoyer son état).
func controls(id: int) -> bool:
	return id == my_id() or (hosting and is_bot(id))


# =========================================================================== connexion

func _on_peer_connected(id: int) -> void:
	# Côté hôte uniquement : le client va se présenter avec `hello`.
	if hosting:
		log_line("HÔTE : un joueur se connecte (id %d)" % id)
	if hosting and in_match:
		# Partie déjà lancée : on refuse poliment.
		_refuse.rpc_id(id, "La partie a déjà commencé.")


func _on_peer_disconnected(id: int) -> void:
	log_line("Joueur %d déconnecté" % id)
	players.erase(id)
	remote_left.emit(id)
	lobby_changed.emit()
	if hosting:
		_lobby.rpc(players, settings)


func _on_connected() -> void:
	# Le réseau passe : on se présente à l'hôte (pseudo, classe, version du jeu).
	log_line("CLIENT : connexion ENet établie avec %s, présentation à l'hôte" % _target)
	_hello.rpc_id(1, pseudo, GameState.selected_class.resource_path, Backend.BUILD_VERSION)


func _on_connection_failed() -> void:
	_fail_connection()


func _on_server_disconnected() -> void:
	log_line("Connexion avec l'hôte perdue")
	var was_connecting := is_connecting()
	leave()
	if was_connecting:
		connection_failed.emit("L'hôte a coupé la connexion avant d'accepter (versions différentes ?).")
	else:
		disconnected.emit("L'hôte a fermé la partie.")


## Aucune réponse de l'hôte : on explique les causes possibles, dans l'ordre.
func _fail_connection() -> void:
	var target := _target
	log_line("CLIENT : aucune réponse de %s après %.0f s" % [target, CONNECT_TIMEOUT])
	leave()
	connection_failed.emit(
		("Aucune réponse de %s.\n" % target)
		+ "1. L'hôte doit déjà être dans le salon (HÉBERGER).\n"
		+ "2. L'adresse doit être celle affichée dans SON salon.\n"
		+ ("3. Son pare-feu doit autoriser le port UDP %d (voir docs/RESEAU.md)." % DEFAULT_PORT))


# =========================================================================== salon

## Client -> hôte : je me présente.
@rpc("any_peer", "call_remote", "reliable")
func _hello(name: String, class_id: String, version: String) -> void:
	if not hosting:
		return
	var id := multiplayer.get_remote_sender_id()
	log_line("HÔTE : %s se présente (version %s)" % [name, version])
	if version != Backend.BUILD_VERSION:
		_refuse.rpc_id(id, "Versions différentes : l'hôte a la %s, toi la %s. Réexportez le jeu depuis le même code." % [Backend.BUILD_VERSION, version])
		return
	if players.size() >= MAX_PLAYERS:
		_refuse.rpc_id(id, "La partie est pleine (%d joueurs)." % MAX_PLAYERS)
		return
	players[id] = _new_player(name.left(16), class_id)
	lobby_changed.emit()
	_lobby.rpc(players, settings)


## Hôte -> clients : état du salon.
@rpc("authority", "call_remote", "reliable")
func _lobby(list: Dictionary, host_settings: Dictionary) -> void:
	players = list
	settings = host_settings
	if is_connecting():
		_connect_elapsed = -1.0
		log_line("CLIENT : accepté dans le salon (%d joueur(s))" % players.size())
		joined.emit()
	lobby_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _refuse(reason: String) -> void:
	log_line("Refusé par l'hôte : " + reason)
	leave()
	connection_failed.emit(reason)


## Changement de classe depuis le salon ou le menu pause.
func set_class(class_id: String) -> void:
	if not online:
		return
	if hosting:
		players[1].class_id = class_id
		lobby_changed.emit()
		_lobby.rpc(players, settings)
	else:
		_set_class.rpc_id(1, class_id)


@rpc("any_peer", "call_remote", "reliable")
func _set_class(class_id: String) -> void:
	if not hosting:
		return
	var id := multiplayer.get_remote_sender_id()
	if players.has(id):
		players[id].class_id = class_id
		lobby_changed.emit()
		_lobby.rpc(players, settings)


## Hôte : règle le nombre de bots et la durée, puis prévient les clients.
func update_settings(bots: int, duration: float) -> void:
	if not hosting:
		return
	settings = {"bots": bots, "duration": duration}
	lobby_changed.emit()
	_lobby.rpc(players, settings)


## Noms des bots ajoutés par l'hôte pour compléter la partie.
const BOT_NAMES := ["NeoByte", "Gl1tch", "V0LT", "Cipher", "Kairo", "Nova", "Raven", "Hexa"]


## Hôte : lance la partie pour tout le monde.
## Les bots entrent dans la même liste que les joueurs, avec un identifiant négatif :
## tout le monde les affiche, mais seul l'hôte les fait jouer.
func start_match() -> void:
	if not hosting:
		return
	for id in players.keys():
		if id < 0:
			players.erase(id)
	var bots: int = clampi(settings.get("bots", 0), 0, MAX_PLAYERS - players.size())
	for i in bots:
		var cls: ClassData = GameState.CLASSES[i % GameState.CLASSES.size()]
		players[-(i + 1)] = _new_player(BOT_NAMES[i % BOT_NAMES.size()], cls.resource_path)
		players[-(i + 1)]["bot"] = true
	in_match = true
	_start_match.rpc(players, settings)
	match_starting.emit()


@rpc("authority", "call_remote", "reliable")
func _start_match(list: Dictionary, host_settings: Dictionary) -> void:
	players = list
	settings = host_settings
	in_match = true
	match_starting.emit()


# =========================================================================== en partie

func _process(delta: float) -> void:
	if is_connecting():
		_connect_elapsed += delta
		if _connect_elapsed > CONNECT_TIMEOUT:
			_fail_connection()
		return
	if not online or not in_match or _last_state.is_empty():
		return
	_state_timer -= delta
	if _state_timer <= 0.0:
		_state_timer = 1.0 / STATE_HZ
		_state.rpc(_last_state)


## Appelé par la scène de jeu à chaque image : états des personnages que cette
## machine fait jouer (son joueur, plus les bots si c'est l'hôte).
## Clés = identifiants (peer pour les joueurs, négatif pour les bots).
func publish_state(states: Dictionary) -> void:
	_last_state = states


## États reçus — envoi NON fiable : si un paquet se perd, le suivant (20 ms plus
## tard) le remplace, inutile de le retransmettre.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _state(states: Dictionary) -> void:
	remote_states.emit(multiplayer.get_remote_sender_id(), states)


## Le tireur signale un impact. Seul l'hôte applique les dégâts.
func hit(target_id: int, damage: int, weapon: String) -> void:
	if not online or not in_match:
		return
	if hosting:
		_apply_damage(target_id, damage, 1, weapon)
	else:
		_hit.rpc_id(1, target_id, damage, weapon)


@rpc("any_peer", "call_remote", "reliable")
func _hit(target_id: int, damage: int, weapon: String) -> void:
	if not hosting:
		return
	_apply_damage(target_id, damage, multiplayer.get_remote_sender_id(), weapon)


## Côté hôte : applique les dégâts et diffuse le résultat.
## `health_of` est rempli par la scène de jeu (voir game.gd).
var health_provider: Callable = Callable()


func _apply_damage(target_id: int, damage: int, shooter_id: int, weapon: String) -> void:
	if not hosting or not health_provider.is_valid():
		return
	health_provider.call(target_id, damage, shooter_id, weapon)


## Hôte -> tous : nouvelle valeur de vie d'un joueur.
@rpc("authority", "call_local", "reliable")
func push_health(peer_id: int, health: int, max_health: int) -> void:
	health_updated.emit(peer_id, health, max_health)


## Hôte -> tous : élimination.
@rpc("authority", "call_local", "reliable")
func push_death(victim_id: int, killer_id: int, weapon: String) -> void:
	if players.has(victim_id):
		players[victim_id].deaths += 1
	if players.has(killer_id) and killer_id != victim_id:
		players[killer_id].kills += 1
	player_died.emit(victim_id, killer_id, weapon)
	lobby_changed.emit()


## Hôte -> tous : réapparition (position décidée par l'hôte).
@rpc("authority", "call_local", "reliable")
func push_respawn(peer_id: int, position: Vector3, yaw: float, class_id: String) -> void:
	if players.has(peer_id):
		players[peer_id].class_id = class_id
	player_respawned.emit(peer_id, position, yaw, class_id)


## Hôte -> tous : fin de partie avec le classement.
@rpc("authority", "call_local", "reliable")
func push_match_over(rows: Array) -> void:
	in_match = false
	match_over.emit(rows)


## Client -> hôte : je suis mort, je demande à réapparaître (avec ma classe).
func request_respawn(class_id: String) -> void:
	if not online:
		return
	if hosting:
		respawn_requested.emit(1, class_id)
	else:
		_request_respawn.rpc_id(1, class_id)


signal respawn_requested(peer_id: int, class_id: String)


@rpc("any_peer", "call_remote", "reliable")
func _request_respawn(class_id: String) -> void:
	if hosting:
		respawn_requested.emit(multiplayer.get_remote_sender_id(), class_id)


# =========================================================================== adresses

## Adresses IPv4 utiles de cette machine, les plus probables en premier.
##
## Un PC Windows en expose souvent une dizaine (Wi-Fi, Ethernet, WSL, VirtualBox,
## Hyper-V, cartes sans adresse valide…). On ne garde que celles qu'un camarade
## peut vraiment utiliser, dans cet ordre :
##   1. Tailscale / ZeroTier (100.x)  : réseau privé, marche depuis n'importe où
##   2. réseau local classique (192.168.x)
##   3. autres réseaux privés (10.x, 172.16-31.x)
static func local_addresses(limit := 4) -> Array:
	var ranked := []
	for address in IP.get_local_addresses():
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
		result.append(entry[1])
	return result.slice(0, limit)
