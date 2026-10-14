class_name BackendLink
extends Node
## Lien entre le serveur de jeu dédié et le back (Server List), vu par le serveur.
##
## Toutes les communications du serveur avec le back passent par ici, avec les
## mêmes étapes que dans project-context.md (« Game server registry », « Match end ») :
##
##   start()          POST /servers            enregistrement (secret partagé -> server_token)
##   report()         PUT /servers/{id}/heartbeat  toutes les 5 s : état, joueurs, map
##                                             -> la réponse dit si le serveur est réservé
##   verify()         POST /tickets/verify     ticket d'un joueur -> son user_id
##   player_match()   événement player.match   (joined / left)
##   match_finished() événement match.finished (résultats de la partie)
##   stop()           DELETE /servers/{id}     désenregistrement à l'arrêt
##
## Les deux événements partent en HTTP vers la Server List, qui les publie dans
## Redis Streams : le serveur de jeu n'a jamais d'accès à Redis.
##
## Cette classe ne fait rien : voir lan_link.gd (sans back) et, plus tard,
## server_list_link.gd (vrai back).

## La Server List a réservé ce serveur pour un groupe (party).
signal reserved(party_id: String)

## Identifiant du serveur (donné par la Server List à l'enregistrement).
var server_id := ""
## Groupe qui a lancé la partie, ou null (LAN, ou partie sans groupe).
var party_id: Variant = null


## Enregistre le serveur. `info` = {name, address, port, map, max_players, build_version}.
## Renvoie "" si tout va bien, sinon l'erreur.
func start(_info: Dictionary) -> String:
	return ""


## Battement de cœur : état (idle, in_progress, ending), nombre de joueurs humains, map.
func report(_status: String, _players: int, _map: String) -> void:
	pass


## Vérifie le ticket d'un joueur. Renvoie son user_id, ou "" si l'accès est refusé.
## Avec le vrai back, c'est une coroutine (appel HTTP) : l'appeler avec `await`.
func verify(_ticket: String, _claimed_user_id: String) -> String:
	return ""


## Événement player.match : un joueur entre dans la partie ou la quitte.
func player_match(_user_id: String, _action: String) -> void:
	pass


## Événement match.finished. `result` a exactement les champs du modèle
## MatchFinished (libs/common/tpsarena_common/events.py), sans event_id.
func match_finished(_result: Dictionary) -> void:
	pass


## Désenregistre le serveur (arrêt propre).
func stop() -> void:
	pass
