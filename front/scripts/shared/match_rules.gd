class_name MatchRules
extends RefCounted
## Règles de partie communes au jeu hors ligne (scripts/game.gd) et au serveur
## dédié (scripts/server/server_game.gd). Fonctions "static" : MatchRules.best_spawn(...).

const RESPAWN_DELAY := 3.0
## Nom de la map tel qu'il part au back (Server List, match.finished).
const MAP_ID := "neo-edo"


## Point d'apparition le plus éloigné des adversaires vivants (un peu de hasard).
static func best_spawn(map: ArenaMap, players: Array, for_player: Node) -> Transform3D:
	var spawns := map.get_spawn_transforms()
	var scored := []
	for t in spawns:
		var nearest := INF
		for other in players:
			if other != for_player and is_instance_valid(other) and other.alive:
				nearest = minf(nearest, t.origin.distance_to(other.global_position))
		scored.append([nearest + randf() * 8.0, t])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	return scored[0][1]


## Dégâts réellement subis : le bouclier (capacité du Tank) les réduit.
static func damage_taken(target: Node, damage: int) -> int:
	if target.has_method("is_shielded") and target.is_shielded():
		return maxi(int(round(damage * target.class_data.ability_strength)), 1)
	return damage


# ---------------------------------------------------------------- Zones de tir

## Hauteur de la zone "tête", mesurée depuis le haut de la capsule de collision.
const HEAD_SIZE := 0.32


## Hauteur actuelle de la cible (sa capsule rapetisse quand elle s'accroupit).
static func body_height(target: Node) -> float:
	var shape: Shape3D = target.collision.shape
	return (shape as CapsuleShape3D).height if shape is CapsuleShape3D else 1.8


## true si l'impact est dans la tête. `hit_offset` = point touché - position de la
## cible (ses pieds) : seule la hauteur compte.
static func is_headshot(target: Node, hit_offset: Vector3) -> bool:
	return hit_offset.y >= body_height(target) - HEAD_SIZE


## Dégâts d'une balle (un plomb), multipliés pour la tête. Le bouclier de la cible
## s'applique ensuite (damage_taken, ou take_damage hors ligne).
static func hit_damage(weapon: WeaponData, headshot: bool) -> int:
	return int(round(float(weapon.damage) * (weapon.headshot_multiplier if headshot else 1.0)))


## Calcule le maillage de navigation (zones où l'on peut marcher) à partir des
## collisions de la map, l'ajoute sous `parent` et renvoie la carte de navigation.
static func bake_navigation(parent: Node3D, map: ArenaMap) -> RID:
	var navmesh := NavigationMesh.new()
	navmesh.agent_radius = 0.5
	navmesh.agent_height = 1.75
	navmesh.agent_max_climb = 0.25
	navmesh.agent_max_slope = 46.0
	navmesh.cell_size = 0.25
	navmesh.cell_height = 0.25
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navmesh.filter_baking_aabb = AABB(Vector3(-61, -1, -61), Vector3(122, 16, 122))
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(navmesh, source, map)
	NavigationServer3D.bake_from_source_geometry_data(navmesh, source)
	var region := NavigationRegion3D.new()
	region.navigation_mesh = navmesh
	parent.add_child(region)
	return parent.get_world_3d().navigation_map


## Points de patrouille des bots.
static func roam_points() -> Array:
	var points := []
	points.append_array(ArenaMap.SPAWN_POINTS)
	points.append_array(ArenaMap.TARGET_POINTS)
	return points


## Classement : 1 = vainqueur. Plus d'éliminations d'abord, puis moins de morts.
## `rows` contient des dictionnaires avec au moins `kills` et `deaths` ; ils sont
## triés sur place et reçoivent un champ `placement`. Deux joueurs à égalité
## parfaite partagent la même place.
static func rank(rows: Array) -> Array:
	rows.sort_custom(func(a, b): return a.kills > b.kills or (a.kills == b.kills and a.deaths < b.deaths))
	for i in rows.size():
		var tied: bool = i > 0 and rows[i].kills == rows[i - 1].kills and rows[i].deaths == rows[i - 1].deaths
		rows[i]["placement"] = rows[i - 1].placement if tied else i + 1
	return rows
