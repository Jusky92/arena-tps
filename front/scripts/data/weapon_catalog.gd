class_name WeaponCatalog
extends RefCounted
## Liste des armes jouables et règles des classes (équipements).
##
## Une classe = {name, primary, secondary} : identifiants d'armes (WeaponData.id).
## Les 2 grenades sont toujours incluses. N'importe quel spécialiste peut prendre
## n'importe quelle classe. Ajouter une arme = créer son .tres et l'ajouter à WEAPONS.

const WEAPONS: Array[WeaponData] = [
	preload("res://data/weapons/mitraillette.tres"),
	preload("res://data/weapons/pompe.tres"),
	preload("res://data/weapons/sniper.tres"),
	preload("res://data/weapons/roquettes.tres"),
	preload("res://data/weapons/lance_flammes.tres"),
	preload("res://data/weapons/laser.tres"),
	preload("res://data/weapons/katana.tres"),
	preload("res://data/weapons/lance_caca.tres"),
]
const GRENADE: WeaponData = preload("res://data/weapons/grenade.tres")
const GRENADES_PER_LIFE := 2
const MAX_LOADOUTS := 10
const NAME_MAX_LENGTH := 24

## Classes proposées au premier lancement (modifiables dans l'accueil).
const DEFAULT_LOADOUTS := [
	{"name": "Assaut", "primary": "smg", "secondary": "laser"},
	{"name": "Corps à corps", "primary": "shotgun", "secondary": "katana"},
	{"name": "Précision", "primary": "sniper", "secondary": "laser"},
	{"name": "Démolition", "primary": "rocket", "secondary": "poop"},
	{"name": "Incendiaire", "primary": "flamer", "secondary": "katana"},
]


## Arme d'après son identifiant (null si inconnue). La grenade est incluse.
static func find(weapon_id: String) -> WeaponData:
	for w in WEAPONS:
		if w.id == weapon_id:
			return w
	return GRENADE if weapon_id == GRENADE.id else null


## Arme d'après son nom affiché (le fil des éliminations ne reçoit que le nom).
static func find_by_name(display_name: String) -> WeaponData:
	for w in WEAPONS:
		if w.display_name == display_name:
			return w
	return GRENADE if display_name == GRENADE.display_name else null


static func primaries() -> Array[WeaponData]:
	return _of_slot(WeaponData.Slot.PRIMARY)


static func secondaries() -> Array[WeaponData]:
	return _of_slot(WeaponData.Slot.SECONDARY)


static func _of_slot(slot: WeaponData.Slot) -> Array[WeaponData]:
	var out: Array[WeaponData] = []
	for w in WEAPONS:
		if w.slot == slot:
			out.append(w)
	return out


## true si les deux armes existent et sont à la bonne place.
static func is_valid_loadout(primary_id: String, secondary_id: String) -> bool:
	var p := find(primary_id)
	var s := find(secondary_id)
	return p != null and s != null and p.slot == WeaponData.Slot.PRIMARY and s.slot == WeaponData.Slot.SECONDARY


## Copie propre d'une classe (nom raccourci, armes valides sinon celles par défaut).
static func sanitize(loadout: Dictionary) -> Dictionary:
	var name := str(loadout.get("name", "Classe")).strip_edges().left(NAME_MAX_LENGTH)
	var primary := str(loadout.get("primary", ""))
	var secondary := str(loadout.get("secondary", ""))
	if not is_valid_loadout(primary, secondary):
		primary = DEFAULT_LOADOUTS[0].primary
		secondary = DEFAULT_LOADOUTS[0].secondary
	return {"name": name if not name.is_empty() else "Classe", "primary": primary, "secondary": secondary}


## Liste de classes nettoyée (10 au maximum ; les classes par défaut si vide).
static func sanitize_list(list: Array) -> Array:
	var out := []
	for l in list:
		if l is Dictionary and out.size() < MAX_LOADOUTS:
			out.append(sanitize(l))
	if out.is_empty():
		for l in DEFAULT_LOADOUTS:
			out.append(l.duplicate())
	return out


## Classe tirée au hasard (bots).
static func random_loadout() -> Dictionary:
	var p := primaries()
	var s := secondaries()
	return {"name": "Bot", "primary": p[randi() % p.size()].id, "secondary": s[randi() % s.size()].id}
