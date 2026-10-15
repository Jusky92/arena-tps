extends Node
## Données partagées entre les écrans (menu, choix de classe, partie).
## Chargé automatiquement au démarrage (autoload "GameState").

## Classes jouables, dans l'ordre d'affichage. Ajouter une classe = ajouter son .tres ici.
const CLASSES: Array[ClassData] = [
	preload("res://data/classes/tank.tres"),
	preload("res://data/classes/assassin.tres"),
	preload("res://data/classes/tireur.tres"),
]

## Classe choisie par le joueur (par défaut : la première).
var selected_class: ClassData = CLASSES[0]


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
## Durée d'une partie (secondes) et nombre de bots pour compléter le serveur.
var match_duration := 180.0
var bot_count := 5
## Réglages de la prochaine partie en ligne, choisis par le chef sur la page de lancement
## et appliqués par le serveur dédié : bots (0 à 7), durée en secondes (60 à 600).
## La carte et le mode de jeu s'y ajouteront.
var online_settings := {"bots": 2, "duration": 180}
