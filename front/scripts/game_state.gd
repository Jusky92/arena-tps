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
