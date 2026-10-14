extends Node
## Service d'accès au back-end (autoload "Backend").
##
## Pour l'instant c'est une SIMULATION : aucune requête réseau, des données factices
## et un petit délai pour imiter le réseau. Les fonctions reprennent les routes du
## BFF prévues dans l'architecture (Auth, Social, Server List, Stats) :
##
##   register / verify_email / resend_code / login / request_password_reset / logout
##   get_profile / get_friends / invite_to_party / get_leaderboard
##   get_servers / create_server / join_server / report_match
##
## Quand le vrai back sera prêt, il suffira de remplacer le contenu de ces fonctions
## par des appels HTTPRequest vers le BFF : les écrans n'auront pas à changer.
## Toutes les fonctions sont asynchrones : on les appelle avec `await`.

signal session_changed
signal party_changed

const BUILD_VERSION := "0.6.0-alpha"
const SIMULATED_LATENCY := Vector2(0.25, 0.6)
const SAVE_PATH := "user://profil_simule.cfg"

## Joueur connecté (vide si déconnecté).
var user := {}
## Groupe (party) : liste de pseudos, le chef en premier. 8 joueurs maximum.
var party: Array[String] = []
## Serveur rejoint pour la partie en cours.
var current_server := {}

var _stats := {}
var _rng := RandomNumberGenerator.new()

const HANDLES := [
	"NeoByte", "Gl1tch", "V0LT", "Cipher", "Kairo", "N3on_Rider", "Rogue_AI", "Syntax", "Hexa",
	"PixelGhost", "ZeroDay", "Quantum", "Nova", "Raven", "Echo", "Overclock", "Firewall", "Daemon",
	"Proxy", "Kernel", "Byte_Me", "Hash", "Static", "Vector", "Shader", "Lambda", "Nyx", "Orion",
	"Sudo", "Ping", "Packet", "Cortex", "Flux", "Ion", "Jolt", "Krypt", "Lux", "Mako", "Null",
	"Omega", "Pulse", "Quark", "Rift", "Spark", "Tesla", "Umbra", "Vapor", "Wraith", "Xeno", "Yotta",
]
const CLASSES := ["Tank", "Assassin", "Tireur"]


func _ready() -> void:
	_rng.seed = 2026
	_load_stats()


func is_logged_in() -> bool:
	return not user.is_empty()


func username() -> String:
	return user.get("username", "Joueur")


# =========================================================================== Auth

## Inscription : crée le compte (non vérifié) et "envoie" un code par e-mail.
func register(pseudo: String, email: String, password: String) -> Dictionary:
	await _latency()
	pseudo = pseudo.strip_edges()
	if pseudo.length() < 3 or pseudo.length() > 16:
		return _error("Le pseudo doit faire entre 3 et 16 caractères.")
	if not email.contains("@") or not email.contains("."):
		return _error("Adresse e-mail invalide.")
	if password.length() < 8:
		return _error("Le mot de passe doit faire au moins 8 caractères.")
	user = {}
	_pending_registration = {"username": pseudo, "email": email}
	return {"ok": true}


var _pending_registration := {}


## Vérification de l'e-mail avec le code à 6 chiffres (simulation : tout code à 6 chiffres est accepté).
## En cas de succès, le joueur est directement connecté (le back renvoie les jetons).
func verify_email(email: String, code: String) -> Dictionary:
	await _latency()
	if code.length() != 6 or not code.is_valid_int():
		return _error("Le code doit contenir 6 chiffres.")
	var pseudo: String = _pending_registration.get("username", email.get_slice("@", 0))
	_open_session(pseudo, email)
	return {"ok": true}


func resend_code(_email: String) -> Dictionary:
	await _latency()
	return {"ok": true, "message": "Si un compte existe, un nouveau code a été envoyé."}


## Connexion. Simulation : accepte tout (sans back, le bouton mène directement au menu).
## Le vrai back renverra 401 (identifiants faux) ou 403 email_not_verified.
func login(identifier: String, _password: String) -> Dictionary:
	await _latency()
	identifier = identifier.strip_edges()
	var pseudo := identifier.get_slice("@", 0) if not identifier.is_empty() else "Joueur"
	_open_session(pseudo, identifier if identifier.contains("@") else "%s@exemple.fr" % pseudo.to_lower())
	return {"ok": true}


## Mot de passe oublié : la réponse est toujours la même (on ne révèle pas si le compte existe).
func request_password_reset(_email: String) -> Dictionary:
	await _latency()
	return {"ok": true, "message": "Si un compte existe pour cette adresse, un code a été envoyé."}


func logout() -> void:
	user = {}
	party.clear()
	session_changed.emit()


func _open_session(pseudo: String, email: String) -> void:
	user = {
		"user_id": _fake_uuid(),
		"username": pseudo.left(16),
		"email": email,
	}
	party = [username()]
	session_changed.emit()
	party_changed.emit()


# =========================================================================== Profil et stats

## Profil + progression + statistiques du joueur connecté.
func get_profile() -> Dictionary:
	await _latency()
	var kills: int = _stats.get("kills", 0)
	var deaths: int = _stats.get("deaths", 0)
	var xp: int = _stats.get("xp", 0)
	var level := 1 + xp / 1000
	return {
		"username": username(),
		"level": level,
		"xp": xp % 1000,
		"xp_next": 1000,
		"matches": _stats.get("matches", 0),
		"wins": _stats.get("wins", 0),
		"kills": kills,
		"deaths": deaths,
		"kd": float(kills) / maxf(deaths, 1),
		"best_streak": _stats.get("best_streak", 0),
		"playtime_min": int(_stats.get("playtime_s", 0) / 60.0),
		"favorite_class": _favorite_class(),
	}


## Classement mondial ou entre amis. Colonnes : rang, pseudo, niveau, kills, morts, K/D, victoires.
func get_leaderboard(scope: String) -> Array:
	await _latency()
	var rows := []
	var names: Array = []
	if scope == "friends":
		for f in _friends_data():
			names.append(f.name)
	else:
		names = HANDLES.duplicate()
	var rng := RandomNumberGenerator.new()
	for i in names.size():
		rng.seed = hash(names[i])
		var kills := rng.randi_range(80, 4200)
		var deaths := int(kills / rng.randf_range(0.6, 2.4))
		rows.append({
			"name": names[i], "level": 1 + kills / 120, "kills": kills, "deaths": deaths,
			"kd": float(kills) / maxf(deaths, 1), "wins": kills / rng.randi_range(14, 30), "me": false,
		})
	var profile := await get_profile()
	rows.append({
		"name": username(), "level": profile.level, "kills": profile.kills, "deaths": profile.deaths,
		"kd": profile.kd, "wins": profile.wins, "me": true,
	})
	rows.sort_custom(func(a, b): return a.kills > b.kills)
	for i in rows.size():
		rows[i]["rank"] = i + 1
	return rows


## Résultat d'un match (équivalent de l'événement match.finished).
func report_match(result: Dictionary) -> void:
	_stats["matches"] = _stats.get("matches", 0) + 1
	_stats["kills"] = _stats.get("kills", 0) + int(result.get("kills", 0))
	_stats["deaths"] = _stats.get("deaths", 0) + int(result.get("deaths", 0))
	_stats["playtime_s"] = _stats.get("playtime_s", 0.0) + float(result.get("duration", 0.0))
	_stats["best_streak"] = maxi(_stats.get("best_streak", 0), int(result.get("best_streak", 0)))
	if result.get("won", false):
		_stats["wins"] = _stats.get("wins", 0) + 1
	_stats["xp"] = _stats.get("xp", 0) + 100 + 25 * int(result.get("kills", 0)) + (250 if result.get("won", false) else 0)
	var played: Dictionary = _stats.get("classes", {})
	var cls: String = result.get("class", "")
	played[cls] = played.get(cls, 0) + 1
	_stats["classes"] = played
	_save_stats()


func _favorite_class() -> String:
	var played: Dictionary = _stats.get("classes", {})
	var best := "—"
	var count := 0
	for cls in played:
		if played[cls] > count:
			count = played[cls]
			best = cls
	return best


# =========================================================================== Social

func get_friends() -> Array:
	await _latency()
	return _friends_data()


func _friends_data() -> Array:
	return [
		{"name": "Elian", "status": "online", "activity": "Dans le menu", "level": 14},
		{"name": "Gl1tch", "status": "in_match", "activity": "En partie · Neo-Edo 5/8", "level": 22},
		{"name": "Nova", "status": "online", "activity": "Dans le menu", "level": 9},
		{"name": "Kairo", "status": "in_match", "activity": "En partie · Neo-Edo 7/8", "level": 31},
		{"name": "PixelGhost", "status": "offline", "activity": "Vu il y a 2 h", "level": 6},
		{"name": "Cipher", "status": "offline", "activity": "Vu hier", "level": 18},
		{"name": "Raven", "status": "offline", "activity": "Vu il y a 3 jours", "level": 11},
	]


## Invite un ami dans le groupe (simulation : il accepte après un court instant).
func invite_to_party(friend_name: String) -> Dictionary:
	if party.has(friend_name):
		return _error("%s est déjà dans le groupe." % friend_name)
	if party.size() >= 8:
		return _error("Le groupe est complet (8 joueurs maximum).")
	await get_tree().create_timer(_rng.randf_range(0.8, 1.6)).timeout
	party.append(friend_name)
	party_changed.emit()
	return {"ok": true}


func leave_party_member(friend_name: String) -> void:
	party.erase(friend_name)
	party_changed.emit()


# =========================================================================== Serveurs

## Liste publique des serveurs (uniquement les parties en cours avec des places libres).
func get_servers() -> Array:
	await _latency()
	var servers := []
	var names := ["CFA INSTA · Salle 204", "Paris · Match à mort", "Gennevilliers LAN", "Archi SI M2 · Officiel",
		"Neon District #1", "Neon District #2", "Asnières Arena", "Entraînement libre"]
	for i in names.size():
		var players := _rng.randi_range(1, 7)
		servers.append({
			"id": "srv-%d" % (i + 1), "name": names[i], "map": "Neo-Edo", "mode": "Match à mort",
			"players": players, "max_players": 8, "ping": _rng.randi_range(8, 70),
			"region": "EU-Ouest", "build_version": BUILD_VERSION,
		})
	return servers


## Lance une partie depuis le groupe : allocation d'un serveur + un ticket par membre.
## `progress` reçoit les étapes à afficher (comme le vrai flux party -> launch).
func create_server(progress: Callable) -> Dictionary:
	var steps := ["Lancement du groupe…", "Allocation d'un serveur…", "Réservation de %d place(s)…" % party.size(),
		"Génération des tickets…", "Connexion au serveur…"]
	for step in steps:
		progress.call(step)
		await get_tree().create_timer(_rng.randf_range(0.25, 0.5)).timeout
	current_server = {"id": "srv-local", "name": "Serveur de %s" % username(), "map": "Neo-Edo",
		"mode": "Match à mort", "players": party.size(), "max_players": 8, "ping": 4}
	return {"ok": true, "server": current_server, "ticket": _fake_uuid()}


## Rejoindre un serveur de la liste : demande d'un ticket à usage unique (30 s).
func join_server(server: Dictionary, progress: Callable) -> Dictionary:
	for step in ["Demande d'un ticket…", "Vérification des places…", "Connexion à %s…" % server.name]:
		progress.call(step)
		await get_tree().create_timer(_rng.randf_range(0.25, 0.5)).timeout
	current_server = server
	return {"ok": true, "server": server, "ticket": _fake_uuid()}


# =========================================================================== outils

func _latency() -> void:
	await get_tree().create_timer(_rng.randf_range(SIMULATED_LATENCY.x, SIMULATED_LATENCY.y)).timeout


func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}


func _fake_uuid() -> String:
	var hex := "0123456789abcdef"
	var s := ""
	for i in 32:
		s += hex[_rng.randi_range(0, 15)]
		if i in [7, 11, 15, 19]:
			s += "-"
	return s


func _load_stats() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		_stats = cfg.get_value("profil", "stats", {})


func _save_stats() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profil", "stats", _stats)
	cfg.save(SAVE_PATH)
