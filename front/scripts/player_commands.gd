class_name PlayerCommands
extends RefCounted
## Commandes d'un joueur pour une image de simulation.
##
## Le joueur local les remplit avec le clavier et la souris, un bot avec son IA.
## Plus tard, en multijoueur, c'est exactement ce que le client enverra au serveur
## de jeu, qui simulera le déplacement, le tir et les dégâts (serveur autoritaire).

var move := Vector2.ZERO        ## direction voulue (x = droite, y = arrière), longueur max 1
var look := Vector2.ZERO        ## rotation à appliquer (radians) : x = gauche/droite, y = haut/bas
var jump := false               ## appui (une image)
var crouch := false             ## maintenu
var sprint := false             ## maintenu
var fire := false               ## maintenu
var fire_pressed := false       ## appui (armes coup par coup)
var aim := false                ## maintenu (clic droit)
var reload := false             ## appui
var ability := false            ## appui
var switch_to := -1             ## arme demandée (0 = principale, 1 = secondaire, -1 = aucune)
var grenade := false            ## appui : lancer une grenade


func clear() -> void:
	move = Vector2.ZERO
	look = Vector2.ZERO
	jump = false
	crouch = false
	sprint = false
	fire = false
	fire_pressed = false
	aim = false
	reload = false
	ability = false
	switch_to = -1
	grenade = false
