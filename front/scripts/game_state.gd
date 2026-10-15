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

## Mode de la prochaine partie : "deathmatch" (bots, chronomètre, scores) ou "training" (mannequins).
var mode := "deathmatch"
## Durée d'une partie (secondes) et nombre de bots pour compléter le serveur.
var match_duration := 180.0
var bot_count := 5
## Niveau des bots hors ligne (voir BotBrain.LEVELS) ; en LAN, c'est le chef qui choisit.
var bot_level := "moyen"

## Réglages de la partie solo, gardés d'une fois sur l'autre.
const SOLO_PATH := "user://partie_solo.cfg"


func _ready() -> void:
	_load_local()
	_load_solo()


## Réglages de la partie solo (map, bots, niveau, durée).
func save_solo() -> void:
	if Effects.headless():
		return
	var cfg := ConfigFile.new()
	cfg.set_value("solo", "map", map_id)
	cfg.set_value("solo", "bots", bot_count)
	cfg.set_value("solo", "level", bot_level)
	cfg.set_value("solo", "duration", match_duration)
	cfg.save(SOLO_PATH)


func _load_solo() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SOLO_PATH) != OK:
		return
	map_id = MapCatalog.valid_id(str(cfg.get_value("solo", "map", map_id)))
	bot_count = clampi(int(cfg.get_value("solo", "bots", bot_count)), 1, 15)
	bot_level = BotBrain.valid_level(str(cfg.get_value("solo", "level", bot_level)))
	match_duration = clampf(float(cfg.get_value("solo", "duration", match_duration)), 60.0, 600.0)


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
