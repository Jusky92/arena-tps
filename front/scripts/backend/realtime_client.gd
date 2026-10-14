class_name RealtimeClient
extends Node
## Connexion WebSocket au service Real-time (backend/services/realtime/PROTOCOL.md) :
## présence des amis, notifications (demandes d'ami, invitations, groupe prêt à
## jouer, niveaux…). Un seul socket par session.
##
##   ouverture  -> {"type": "auth", "token"}  (dans les 5 s ; de nouveau après chaque
##                 rafraîchissement du jeton, voir update_token)
##   toutes les 20 s -> {"type": "heartbeat"}
##   coupure    -> reconnexion automatique, délai croissant (1, 2, 4… 30 s)
##
## Codes de fermeture : 4001 = jeton refusé (on demande un nouveau jeton puis on se
## reconnecte), 4001 « session_revoked » et 4003 (compte supprimé) = session perdue.

signal message(data: Dictionary)
## Le socket est authentifié (premier « hello ») ou vient de tomber.
signal status_changed(connected: bool)
## Le jeton a été refusé : il faut le rafraîchir (puis appeler update_token).
signal token_rejected
## Plus de reconnexion possible : session révoquée ou compte supprimé.
signal session_ended(reason: String)

const MAX_RECONNECT_DELAY := 30.0

var _url := ""
var _token := ""
var _ws: WebSocketPeer
var _was_open := false
var _connected := false
var _closing := false
var _heartbeat_interval := 20.0
var _heartbeat_left := 0.0
var _reconnect_delay := 1.0
var _reconnect_left := -1.0


func open(url: String, token: String) -> void:
	_url = url
	_token = token
	_closing = false
	_reconnect_delay = 1.0
	_connect()


## Nouveau jeton (après POST /auth/refresh) : renvoyé au service s'il est connecté.
func update_token(token: String) -> void:
	_token = token
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_send({"type": "auth", "token": _token})
	elif _ws == null and _reconnect_left < 0.0 and not _closing:
		_connect()                # fermé après un 4001 : on revient avec le nouveau jeton


func close() -> void:
	_closing = true
	_reconnect_left = -1.0
	if _ws:
		_ws.close(1000, "logout")
	_set_connected(false)


func is_connected_to_service() -> bool:
	return _connected


func send(data: Dictionary) -> void:
	if _connected:
		_send(data)


func _connect() -> void:
	_ws = WebSocketPeer.new()
	_was_open = false
	_reconnect_left = -1.0
	var err := _ws.connect_to_url(_url)
	if err != OK:
		_schedule_reconnect()


func _process(delta: float) -> void:
	if _reconnect_left >= 0.0:
		_reconnect_left -= delta
		if _reconnect_left < 0.0:
			_connect()
		return
	if _ws == null:
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _was_open:
				_was_open = true
				_send({"type": "auth", "token": _token})
			while _ws.get_available_packet_count() > 0:
				var parsed: Variant = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
				if parsed is Dictionary:
					_handle(parsed)
			if _connected:
				_heartbeat_left -= delta
				if _heartbeat_left <= 0.0:
					_heartbeat_left = _heartbeat_interval
					_send({"type": "heartbeat"})
		WebSocketPeer.STATE_CLOSED:
			var code := _ws.get_close_code()
			var reason := _ws.get_close_reason()
			_ws = null
			_set_connected(false)
			if _closing:
				return
			if code == 4003 or (code == 4001 and reason == "session_revoked"):
				_closing = true
				session_ended.emit("Ta session a été fermée (mot de passe changé ou compte supprimé). Reconnecte-toi."
					if code == 4001 else "Ce compte a été supprimé.")
			elif code == 4001:
				token_rejected.emit()     # update_token() relancera la connexion
			else:
				_schedule_reconnect()


func _handle(data: Dictionary) -> void:
	if data.get("type") == "hello":
		_heartbeat_interval = float(data.get("heartbeat_interval", 20))
		_heartbeat_left = _heartbeat_interval
		_reconnect_delay = 1.0
		_set_connected(true)
	message.emit(data)


func _schedule_reconnect() -> void:
	_reconnect_left = _reconnect_delay
	_reconnect_delay = minf(_reconnect_delay * 2.0, MAX_RECONNECT_DELAY)


func _send(data: Dictionary) -> void:
	_ws.send_text(JSON.stringify(data))


func _set_connected(value: bool) -> void:
	if value != _connected:
		_connected = value
		status_changed.emit(value)
