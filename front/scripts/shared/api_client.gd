class_name ApiClient
extends Node
## Requêtes HTTP JSON vers le back, communes au jeu (BFF) et au serveur dédié
## (Server List). Un nœud HTTPRequest par requête, libéré à la fin.
##
##   var r := await api.request(HTTPClient.METHOD_POST, "/auth/login", {"email": …})
##   r = {ok, status, data, error, message}
##
## `error` est le code renvoyé par le back ({"error": …, "message": …}) : c'est
## le contrat de l'API, le jeu s'en sert pour choisir quoi faire. `message` est
## sa traduction française, prête à afficher.

## Adresse de base, ex. "http://localhost:8000".
var base_url := ""
## Délai maximal d'une requête, en secondes.
var timeout := 10.0

## Messages affichés pour chaque code d'erreur du back.
const ERROR_MESSAGES := {
	# Connexion au back
	"unreachable": "Impossible de joindre le serveur du jeu. Vérifie l'adresse du back et ta connexion.",
	"bad_gateway": "Le serveur du jeu a renvoyé une réponse invalide. Réessaie dans un instant.",
	"auth_unavailable": "Le service des comptes est indisponible. Réessaie dans un instant.",
	"serverlist_unavailable": "La liste des serveurs est indisponible. Réessaie dans un instant.",
	"social_unavailable": "Le service des amis et des groupes est indisponible. Réessaie dans un instant.",
	"stats_unavailable": "Les statistiques sont indisponibles. Réessaie dans un instant.",
	"realtime_unavailable": "Le service temps réel est indisponible. Réessaie dans un instant.",
	"rate_limited": "Trop de tentatives. Patiente un peu avant de réessayer.",
	"validation": "Certaines informations sont invalides.",
	# Comptes
	"invalid_credentials": "E-mail ou mot de passe incorrect.",
	"email_not_verified": "Vérifie d'abord ton adresse e-mail avec le code reçu.",
	"email_taken": "Cette adresse e-mail est déjà utilisée.",
	"username_taken": "Ce pseudo est déjà pris.",
	"already_registered": "Cette adresse e-mail ou ce pseudo est déjà utilisé.",
	"invalid_code": "Code invalide ou expiré.",
	"invalid_token": "Ta session a expiré. Reconnecte-toi.",
	"token_expired": "Ta session a expiré. Reconnecte-toi.",
	"not_authenticated": "Ta session a expiré. Reconnecte-toi.",
	"invalid_refresh_token": "Ta session a expiré. Reconnecte-toi.",
	"wrong_password": "Mot de passe incorrect.",
	"user_not_found": "Ce joueur n'existe pas.",
	# Amis
	"cannot_friend_self": "Tu ne peux pas t'ajouter toi-même.",
	"already_friends": "Vous êtes déjà amis.",
	"request_exists": "Tu as déjà envoyé une demande à ce joueur.",
	"request_not_found": "Cette demande d'ami n'existe plus.",
	"too_many_friends": "Nombre maximal d'amis atteint.",
	"not_friends": "Vous n'êtes pas amis.",
	# Groupes
	"party_not_found": "Ce groupe n'existe plus.",
	"not_member": "Ce joueur n'est pas dans le groupe.",
	"not_leader": "Seul le chef du groupe peut faire ça.",
	"already_in_party": "Tu es déjà dans un groupe.",
	"not_in_lobby": "Le groupe est en partie.",
	"party_full": "Le groupe est complet (8 joueurs).",
	"invite_not_found": "Cette invitation a expiré.",
	"already_member": "Ce joueur est déjà dans le groupe.",
	"cannot_invite_self": "Tu ne peux pas t'inviter toi-même.",
	"cannot_kick_self": "Quitte le groupe plutôt que de t'exclure.",
	"party_changed": "Le groupe a changé pendant la préparation de la partie. Relance.",
	"party_too_large": "Le groupe est trop grand pour un serveur.",
	# Serveurs
	"no_server_available": "Aucun serveur de jeu n'est libre pour le moment. Réessaie dans un instant.",
	"allocation_failed": "La réservation d'un serveur a échoué. Réessaie dans un instant.",
	"server_not_found": "Ce serveur n'existe plus.",
	"not_joinable": "Cette partie ne peut pas être rejointe.",
	"server_full": "Cette partie est pleine.",
	"invalid_ticket": "Ticket d'accès invalide ou expiré.",
	"match_not_found": "Cette partie n'existe pas.",
}


## Envoie une requête. `body` (Dictionary ou null) part en JSON.
func request(method: int, path: String, body: Variant = null, headers := PackedStringArray()) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = timeout
	add_child(http)
	var all_headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	all_headers.append_array(headers)
	var payload := "" if body == null else JSON.stringify(body)
	var err := http.request(base_url + path, all_headers, method, payload)
	if err != OK:
		http.queue_free()
		return failure(0, "unreachable")
	var response: Array = await http.request_completed
	http.queue_free()
	var result: int = response[0]
	var status: int = response[1]
	var text := (response[3] as PackedByteArray).get_string_from_utf8()
	if result != HTTPRequest.RESULT_SUCCESS:
		return failure(0, "unreachable")
	var data: Variant = JSON.parse_string(text) if not text.is_empty() else null
	if status >= 200 and status < 300:
		return {"ok": true, "status": status, "data": data, "error": "", "message": ""}
	var code := ""
	if data is Dictionary and data.has("error"):
		code = str(data.error)
	elif status == 422:
		code = "validation"
	elif status == 502:
		code = "bad_gateway"
	var fallback: String = data.get("message", "") if data is Dictionary else ""
	return failure(status, code, fallback)


## Réponse d'échec au même format que `request`.
static func failure(status: int, code: String, fallback := "") -> Dictionary:
	var message: String = ERROR_MESSAGES.get(code, "")
	if message.is_empty():
		message = fallback if not fallback.is_empty() else "Erreur inattendue (code %d)." % status
	return {"ok": false, "status": status, "data": null, "error": code, "message": message}


static func bearer(token: String) -> PackedStringArray:
	return PackedStringArray(["Authorization: Bearer " + token])
