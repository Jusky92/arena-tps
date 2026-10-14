class_name UiIcons
extends RefCounted
## Icônes de l'interface (assets/ui/icons/*.svg, blanches : on les colore avec modulate).
## Les icônes d'arme et de capacité se déduisent des fiches (WeaponData.model,
## ClassData.ability) : une nouvelle arme d'un modèle existant a déjà son icône.

const HEALTH := preload("res://assets/ui/icons/health.svg")
const AMMO := preload("res://assets/ui/icons/ammo.svg")
const SKULL := preload("res://assets/ui/icons/skull.svg")

const WEAPONS := {
	WeaponData.Model.SHOTGUN: preload("res://assets/ui/icons/shotgun.svg"),
	WeaponData.Model.SMG: preload("res://assets/ui/icons/smg.svg"),
	WeaponData.Model.SNIPER: preload("res://assets/ui/icons/sniper.svg"),
}

const ABILITIES := {
	ClassData.Ability.SHIELD: preload("res://assets/ui/icons/shield.svg"),
	ClassData.Ability.DASH: preload("res://assets/ui/icons/dash.svg"),
	ClassData.Ability.PIERCE: preload("res://assets/ui/icons/pierce.svg"),
}


static func weapon(data: WeaponData) -> Texture2D:
	return WEAPONS.get(data.model) if data else null


static func ability(data: ClassData) -> Texture2D:
	return ABILITIES.get(data.ability) if data else null


## Icône d'une arme d'après son nom affiché (le fil des éliminations ne reçoit que le nom).
## null si le nom ne correspond à aucune arme (ex. "Arène").
static func weapon_by_name(display_name: String) -> Texture2D:
	for cls: ClassData in GameState.CLASSES:
		if cls.weapon and cls.weapon.display_name == display_name:
			return weapon(cls.weapon)
	return null
