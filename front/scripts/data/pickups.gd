class_name Pickups
extends RefCounted
## Bonus posés sur la map (phase 4) : types, réglages et emplacements.
##
## Les bonus sont décidés par la partie qui fait foi : le serveur dédié en ligne,
## la partie locale hors ligne (PickupDirector). Les clients ne font qu'afficher.

enum Kind { HEAL, ARMOR, DOUBLE_JUMP, SPEED, MINIGUN, LASER_RIFLE, POWER_FIST, SUPER }
## Super-pouvoirs (bonus SUPER : l'un des trois, tiré au hasard, déclenché avec F).
enum Super { OVERLOAD, SHOCKWAVE, INVISIBILITY }

const HEAL_AMOUNT := 50
const ARMOR_AMOUNT := 50
const ARMOR_MAX := 100
const DOUBLE_JUMP_TIME := 30.0
const SPEED_TIME := 12.0
const SPEED_BONUS := 0.35            ## +35 % de vitesse
const OVERLOAD_TIME := 12.0
const OVERLOAD_DAMAGE := 1.5         ## dégâts x1,5
const OVERLOAD_SPEED := 0.25         ## +25 % de vitesse
const INVISIBILITY_TIME := 10.0
const INVISIBILITY_REVEAL := 1.0     ## tirer dévoile pendant ce temps (s)
const PICK_RADIUS := 1.6             ## distance de ramassage (m, à l'horizontale)

## Réglages par type : nom affiché, couleur, réapparition (s), arme spéciale donnée.
const INFO := {
	Kind.HEAL: {"name": "Soin", "color": Color(0.32, 0.95, 0.55), "respawn": 20.0},
	Kind.ARMOR: {"name": "Armure", "color": Color(0.35, 0.65, 1.0), "respawn": 30.0},
	Kind.DOUBLE_JUMP: {"name": "Double saut", "color": Color(0.85, 0.95, 1.0), "respawn": 40.0},
	Kind.SPEED: {"name": "Vitesse", "color": Color(1.0, 0.84, 0.25), "respawn": 35.0},
	Kind.MINIGUN: {"name": "Sulfateuse", "color": Color(1.0, 0.5, 0.2), "respawn": 60.0, "weapon": "minigun"},
	Kind.LASER_RIFLE: {"name": "Fusil laser", "color": Color(0.25, 0.95, 1.0), "respawn": 60.0, "weapon": "laser_rifle"},
	Kind.POWER_FIST: {"name": "Poing puissant", "color": Color(1.0, 0.3, 0.75), "respawn": 60.0, "weapon": "power_fist"},
	Kind.SUPER: {"name": "Super-pouvoir", "color": Color(0.95, 0.27, 0.78), "respawn": 90.0},
}

const SUPER_INFO := {
	Super.OVERLOAD: {"name": "Surcharge néon", "color": Color(0.95, 0.27, 0.78)},
	Super.SHOCKWAVE: {"name": "Onde de choc", "color": Color(1.0, 0.55, 0.2)},
	Super.INVISIBILITY: {"name": "Invisibilité", "color": Color(0.6, 0.85, 1.0)},
}

## Onde de choc : explosion autour du joueur (fiche d'arme dédiée, sans dégâts sur soi).
const SHOCKWAVE: WeaponData = preload("res://data/weapons/onde_de_choc.tres")


static func name_of(kind: int) -> String:
	return INFO[kind].name


static func color_of(kind: int) -> Color:
	return INFO[kind].color


static func respawn_of(kind: int) -> float:
	return INFO[kind].respawn


## Arme spéciale donnée par ce bonus ("" si ce n'en est pas un).
static func weapon_of(kind: int) -> String:
	return INFO[kind].get("weapon", "")


static func random_super() -> int:
	return randi() % Super.size()
