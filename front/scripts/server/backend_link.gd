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
## Cette classe ne fait rien : voir lan_link.gd (sans back) et server_list_link.gd
## (vrai back).
##
## start(), report() et verify() sont des coroutines (elles contiennent un await)
## même ici : le serveur les appelle à travers une variable typée BackendLink, et
## GDScript décide d'après ce type statique si l'appel attend une coroutine. Une
## méthode ordinaire ici mais coroutine dans ServerListLink fait planter Godot
## (pile corrompue après l'await). Une implémentation qui répond tout de suite
## (LanLink) reste compatible.

## La Server List a réservé ce serveur pour un groupe (party).
signal reserved(party_id: String)
## La réservation a expiré sans que la partie commence : le serveur est de nouveau libre.
signal reservation_ended

## Identifiant du serveur (donné par la Server List à l'enregistrement).
var server_id := ""
## Groupe qui a lancé la partie, ou null (LAN, ou partie sans groupe).
var party_id: Variant = null
## Tickets pas encore utilisés (places réservées), d'après le dernier battement de cœur.
var reserved_slots := 0
## Réglages choisis par le chef du groupe qui a réservé le serveur :
## {bots, duration_seconds}, vide si aucun (LAN, ou pas de réservation).
var match_settings := {}
## user_id du chef du groupe qui a réservé le serveur : il lance la partie depuis
## le salon. Vide si aucun (LAN, ou pas de réservation).
var leader_user_id := ""


## true pour le mode LAN : pas de back, le premier joueur règle et lance la partie.
func is_lan() -> bool:
	return false


## Enregistre le serveur. `info` = {name, address, port, region, map, max_players, build_version}.
## Renvoie "" si tout va bien, sinon l'erreur. Peut être une coroutine : l'appeler avec `await`.
func start(_info: Dictionary) -> String:
	await get_tree().process_frame
	return ""


## Battement de cœur : état (idle, in_progress, ending), nombre de joueurs humains, map.
func report(_status: String, _players: int, _map: String) -> void:
	await get_tree().process_frame


## Vérifie le ticket d'un joueur. Renvoie son user_id, ou "" si l'accès est refusé.
## Avec le vrai back, c'est une coroutine (appel HTTP) : l'appeler avec `await`.
func verify(_ticket: String, _claimed_user_id: String) -> String:
	await get_tree().process_frame
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
