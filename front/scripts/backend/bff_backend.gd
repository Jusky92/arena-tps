class_name BffBackend
extends Node
## Le vrai back, vu du jeu : HTTP vers le BFF et WebSocket vers Real-time.
## Utilisé par la façade Backend (backend.gd), qui garde l'état partagé.
##
## Session : jeton d'accès (15 min) + jeton de rafraîchissement, en mémoire
## seulement. Le jeton d'accès est renouvelé 60 s avant son expiration, ou dès
## qu'une requête est refusée (401), puis renvoyé au service temps réel.

const GET := HTTPClient.METHOD_GET
const POST := HTTPClient.METHOD_POST
const PUT := HTTPClient.METHOD_PUT
const DELETE := HTTPClient.METHOD_DELETE
const TOKEN_ERRORS := ["invalid_token", "token_expired", "not_authenticated"]
const PSEUDO_REGEX := "^[A-Za-z0-9_]{3,20}$"

var b: Node                      # la façade (autoload Backend)
var _api: ApiClient
var _rt: RealtimeClient
var _access := ""
var _refresh := ""
var _refresh_timer: Timer
var _refreshing := false
## Présence des amis : user_id -> {status, activity}.
var _presence := {}
## Version du dernier état de groupe appliqué (party.updated peut arriver dans le désordre).
var _party_version := -1

signal _refresh_done(ok: bool)


func setup(facade: Node) -> void:
	b = facade
	_api = ApiClient.new()
	_api.base_url = "http://%s:%d" % [b.host, b.BFF_PORT]
	add_child(_api)
	_rt = RealtimeClient.new()
	add_child(_rt)
	_rt.message.connect(_on_realtime)
	_rt.status_changed.connect(func(_c: bool) -> void: b.services_changed.emit())
	_rt.token_rejected.connect(_on_token_rejected)
	_rt.session_ended.connect(func(reason: String) -> void: b._lose_session(reason))
	_refresh_timer = Timer.new()
	_refresh_timer.one_shot = true
	_refresh_timer.timeout.connect(_refresh_tokens)
	add_child(_refresh_timer)


func services_online() -> bool:
	return _rt.is_connected_to_service()


# =========================================================================== requêtes

## Requête au BFF avec le jeton du joueur ; un jeton expiré est renouvelé une fois.
func _call(method: int, path: String, body: Variant = null) -> Dictionary:
	var r := await _api.request(method, path, body, ApiClient.bearer(_access))
	if r.status == 401 and r.error in TOKEN_ERRORS and not _refresh.is_empty():
		if await _refresh_tokens():
			r = await _api.request(method, path, body, ApiClient.bearer(_access))
		else:
			b._lose_session("Ta session a expiré. Reconnecte-toi.")
	return r


## Requête sans jeton (inscription, connexion…).
func _public(method: int, path: String, body: Variant = null) -> Dictionary:
	return await _api.request(method, path, body)


static func _err(message: String, code := "") -> Dictionary:
	return {"ok": false, "error": code, "message": message}


# =========================================================================== compte

func register(pseudo: String, email: String, password: String) -> Dictionary:
	var regex := RegEx.create_from_string(PSEUDO_REGEX)
	if regex.search(pseudo) == null:
		return _err("Le pseudo doit faire de 3 à 20 caractères : lettres, chiffres ou _ (sans espace ni accent).")
	if not email.contains("@") or not email.get_slice("@", 1).contains("."):
		return _err("Adresse e-mail invalide.")
	if password.length() < 8:
		return _err("Le mot de passe doit faire au moins 8 caractères.")
	return await _public(POST, "/auth/register", {"username": pseudo, "email": email, "password": password})


func verify_email(email: String, code: String) -> Dictionary:
	if not email.contains("@"):
		return _err("Saisis l'e-mail de ton compte.")
	if code.length() != 6 or not code.is_valid_int():
		return _err("Le code doit contenir 6 chiffres.")
	var r := await _public(POST, "/auth/verify-email", {"email": email, "code": code})
	if not r.ok:
		return r
	return await _open_session(r)


func resend_code(email: String) -> Dictionary:
	if not email.contains("@"):
		return _err("Saisis l'e-mail de ton compte.")
	var r := await _public(POST, "/auth/verify-email/resend", {"email": email})
	if r.ok:
		r.message = "Si ce compte attend sa vérification, un nouveau code a été envoyé."
	return r


## `identifier` : l'e-mail ou le pseudo du compte.
func login(identifier: String, password: String) -> Dictionary:
	if identifier.is_empty():
		return _err("Saisis ton e-mail ou ton pseudo.")
	var r := await _public(POST, "/auth/login", {"identifier": identifier, "password": password})
	if not r.ok:
		return r
	return await _open_session(r)


func request_password_reset(email: String) -> Dictionary:
	var r := await _public(POST, "/auth/password-reset/request", {"email": email})
	if r.ok:
		r.message = "Si un compte existe pour cette adresse, un code a été envoyé."
	return r


func confirm_password_reset(email: String, code: String, new_password: String) -> Dictionary:
	if code.length() != 6 or not code.is_valid_int():
		return _err("Le code doit contenir 6 chiffres.")
	if new_password.length() < 8:
		return _err("Le mot de passe doit faire au moins 8 caractères.")
	var r := await _public(POST, "/auth/password-reset/confirm", {"email": email, "code": code, "new_password": new_password})
	if r.ok:
		r.message = "Mot de passe changé. Connecte-toi avec le nouveau."
	return r


func logout() -> void:
	if not _refresh.is_empty():
		_public(POST, "/auth/logout", {"refresh_token": _refresh})   # sans attendre la réponse
	_access = ""
	_refresh = ""
	_presence = {}
	_party_version = -1
	_refresh_timer.stop()
	_rt.close()


## Jetons reçus (connexion ou vérification de l'e-mail) : on charge le compte et
## on ouvre le WebSocket.
func _open_session(tokens: Dictionary) -> Dictionary:
	_store_tokens(tokens.data)
	var me := await _call(GET, "/auth/me")
	if not me.ok:
		logout()
		return me
	b.user = {"user_id": me.data.user_id, "username": me.data.username, "email": me.data.email}
	b.party = {}
	b.invites = []
	_rt.open("ws://%s:%d/ws" % [b.host, b.REALTIME_PORT], _access)
	b.session_changed.emit()
	refresh_friends()
	return {"ok": true, "error": "", "message": ""}


func _store_tokens(data: Dictionary) -> void:
	_access = data.access_token
	_refresh = data.refresh_token
	_refresh_timer.start(maxf(float(data.get("expires_in", 900)) - 60.0, 10.0))


## Renouvelle les jetons. Plusieurs appels simultanés partagent le même renouvellement.
func _refresh_tokens() -> bool:
	if _refreshing:
		return await _refresh_done
	if _refresh.is_empty():
		return false
	_refreshing = true
	var r := await _public(POST, "/auth/refresh", {"refresh_token": _refresh})
	_refreshing = false
	if r.ok:
		_store_tokens(r.data)
		_rt.update_token(_access)
	elif r.status == 401:
		b._lose_session("Ta session a expiré. Reconnecte-toi.")
	_refresh_done.emit(r.ok)
	return r.ok


func _on_token_rejected() -> void:
	if await _refresh_tokens():
		_rt.update_token(_access)


# =========================================================================== profil et classement

func get_profile() -> Dictionary:
	var id: String = b.user_id()
	var stats := await _call(GET, "/players/%s/stats" % id)
	if not stats.ok:
		return stats
	var progression := await _call(GET, "/progression/%s" % id)
	if not progression.ok:
		return progression
	var s: Dictionary = stats.data
	var p: Dictionary = progression.data
	return {
		"ok": true, "username": b.username(), "level": int(p.level), "xp": int(p.xp),
		"xp_in_level": int(p.xp_in_level), "xp_to_next_level": maxi(int(p.xp_to_next_level), 1),
		"matches": int(s.matches_played), "wins": int(s.wins), "kills": int(s.kills),
		"deaths": int(s.deaths), "kd": float(s.kd_ratio), "achievements": p.achievements,
	}


func get_leaderboard(type: String, around: bool) -> Dictionary:
	var path := ("/leaderboards/%s/around/%s?radius=5" % [type, b.user_id()]) if around else ("/leaderboards/%s?limit=20" % type)
	var r := await _call(GET, path)
	if not r.ok:
		return r
	var entries := []
	for e in r.data.entries:
		entries.append({
			"rank": int(e.rank), "user_id": e.user_id, "value": int(e.value), "me": e.user_id == b.user_id(),
			"username": e.username if e.username != null else "(compte supprimé)",
		})
	return {"ok": true, "total_players": int(r.data.total_players), "player_rank": r.data.get("player_rank"), "entries": entries}


# =========================================================================== amis

func refresh_friends() -> Dictionary:
	var r := await _call(GET, "/friends")
	if not r.ok:
		return r
	var friends := []
	for f in r.data.friends:
		var presence: Dictionary = _presence.get(f.user_id, {})
		friends.append({
			"user_id": f.user_id, "username": _name(f), "status": presence.get("status", "offline"),
			"activity": presence.get("activity"),
		})
	friends.sort_custom(func(x, y): return _friend_order(x) < _friend_order(y))
	b.friends = friends
	b.incoming = r.data.incoming.map(func(q): return {"request_id": q.request_id, "user_id": q.user_id, "username": _name(q)})
	b.outgoing = r.data.outgoing.map(func(q): return {"request_id": q.request_id, "user_id": q.user_id, "username": _name(q)})
	b.friends_changed.emit()
	return r


static func _name(entry: Dictionary) -> String:
	return entry.username if entry.get("username") != null else "?"


## En partie d'abord, puis en ligne, puis hors ligne ; par nom à l'intérieur.
static func _friend_order(f: Dictionary) -> String:
	var rank := "0" if f.activity == "in_match" else ("1" if f.status == "online" else "2")
	return rank + f.username.to_lower()


func search_users(text: String) -> Dictionary:
	if text.is_empty():
		return _err("Tape une partie du pseudo.")
	var r := await _call(GET, "/auth/users/search?username=%s" % text.uri_encode())
	if not r.ok:
		return r
	var users: Array = r.data.users.filter(func(u): return u.user_id != b.user_id())
	return {"ok": true, "users": users}


func send_friend_request(target: String) -> Dictionary:
	var r := await _call(POST, "/friends/requests", {"user_id": target})
	if r.ok:
		r.message = "Vous êtes maintenant amis." if r.data.status == "accepted" else "Demande d'ami envoyée."
		refresh_friends()
	return r


func accept_friend_request(request_id: String) -> Dictionary:
	var r := await _call(POST, "/friends/requests/%s/accept" % request_id)
	refresh_friends()
	return r


func decline_friend_request(request_id: String) -> Dictionary:
	var r := await _call(POST, "/friends/requests/%s/decline" % request_id)
	refresh_friends()
	return r


func remove_friend(friend_id: String) -> Dictionary:
	var r := await _call(DELETE, "/friends/%s" % friend_id)
	refresh_friends()
	return r


# =========================================================================== groupe

func _ensure_party() -> Dictionary:
	if not b.party.is_empty():
		return {"ok": true}
	var r := await _call(POST, "/parties")
	if r.ok:
		_apply_party(r.data, true)
	return r


func create_party() -> Dictionary:
	if not b.party.is_empty():
		return _err("Tu es déjà dans un groupe.")
	return await _ensure_party()


func _apply_party(data: Dictionary, force := false) -> void:
	var version := int(data.get("version", 0))
	if not force and data.party_id == b.party.get("party_id") and version < _party_version:
		return
	_party_version = version
	var members := []
	for m in data.get("members", []):
		members.append({"user_id": m.user_id, "username": m.username if m.username != null else "?",
			"class_id": m.get("class_id") if m.get("class_id") != null else ""})
	b.party = {"party_id": data.party_id, "leader_id": data.leader_id, "status": data.status, "members": members}
	b.party_changed.emit()


func _reload_party(party_id: String) -> void:
	var r := await _call(GET, "/parties/%s" % party_id)
	if r.ok:
		_apply_party(r.data, true)
	elif r.error == "party_not_found" and b.party.get("party_id") == party_id:
		b.party = {}
		b.party_changed.emit()


func invite_to_party(friend_id: String) -> Dictionary:
	var created := await _ensure_party()
	if not created.ok:
		return created
	var r := await _call(POST, "/parties/%s/invite" % b.party.party_id, {"user_id": friend_id})
	if r.ok:
		r.message = "Invitation envoyée."
	return r


func accept_invite(invite_id: String) -> Dictionary:
	# Seul dans son groupe ? On le quitte pour rejoindre celui de l'ami.
	if not b.party.is_empty() and b.party.members.size() <= 1:
		await leave_party()
	var r := await _call(POST, "/invites/%s/accept" % invite_id)
	b.dismiss_invite(invite_id)
	if r.ok:
		_apply_party(r.data, true)
	return r


func leave_party() -> Dictionary:
	if b.party.is_empty():
		return {"ok": true}
	var r := await _call(POST, "/parties/%s/leave" % b.party.party_id)
	if r.ok or r.error == "party_not_found":
		b.party = {}
		b.party_changed.emit()
		r.ok = true
	return r


func kick_from_party(member_id: String) -> Dictionary:
	if b.party.is_empty():
		return _err("Tu n'as pas de groupe.")
	var r := await _call(POST, "/parties/%s/kick" % b.party.party_id, {"user_id": member_id})
	if r.ok:
		_reload_party(b.party.party_id)
	return r


func give_lead(member_id: String) -> Dictionary:
	if b.party.is_empty():
		return _err("Tu n'as pas de groupe.")
	var r := await _call(POST, "/parties/%s/leader" % b.party.party_id, {"user_id": member_id})
	if r.ok:
		_reload_party(b.party.party_id)
	return r


func set_party_class(class_id: String) -> Dictionary:
	if b.party.is_empty():
		return {"ok": true}
	var r := await _call(PUT, "/parties/%s/class" % b.party.party_id, {"class_id": class_id})
	if r.ok and not b.party.is_empty():
		_reload_party(b.party.party_id)
	return r


func launch_party(settings: Dictionary) -> Dictionary:
	var created := await _ensure_party()
	if not created.ok:
		return created
	var body := {
		"build_version": b.BUILD_VERSION,
		"match_settings": {"bots": int(settings.bots), "duration_seconds": int(settings.duration)},
	}
	var r := await _call(POST, "/parties/%s/launch" % b.party.party_id, body)
	if not r.ok:
		return r
	return {"ok": true, "server_id": r.data.server_id, "address": r.data.address, "port": int(r.data.port), "ticket": r.data.ticket}


# =========================================================================== serveurs publics

func get_servers() -> Dictionary:
	var r := await _call(GET, "/servers?build_version=%s" % b.BUILD_VERSION.uri_encode())
	if not r.ok:
		return r
	return {"ok": true, "servers": r.data.servers}


func get_join_ticket(server_id: String) -> Dictionary:
	var r := await _call(POST, "/servers/%s/join-ticket" % server_id)
	if not r.ok:
		return r
	return {"ok": true, "address": r.data.address, "port": int(r.data.port), "ticket": r.data.ticket}


# =========================================================================== temps réel

func _on_realtime(data: Dictionary) -> void:
	match data.get("type"):
		"hello":
			for p in data.get("friends", []):
				_presence[p.user_id] = {"status": p.status, "activity": p.get("activity")}
			_apply_presence()
		"presence":
			_presence[data.user_id] = {"status": data.status, "activity": data.get("activity")}
			_apply_presence()
		"notification":
			_on_notification(str(data.get("event", "")), data.get("data", {}))
		"error":
			push_warning("Real-time : %s (%s)" % [data.get("error"), data.get("message")])


## Met à jour la présence dans la liste d'amis déjà chargée.
func _apply_presence() -> void:
	for f in b.friends:
		var presence: Dictionary = _presence.get(f.user_id, {})
		f.status = presence.get("status", "offline")
		f.activity = presence.get("activity")
	b.friends.sort_custom(func(x, y): return _friend_order(x) < _friend_order(y))
	b.friends_changed.emit()


func _on_notification(event: String, data: Dictionary) -> void:
	match event:
		"friend.request_sent":
			await refresh_friends()
			b.toast.emit("%s t'a envoyé une demande d'ami." % _name_of(data.get("from_user_id", "")))
		"friend.added":
			await refresh_friends()
		"friend.request_removed", "friend.removed":
			refresh_friends()
		"party.invite_sent":
			var from: String = data.get("from_user_id", "")
			var invite := {"invite_id": data.invite_id, "party_id": data.party_id, "from_user_id": from, "from_name": _name_of(from)}
			b.invites = b.invites.filter(func(i): return i.invite_id != invite.invite_id) + [invite]
			b.invites_changed.emit()
			b.toast.emit("%s t'invite dans son groupe." % invite.from_name)
		"party.updated":
			if not (b.user_id() in data.get("member_ids", [])):
				# Retiré du groupe (parti ou exclu).
				if b.party.get("party_id") == data.party_id:
					b.party = {}
					b.party_changed.emit()
				return
			if data.party_id == b.party.get("party_id") and int(data.get("version", 0)) <= _party_version:
				return
			_reload_party(data.party_id)
		"party.disbanded":
			if b.party.get("party_id") == data.get("party_id"):
				b.party = {}
				b.party_changed.emit()
		"party.match_ready":
			b.match_ready.emit({"server_id": data.server_id, "address": data.address, "port": int(data.port), "ticket": data.ticket})
		"progress.level_up":
			b.toast.emit("Niveau %d atteint !" % int(data.get("level", 0)))
		"progress.achievement_unlocked":
			b.toast.emit("Succès débloqué : %s" % b.achievement_name(data.get("achievement_id", "")))


## Pseudo d'un ami déjà chargé, sinon « Un joueur ».
func _name_of(id: String) -> String:
	for list in [b.friends, b.incoming, b.outgoing]:
		for f in list:
			if f.user_id == id:
				return f.username
	return "Un joueur"
