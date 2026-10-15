class_name UiIcons
extends RefCounted
## Icônes de l'interface (assets/ui/icons/*.svg, blanches : on les colore avec modulate).
## Les icônes d'arme et de capacité se déduisent des fiches (WeaponData.model,
## ClassData.ability) : une nouvelle arme d'un modèle existant a déjà son icône.

const HEALTH := preload("res://assets/ui/icons/health.svg")
const AMMO := preload("res://assets/ui/icons/ammo.svg")
const SKULL := preload("res://assets/ui/icons/skull.svg")
const GRENADE := preload("res://assets/ui/icons/grenade.svg")

const WEAPONS := {
	WeaponData.Model.SHOTGUN: preload("res://assets/ui/icons/shotgun.svg"),
	WeaponData.Model.SMG: preload("res://assets/ui/icons/smg.svg"),
	WeaponData.Model.SNIPER: preload("res://assets/ui/icons/sniper.svg"),
	WeaponData.Model.ROCKET: preload("res://assets/ui/icons/rocket.svg"),
	WeaponData.Model.FLAMER: preload("res://assets/ui/icons/flamer.svg"),
	WeaponData.Model.LASER: preload("res://assets/ui/icons/laser.svg"),
	WeaponData.Model.KATANA: preload("res://assets/ui/icons/katana.svg"),
	WeaponData.Model.POOP: preload("res://assets/ui/icons/poop.svg"),
	WeaponData.Model.GRENADE: preload("res://assets/ui/icons/grenade.svg"),
	WeaponData.Model.MINIGUN: preload("res://assets/ui/icons/minigun.svg"),
	WeaponData.Model.LASER_RIFLE: preload("res://assets/ui/icons/laser_rifle.svg"),
	WeaponData.Model.FIST: preload("res://assets/ui/icons/fist.svg"),
	WeaponData.Model.ASSAULT: preload("res://assets/ui/icons/assault.svg"),
	WeaponData.Model.SHOGUN: preload("res://assets/ui/icons/shogun.svg"),
}

const ABILITIES := {
	ClassData.Ability.SHIELD: preload("res://assets/ui/icons/shield.svg"),
	ClassData.Ability.DASH: preload("res://assets/ui/icons/dash.svg"),
	ClassData.Ability.PIERCE: preload("res://assets/ui/icons/pierce.svg"),
	ClassData.Ability.CHARGE: preload("res://assets/ui/icons/charge.svg"),
}


static func weapon(data: WeaponData) -> Texture2D:
	return WEAPONS.get(data.model) if data else null


static func ability(data: ClassData) -> Texture2D:
	return ABILITIES.get(data.ability) if data else null


## Icône d'une arme d'après son nom affiché (le fil des éliminations ne reçoit que le nom).
## null si le nom ne correspond à aucune arme (ex. "Arène").
static func weapon_by_name(display_name: String) -> Texture2D:
	return weapon(WeaponCatalog.find_by_name(display_name))
