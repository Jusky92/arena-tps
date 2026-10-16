class_name UserData
## Dossier des données du joueur (user://). Godot le nomme d'après le projet : il est
## passé de « Arena TPS » à « TPS Arena » avec le nom du jeu. Au premier lancement
## sous le nouveau nom, on reprend les réglages de l'ancien dossier (touches, classes,
## paramètres, adresse du back, identifiants retenus). L'ancien dossier n'est pas effacé.

const OLD_FOLDER := "Arena TPS"


static func migrate_old_folder() -> void:
	var current := OS.get_user_data_dir()
	var old := current.get_base_dir().path_join(OLD_FOLDER)
	if current.get_file() == OLD_FOLDER or not DirAccess.dir_exists_absolute(old):
		return
	var dir := DirAccess.open(old)
	if dir == null:
		return
	for file in dir.get_files():
		var target := current.path_join(file)
		if file.get_extension() == "cfg" and not FileAccess.file_exists(target):
			DirAccess.copy_absolute(old.path_join(file), target)
