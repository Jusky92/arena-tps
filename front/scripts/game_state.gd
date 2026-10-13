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

## Mode de la prochaine partie : "deathmatch" (bots, chronomètre, scores) ou "training" (mannequins).
var mode := "deathmatch"
## Durée d'une partie (secondes) et nombre de bots pour compléter le serveur.
var match_duration := 180.0
var bot_count := 5
