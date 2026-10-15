class_name SimulatedBackend
extends Node
## « Jouer hors ligne » : back simulé, sans aucune requête réseau. Mêmes
## fonctions et mêmes formes de données que BffBackend, avec des valeurs
## factices et un petit délai pour imiter le réseau.
##
## Le lancement d'une partie en ligne et les serveurs publics demandent le vrai
## back : hors ligne, on joue en LAN en rejoignant un serveur par son adresse.

const SIMULATED_LATENCY := Vector2(0.15, 0.4)
const ONLINE_ONLY := "Hors ligne, rejoins un serveur LAN par son adresse (JOUER EN LIGNE). Connecte-toi au back pour lancer une partie de groupe."

const HANDLES := [
	"NeoByte", "Gl1tch", "V0LT", "Cipher", "Kairo", "N3on_Rider", "Rogue_AI", "Syntax", "Hexa",
	"PixelGhost", "ZeroDay", "Quantum", "Nova", "Raven", "Echo", "Overclock", "Firewall", "Daemon",
	"Proxy", "Kernel", "Byte_Me", "Hash", "Static", "Vector", "Shader", "Lambda", "Nyx", "Orion",
]

var b: Node
var _rng := RandomNumberGenerator.new()
var _pending_username := ""
## Identifiants factices stables par pseudo, pour que les listes restent cohérentes.
var _ids := {}


func setup(facade: Node) -> void:
	b = facade
	_rng.randomize()


func services_online() -> bool:
	return false


func _latency() -> void:
	await get_tree().create_timer(_rng.randf_range(SIMULATED_LATENCY.x, SIMULATED_LATENCY.y)).timeout


static func _ok(extra := {}) -> Dictionary:
	return {"ok": true, "error": "", "message": ""}.merged(extra)


static func _err(message: String) -> Dictionary:
	return {"ok": false, "error": "", "message": message}


func _id_of(username: String) -> String:
	if not _ids.has(username):
		_ids[username] = Uuid.v4()
	return _ids[username]


# =========================================================================== compte

func register(pseudo: String, email: String, password: String) -> Dictionary:
	await _latency()
	if pseudo.length() < 3 or pseudo.length() > 20:
		return _err("Le pseudo doit faire de 3 à 20 caractères.")
	if not email.contains("@"):
		return _err("Adresse e-mail invalide.")
	if password.length() < 8:
		return _err("Le mot de passe doit faire au moins 8 caractères.")
	_pending_username = pseudo
	return _ok()


func verify_email(email: String, code: String) -> Dictionary:
	await _latency()
	if code.length() != 6 or not code.is_valid_int():
		return _err("Le code doit contenir 6 chiffres.")
	_open_session(_pending_username if not _pending_username.is_empty() else email.get_slice("@", 0), email)
	return _ok()


func resend_code(_email: String) -> Dictionary:
	await _latency()
	return _ok({"message": "Hors ligne : n'importe quels 6 chiffres conviennent."})


## Accepte n'importe quel identifiant : le pseudo est la partie avant « @ ».
func login(identifier: String, _password: String) -> Dictionary:
	await _latency()
	var pseudo := identifier.get_slice("@", 0) if not identifier.is_empty() else "Joueur"
	_open_session(pseudo, identifier)
	return _ok()


func request_password_reset(_email: String) -> Dictionary:
	await _latency()
	return _ok({"message": "Hors ligne : n'importe quels 6 chiffres conviennent."})


func confirm_password_reset(_email: String, _code: String, _new_password: String) -> Dictionary:
	await _latency()
	return _ok({"message": "Mot de passe changé (hors ligne, rien n'est enregistré)."})


func logout() -> void:
	pass


## Nouvel identifiant à chaque session : deux jeux lancés sur le même PC ne
## doivent pas avoir le même (le serveur de jeu refuse un compte déjà connecté).
func _open_session(pseudo: String, email: String) -> void:
	b.user = {"user_id": Uuid.v4(), "username": pseudo.left(20), "email": email}
	b.party = {}
	b.friends = []
	for i in 7:
		var handle: String = HANDLES[(i * 5 + 3) % HANDLES.size()]
		var status := "online" if i < 4 else "offline"
		b.friends.append({"user_id": _id_of(handle), "username": handle, "status": status,
			"activity": ("in_match" if i % 2 == 1 else "menu") if status == "online" else null})
	b.incoming = [{"request_id": Uuid.v4(), "user_id": _id_of("PixelGhost"), "username": "PixelGhost"}]
	b.outgoing = []
	b.invites = []
	b.session_changed.emit()
	b.friends_changed.emit()


# =========================================================================== profil et classement

## Hors ligne, rien n'est compté : un profil tout neuf.
func get_profile() -> Dictionary:
	await _latency()
	var achievements := []
	for id in b.ACHIEVEMENTS:
		achievements.append({"id": id, "name": id, "description": "", "unlocked_at": null})
	return _ok({"username": b.username(), "level": 1, "xp": 0, "xp_in_level": 0, "xp_to_next_level": 1000,
		"matches": 0, "wins": 0, "kills": 0, "deaths": 0, "kd": 0.0, "achievements": achievements})


func get_leaderboard(type: String, around: bool) -> Dictionary:
	await _latency()
	var rows := []
	for handle in HANDLES:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(handle + type)
		var value: int = {"xp": rng.randi_range(500, 60000), "wins": rng.randi_range(1, 300), "kills": rng.randi_range(20, 5000)}[type]
		rows.append({"user_id": _id_of(handle), "username": handle, "value": value, "me": false})
	rows.sort_custom(func(x, y): return x.value > y.value)
	for i in rows.size():
		rows[i]["rank"] = i + 1
	var entries := rows.slice(10, 21) if around else rows.slice(0, 20)
	return _ok({"total_players": rows.size(), "player_rank": null, "entries": entries})


# =========================================================================== amis

func refresh_friends() -> Dictionary:
	b.friends_changed.emit()
	return _ok()


func search_users(text: String) -> Dictionary:
	await _latency()
	var users := []
	for handle in HANDLES:
		if handle.to_lower().contains(text.to_lower()):
			users.append({"user_id": _id_of(handle), "username": handle})
	return _ok({"users": users.slice(0, 20)})


func send_friend_request(target: String) -> Dictionary:
	await _latency()
	b.outgoing.append({"request_id": Uuid.v4(), "user_id": target, "username": _name_of(target)})
	b.friends_changed.emit()
	return _ok({"message": "Demande d'ami envoyée."})


func accept_friend_request(request_id: String) -> Dictionary:
	await _latency()
	for q in b.incoming:
		if q.request_id == request_id:
			b.friends.append({"user_id": q.user_id, "username": q.username, "status": "online", "activity": "menu"})
	b.incoming = b.incoming.filter(func(q): return q.request_id != request_id)
	b.friends_changed.emit()
	return _ok()


func decline_friend_request(request_id: String) -> Dictionary:
	await _latency()
	b.incoming = b.incoming.filter(func(q): return q.request_id != request_id)
	b.outgoing = b.outgoing.filter(func(q): return q.request_id != request_id)
	b.friends_changed.emit()
	return _ok()


func remove_friend(friend_id: String) -> Dictionary:
	await _latency()
	b.friends = b.friends.filter(func(f): return f.user_id != friend_id)
	b.friends_changed.emit()
	return _ok()


func _name_of(id: String) -> String:
	for handle in _ids:
		if _ids[handle] == id:
			return handle
	return "Joueur"


# =========================================================================== groupe

func create_party() -> Dictionary:
	if not b.party.is_empty():
		return _err("Tu es déjà dans un groupe.")
	b.party = {"party_id": Uuid.v4(), "leader_id": b.user_id(), "status": "lobby",
		"members": [{"user_id": b.user_id(), "username": b.username()}]}
	b.party_changed.emit()
	return _ok()


## L'ami invité « accepte » après un court instant.
func invite_to_party(friend_id: String) -> Dictionary:
	if b.party.is_empty():
		create_party()
	var members: Array = b.party.members
	if members.any(func(m): return m.user_id == friend_id):
		return _err("Ce joueur est déjà dans le groupe.")
	if members.size() >= 8:
		return _err("Le groupe est complet (8 joueurs).")
	await get_tree().create_timer(_rng.randf_range(0.8, 1.6)).timeout
	members.append({"user_id": friend_id, "username": _name_of(friend_id)})
	b.party_changed.emit()
	return _ok({"message": "Invitation acceptée."})


func accept_invite(invite_id: String) -> Dictionary:
	b.dismiss_invite(invite_id)
	return _ok()


func leave_party() -> Dictionary:
	b.party = {}
	b.party_changed.emit()
	return _ok()


func kick_from_party(member_id: String) -> Dictionary:
	if not b.party.is_empty():
		b.party.members = b.party.members.filter(func(m): return m.user_id != member_id)
		b.party_changed.emit()
	return _ok()


func launch_party(_settings: Dictionary) -> Dictionary:
	return _err(ONLINE_ONLY)


# =========================================================================== serveurs publics

func get_servers() -> Dictionary:
	return _err(ONLINE_ONLY)


func get_join_ticket(_server_id: String) -> Dictionary:
	return _err(ONLINE_ONLY)
