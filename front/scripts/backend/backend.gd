extends Node
## Service d'accès au back-end (autoload "Backend"), seul point de contact des écrans.
##
## Deux modes, avec exactement la même API :
##   "bff"        le vrai back : HTTP vers le BFF (port 8000) et WebSocket vers
##                Real-time (port 8005) sur l'adresse choisie à la connexion.
##                Voir bff_backend.gd et realtime_client.gd.
##   "simulated"  « Jouer hors ligne » : aucune requête, données factices
##                (simulated_backend.gd). On joue alors en LAN, par adresse IP.
##
## Les fonctions sont asynchrones (`await`) et renvoient un dictionnaire
## {ok, error, message, …} : `error` est le code du back, `message` sa traduction
## à afficher. L'état partagé (compte, groupe, amis, invitations) est gardé ici et
## les écrans suivent les signaux.

signal session_changed
## La session est perdue (jeton refusé, session révoquée) : retour à l'écran de connexion.
signal session_lost(reason: String)
signal party_changed
signal friends_changed
signal invites_changed
## Le groupe a un serveur : {server_id, address, port, ticket}.
signal match_ready(info: Dictionary)
## Connexion au service temps réel ouverte ou perdue.
signal services_changed
## Court message à afficher (demande d'ami reçue, niveau atteint…).
signal toast(text: String)

## Doit être identique sur le jeu et le serveur dédié (vérifiée à la connexion),
## et sert à filtrer la liste des serveurs.
const BUILD_VERSION := "0.11.0-alpha"
const BFF_PORT := 8000
const REALTIME_PORT := 8005
const CONFIG_PATH := "user://reseau.cfg"

## "bff" ou "simulated".
var mode := "bff"
## Adresse du PC qui fait tourner le back (BFF + Real-time).
var host := "localhost"

## Joueur connecté : {user_id, username, email} (vide si déconnecté).
var user := {}
## Groupe : {party_id, leader_id, status, members: [{user_id, username}]}, vide si aucun.
var party := {}
## Amis : [{user_id, username, status ("online" | "offline"), activity ("menu" | "in_match" | null)}].
var friends: Array = []
## Demandes d'ami reçues et envoyées : [{request_id, user_id, username}].
var incoming: Array = []
var outgoing: Array = []
## Invitations dans un groupe reçues : [{invite_id, party_id, from_user_id, from_name}].
var invites: Array = []

var _impl: Node


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		host = cfg.get_value("back", "adresse", host)
		mode = cfg.get_value("back", "mode", mode)
	_set_impl()


## Change de mode (et d'adresse pour le vrai back), retenu pour la prochaine fois.
func use(new_mode: String, new_host := "") -> void:
	if is_logged_in():
		logout()
	mode = new_mode
	if not new_host.strip_edges().is_empty():
		host = new_host.strip_edges().trim_prefix("http://").trim_prefix("https://").trim_suffix("/")
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value("back", "adresse", host)
	cfg.set_value("back", "mode", mode)
	cfg.save(CONFIG_PATH)
	_set_impl()


func _set_impl() -> void:
	if _impl:
		remove_child(_impl)
		_impl.queue_free()
	_impl = (SimulatedBackend.new() if mode == "simulated" else BffBackend.new()) as Node
	_impl.name = "Impl"
	add_child(_impl)
	_impl.setup(self)


func is_simulated() -> bool:
	return mode == "simulated"


func is_logged_in() -> bool:
	return not user.is_empty()


func username() -> String:
	return user.get("username", "Joueur")


## Identifiant du compte (le `sub` du JWT) : il identifie le joueur auprès du
## serveur de jeu et dans les résultats de match.
func user_id() -> String:
	return user.get("user_id", "")


## true si le service temps réel est connecté (toujours false hors ligne).
func services_online() -> bool:
	return _impl.services_online()


## true si le joueur peut lancer une partie : chef du groupe, ou pas de groupe.
func is_party_leader() -> bool:
	return party.is_empty() or party.get("leader_id") == user_id()


## Membres du groupe, le joueur seul s'il n'en a pas.
func party_members() -> Array:
	if party.is_empty():
		return [{"user_id": user_id(), "username": username()}]
	return party.get("members", [])


# =========================================================================== Compte

func register(pseudo: String, email: String, password: String) -> Dictionary:
	return await _impl.register(pseudo.strip_edges(), email.strip_edges(), password)


## En cas de succès, le joueur est connecté (le back renvoie les jetons).
func verify_email(email: String, code: String) -> Dictionary:
	return await _impl.verify_email(email.strip_edges(), code)


func resend_code(email: String) -> Dictionary:
	return await _impl.resend_code(email.strip_edges())


## Connexion avec l'e-mail OU le pseudo du compte. `error` vaut "email_not_verified"
## si le compte attend encore son code.
func login(identifier: String, password: String) -> Dictionary:
	return await _impl.login(identifier.strip_edges(), password)


func request_password_reset(email: String) -> Dictionary:
	return await _impl.request_password_reset(email.strip_edges())


func confirm_password_reset(email: String, code: String, new_password: String) -> Dictionary:
	return await _impl.confirm_password_reset(email.strip_edges(), code, new_password)


func logout() -> void:
	_impl.logout()
	_clear()


## Appelé par l'implémentation quand la session ne peut plus continuer.
func _lose_session(reason: String) -> void:
	if not is_logged_in():
		return
	_impl.logout()
	_clear()
	session_lost.emit(reason)


func _clear() -> void:
	user = {}
	party = {}
	friends = []
	incoming = []
	outgoing = []
	invites = []
	session_changed.emit()
	party_changed.emit()
	friends_changed.emit()
	invites_changed.emit()


# =========================================================================== Profil et classement

## {ok, username, level, xp, xp_in_level, xp_to_next_level, matches, wins, kills,
##  deaths, kd, achievements: [{id, name, description, unlocked_at}]}
func get_profile() -> Dictionary:
	return await _impl.get_profile()


## Classes (équipements) du joueur, sauvegardées sur son compte :
## {ok, loadouts: [{name, primary, secondary}]}. Liste vide = jamais enregistrées.
func get_loadouts() -> Dictionary:
	return await _impl.get_loadouts()


## Remplace toutes les classes du joueur (10 au maximum) : {ok}.
func save_loadouts(list: Array) -> Dictionary:
	return await _impl.save_loadouts(list)


## `type` : "xp", "wins" ou "kills". `around` : autour du joueur plutôt que le haut.
## {ok, total_players, player_rank, entries: [{rank, user_id, username, value, me}]}
func get_leaderboard(type: String, around := false) -> Dictionary:
	return await _impl.get_leaderboard(type, around)


# =========================================================================== Amis

func refresh_friends() -> Dictionary:
	return await _impl.refresh_friends()


## Joueurs dont le pseudo contient `text` : {ok, users: [{user_id, username}]}.
func search_users(text: String) -> Dictionary:
	return await _impl.search_users(text.strip_edges())


func send_friend_request(target_user_id: String) -> Dictionary:
	return await _impl.send_friend_request(target_user_id)


func accept_friend_request(request_id: String) -> Dictionary:
	return await _impl.accept_friend_request(request_id)


## Refuse une demande reçue, ou annule une demande envoyée.
func decline_friend_request(request_id: String) -> Dictionary:
	return await _impl.decline_friend_request(request_id)


func remove_friend(friend_id: String) -> Dictionary:
	return await _impl.remove_friend(friend_id)


# =========================================================================== Groupe

## Invite un ami (le groupe est créé s'il n'existe pas encore).
func invite_to_party(friend_id: String) -> Dictionary:
	return await _impl.invite_to_party(friend_id)


func accept_invite(invite_id: String) -> Dictionary:
	return await _impl.accept_invite(invite_id)


func dismiss_invite(invite_id: String) -> void:
	invites = invites.filter(func(i): return i.invite_id != invite_id)
	invites_changed.emit()


func leave_party() -> Dictionary:
	return await _impl.leave_party()


func kick_from_party(member_id: String) -> Dictionary:
	return await _impl.kick_from_party(member_id)


## Chef : réserve un serveur pour le groupe (créé s'il n'existe pas).
## {ok, server_id, address, port, ticket} ; les autres membres reçoivent `match_ready`.
func launch_party() -> Dictionary:
	return await _impl.launch_party()


# =========================================================================== Serveurs publics

## Parties en cours avec des places libres : {ok, servers: [{server_id, name, region, map, players, max_players}]}.
func get_servers() -> Dictionary:
	return await _impl.get_servers()


## Ticket pour rejoindre une partie en cours : {ok, address, port, ticket}.
func get_join_ticket(server_id: String) -> Dictionary:
	return await _impl.get_join_ticket(server_id)


# =========================================================================== Traductions

## Noms des succès (les définitions sont dans le service Stats, en anglais).
const ACHIEVEMENTS := {
	"first_match": ["Bienvenue dans l'arène", "Jouer ta première partie."],
	"first_win": ["Premier sang", "Gagner une partie."],
	"wins_10": ["Prétendant", "Gagner 10 parties."],
	"kills_100": ["Tireur d'élite", "Faire 100 éliminations."],
	"kills_1000": ["Légende", "Faire 1000 éliminations."],
	"match_10_kills": ["Carnage", "Faire 10 éliminations dans une partie."],
	"flawless": ["Intouchable", "Gagner une partie sans mourir."],
}


static func achievement_name(id: String, fallback := "") -> String:
	return ACHIEVEMENTS.get(id, [fallback if not fallback.is_empty() else id])[0]


static func achievement_description(id: String, fallback := "") -> String:
	var entry: Array = ACHIEVEMENTS.get(id, [])
	return entry[1] if entry.size() > 1 else fallback
