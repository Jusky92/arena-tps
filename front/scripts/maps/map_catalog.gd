class_name MapCatalog
extends RefCounted
## Maps jouables. Chaque map est une scène dont le script hérite d'ArenaMap et
## répond aux mêmes questions : points d'apparition, bonus, cibles d'entraînement,
## zone de navigation des bots (voir ArenaMap : spawn_points(), pickup_points()…).
##
## L'identifiant voyage sur le réseau (réglages du salon) et part au back (Server
## List, match.finished). Ajouter une map = créer sa scène et l'ajouter ici.

const MAPS := [
	{"id": "neo-edo", "name": "NEO-EDO", "scene": "res://scenes/maps/arena.tscn",
		"subtitle": "Quartier japonais néon · 120 × 120 m"},
	{"id": "hikari-mall", "name": "Hikari Mall", "scene": "res://scenes/maps/mall.tscn",
		"subtitle": "Centre commercial abandonné · 100 × 100 m · 2 niveaux"},
]
const DEFAULT_ID := "neo-edo"


static func find(map_id: String) -> Dictionary:
	for m in MAPS:
		if m.id == map_id:
			return m
	return MAPS[0]


static func is_valid(map_id: String) -> bool:
	return MAPS.any(func(m): return m.id == map_id)


static func scene_of(map_id: String) -> PackedScene:
	return load(find(map_id).scene)


static func name_of(map_id: String) -> String:
	return find(map_id).name


## Identifiant valide (celui donné, sinon la map par défaut).
static func valid_id(map_id: String) -> String:
	return map_id if is_valid(map_id) else DEFAULT_ID
