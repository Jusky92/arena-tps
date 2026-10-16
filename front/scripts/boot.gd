extends Node
## Scène de démarrage (scenes/boot.tscn) : choisit entre le jeu et le serveur dédié.
##
## Un seul projet Godot donne deux exécutables (voir export_presets.cfg) :
##   TPSArena         le jeu, pour les joueurs           -> écran de connexion
##   TPSArena_Server  le serveur dédié, sans fenêtre     -> scenes/server/server.tscn
##
## Le serveur démarre aussi depuis l'éditeur ou la ligne de commande :
##   godot --path front --headless -- --server

const GAME_START := "res://scenes/auth.tscn"
const SERVER := "res://scenes/server/server.tscn"


func _ready() -> void:
	get_tree().change_scene_to_file.call_deferred(SERVER if is_server_build() else GAME_START)


static func is_server_build() -> bool:
	return OS.has_feature("dedicated_server") \
		or OS.get_cmdline_user_args().has("--server") \
		or DisplayServer.get_name() == "headless"
