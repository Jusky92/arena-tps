extends Node
## Données partagées entre les écrans (menu, choix du spécialiste, partie).
## Chargé automatiquement au démarrage (autoload "GameState").
##
## Vocabulaire :
##   spécialiste = personnage (design + capacité), une fiche ClassData ;
##   classe      = équipement créé par le joueur : arme principale + secondaire + 2 grenades
##                 (dictionnaire {name, primary, secondary}, voir WeaponCatalog).

## Spécialistes jouables, dans l'ordre d'affichage. Ajouter un spécialiste = ajouter son .tres ici.
const CLASSES: Array[ClassData] = [
	preload("res://data/classes/tank.tres"),
	preload("res://data/classes/assassin.tres"),
	preload("res://data/classes/tireur.tres"),
	preload("res://data/classes/oni.tres"),
]

## Copie locale des classes : sert hors ligne et si le back ne répond pas.
const LOADOUTS_PATH := "user://loadouts.cfg"

signal loadouts_changed

## Spécialiste choisi par le joueur (par défaut : le premier).
var selected_class: ClassData = CLASSES[0]
## Classes du joueur (10 au maximum) et celle choisie pour la prochaine apparition.
var loadouts: Array = []
var selected_loadout := 0

## Map des parties hors ligne (solo, entraînement) ; en LAN, c'est le chef qui choisit.
var map_id := MapCatalog.DEFAULT_ID


## Identifiant d'une classe, partagé avec le back (classe de chaque membre du groupe) :
## le nom de son fichier .tres (« tank », « assassin », « tireur »).
static func class_id(cls: ClassData) -> String:
	return cls.resource_path.get_file().get_basename()


## Classe d'après son identifiant ; la première si inconnu (ou pas encore envoyé).
static func class_from_id(id: Variant) -> ClassData:
	for cls in CLASSES:
		if class_id(cls) == str(id):
			return cls
	return CLASSES[0]


## Mode de la prochaine partie : "deathmatch" (bots, chronomètre, scores) ou "training" (mannequins).
var mode := "deathmatch"
## Durée d'une partie (secondes). Partie solo : nombre de bots (1 à MAX_SOLO_BOTS) et
## leur niveau (indice dans BotBrain.LEVELS), choisis avant de lancer, gardés pour la session.
var match_duration := 180.0
var bot_count := 5
var bot_level := BotBrain.NORMAL
const MAX_SOLO_BOTS := 15
## Réglages de départ de la prochaine partie en ligne, envoyés avec la réservation :
## bots (0 à 15), durée en secondes (60 à 600). Le chef les change dans le salon du
## serveur (lobby_screen.gd), qui les garde ici pour le lancement suivant.
var online_settings := {"bots": 2, "duration": 180}


func _ready() -> void:
	_load_local()


## Classe choisie (toujours valide).
func current_loadout() -> Dictionary:
	if loadouts.is_empty():
		loadouts = WeaponCatalog.sanitize_list([])
	selected_loadout = clampi(selected_loadout, 0, loadouts.size() - 1)
	return loadouts[selected_loadout]


## Remplace toutes les classes (après édition ou chargement depuis le back) et
## met à jour la copie locale. La sauvegarde sur le compte est faite par l'appelant
## (Backend.save_loadouts), pour qu'il puisse afficher une erreur.
func set_loadouts(list: Array, selected := -1) -> void:
	loadouts = WeaponCatalog.sanitize_list(list)
	if selected >= 0:
		selected_loadout = selected
	selected_loadout = clampi(selected_loadout, 0, loadouts.size() - 1)
	_save_local()
	loadouts_changed.emit()


func select_loadout(index: int) -> void:
	selected_loadout = clampi(index, 0, loadouts.size() - 1)
	_save_local()


func _load_local() -> void:
	var cfg := ConfigFile.new()
	var list := []
	if cfg.load(LOADOUTS_PATH) == OK:
		list = cfg.get_value("classes", "list", [])
		selected_loadout = int(cfg.get_value("classes", "selected", 0))
		var spec := str(cfg.get_value("classes", "specialist", ""))
		for c in CLASSES:
			if c.resource_path == spec:
				selected_class = c
	loadouts = WeaponCatalog.sanitize_list(list)
	selected_loadout = clampi(selected_loadout, 0, loadouts.size() - 1)


func _save_local() -> void:
	if Effects.headless():
		return    # le serveur dédié n'a pas de classes à lui
	var cfg := ConfigFile.new()
	cfg.set_value("classes", "list", loadouts)
	cfg.set_value("classes", "selected", selected_loadout)
	cfg.set_value("classes", "specialist", selected_class.resource_path)
	cfg.save(LOADOUTS_PATH)


## Spécialiste choisi (mémorisé avec les classes).
func select_specialist(data: ClassData) -> void:
	selected_class = data
	_save_local()
