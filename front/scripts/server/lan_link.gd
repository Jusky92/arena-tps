class_name LanLink
extends BackendLink
## Lien « sans back » : partie en réseau local, joueurs connectés par IP.
##
## Aucun appel réseau : tous les tickets sont acceptés (le client annonce son
## user_id) et les événements sont seulement écrits dans le journal, déjà au
## format attendu par le back. On peut ainsi vérifier les données avant que le
## serveur soit branché à la Server List.


func is_lan() -> bool:
	return true


func start(info: Dictionary) -> String:
	server_id = Uuid.v4()
	Net.log_line("LAN : pas de back, serveur %s « %s » (id %s)" % [info.get("map", ""), info.get("name", ""), server_id])
	return ""


func verify(_ticket: String, claimed_user_id: String) -> String:
	return claimed_user_id


func player_match(user_id: String, action: String) -> void:
	Net.log_line("LAN : player.match %s" % JSON.stringify({"user_id": user_id, "server_id": server_id, "action": action}))


func match_finished(result: Dictionary) -> void:
	Net.log_line("LAN : match.finished %s" % JSON.stringify(result))
