class_name ServerListLink
extends BackendLink
## Lien avec le vrai back : la Server List (voir backend/services/serverlist).
##
##   enregistrement   POST /servers               secret partagé GAME_SERVER_SECRET
##                                                -> server_id + server_token
##   battement        PUT /servers/{id}/heartbeat  toutes les 5 s (server_main.gd)
##                                                -> la réponse dit si un groupe a réservé le serveur
##   tickets          POST /tickets/verify         à chaque joueur qui se présente
##   évènements       POST /servers/{id}/player-match, /servers/{id}/match-finished
##   arrêt            DELETE /servers/{id}
##
## Tous les appels après l'enregistrement portent le server_token. Si la Server
## List ne connaît plus le serveur (404 server_not_found, par exemple après 15 s
## sans battement), il s'enregistre de nouveau.

## Essais pour envoyer un évènement, et pause avant chaque nouvel essai (s).
const EVENT_RETRIES := [0.0, 2.0, 5.0]

var _api: ApiClient
var _secret := ""
var _token := ""
var _info := {}
var _heartbeat_busy := false
## État donné par la Server List au dernier battement (idle, reserved, in_progress, ending).
var _remote_status := "idle"


func _init(serverlist_url: String, game_server_secret: String) -> void:
	_api = ApiClient.new()
	_api.base_url = serverlist_url.trim_suffix("/")
	_secret = game_server_secret


func _ready() -> void:
	add_child(_api)


func start(info: Dictionary) -> String:
	_info = info
	return await _register()


func _register() -> String:
	var body := {
		"name": _info.get("name", "Arena TPS"),
		"address": _info.get("address", ""),
		"port": _info.get("port", Net.DEFAULT_PORT),
		"region": _info.get("region", "eu"),
		"map": _info.get("map", MatchRules.MAP_ID),
		"max_players": _info.get("max_players", Net.max_players),
		"build_version": _info.get("build_version", Backend.BUILD_VERSION),
	}
	var r := await _api.request(HTTPClient.METHOD_POST, "/servers", body, ApiClient.bearer(_secret))
	if not r.ok:
		if r.error == "invalid_secret":
			return "La Server List refuse GAME_SERVER_SECRET : il doit être le même que dans le .env du back."
		return "Enregistrement auprès de la Server List impossible (%s) : %s" % [_api.base_url, r.message]
	server_id = r.data.server_id
	_token = r.data.server_token
	_remote_status = "idle"
	reserved_slots = 0
	Net.log_line("SERVER LIST : enregistré (id %s) à %s, adresse donnée aux joueurs %s:%d"
		% [server_id, _api.base_url, body.address, body.port])
	return ""


func report(status: String, players: int, map: String) -> void:
	if server_id.is_empty() or _heartbeat_busy:
		return
	_heartbeat_busy = true
	# Seule une allocation réserve un serveur : localement « reserved », il
	# continue d'annoncer « idle » et la Server List garde la réservation.
	var sent := "idle" if status == "reserved" else status
	var body := {"status": sent, "players": players, "map": map}
	var r := await _api.request(HTTPClient.METHOD_PUT, "/servers/%s/heartbeat" % server_id, body, ApiClient.bearer(_token))
	_heartbeat_busy = false
	if not r.ok:
		if r.error == "server_not_found":
			Net.log_line("SERVER LIST : serveur oublié par la Server List, nouvel enregistrement")
			var error := await _register()
			if not error.is_empty():
				Net.log_line("SERVER LIST : " + error)
		else:
			Net.log_line("SERVER LIST : battement de cœur refusé (%s)" % r.message)
		return
	var data: Dictionary = r.data
	reserved_slots = int(data.get("reserved_slots", 0))
	var remote: String = data.get("status", sent)
	if remote == "reserved" and _remote_status != "reserved":
		party_id = data.get("party_id")
		var received: Variant = data.get("match_settings")
		match_settings = received if received is Dictionary else {}
		var leader: Variant = data.get("leader_id")
		leader_user_id = leader if leader is String else ""
		Net.log_line("SERVER LIST : réservé pour le groupe %s (%d place(s), chef %s), réglages %s"
			% [party_id, reserved_slots, leader_user_id, match_settings])
		reserved.emit(str(party_id))
	elif remote == "idle" and _remote_status == "reserved":
		Net.log_line("SERVER LIST : réservation expirée, serveur de nouveau libre")
		party_id = null
		match_settings = {}
		leader_user_id = ""
		reservation_ended.emit()
	_remote_status = remote


func verify(ticket: String, claimed_user_id: String) -> String:
	if ticket.is_empty() or server_id.is_empty():
		return ""
	var body := {"ticket": ticket, "server_id": server_id}
	var r := await _api.request(HTTPClient.METHOD_POST, "/tickets/verify", body, ApiClient.bearer(_token))
	if not r.ok:
		Net.log_line("SERVER LIST : ticket refusé (%s)" % r.message)
		return ""
	var user_id: String = r.data.get("user_id", "")
	if user_id != claimed_user_id:
		Net.log_line("SERVER LIST : ticket de %s présenté par %s" % [user_id, claimed_user_id])
	return user_id


func player_match(user_id: String, action: String) -> void:
	_send_event("/servers/%s/player-match" % server_id, {"user_id": user_id, "action": action}, "player.match " + action)


func match_finished(result: Dictionary) -> void:
	_send_event("/servers/%s/match-finished" % server_id, result, "match.finished")


func stop() -> void:
	if server_id.is_empty():
		return
	Net.log_line("SERVER LIST : désenregistrement")
	_api.request(HTTPClient.METHOD_DELETE, "/servers/%s" % server_id, null, ApiClient.bearer(_token))


## Envoie un évènement, avec quelques nouveaux essais si le back ne répond pas.
## Un refus (4xx) n'est pas réessayé : la même requête serait refusée de nouveau.
func _send_event(path: String, body: Dictionary, label: String) -> void:
	for pause in EVENT_RETRIES:
		if pause > 0.0:
			await get_tree().create_timer(pause).timeout
		var r := await _api.request(HTTPClient.METHOD_POST, path, body, ApiClient.bearer(_token))
		if r.ok:
			Net.log_line("SERVER LIST : %s envoyé" % label)
			return
		Net.log_line("SERVER LIST : échec de l'envoi de %s (%s)" % [label, r.message])
		if r.status >= 400 and r.status < 500:
			return
	Net.log_line("SERVER LIST : %s abandonné après %d essais" % [label, EVENT_RETRIES.size()])
