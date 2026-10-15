class_name MatchRules
extends RefCounted
## Règles de partie communes au jeu hors ligne (scripts/game.gd) et au serveur
## dédié (scripts/server/server_game.gd). Fonctions "static" : MatchRules.best_spawn(...).

const RESPAWN_DELAY := 3.0
## Map par défaut (identifiants : voir MapCatalog ; la map en cours répond à map_id()).
const MAP_ID := MapCatalog.DEFAULT_ID


## Point d'apparition le plus éloigné des adversaires vivants (un peu de hasard).
static func best_spawn(map: Node3D, players: Array, for_player: Node) -> Transform3D:
	var spawns: Array = map.get_spawn_transforms()
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
static func bake_navigation(parent: Node3D, map: Node3D) -> RID:
	var navmesh := NavigationMesh.new()
	navmesh.agent_radius = 0.5
	navmesh.agent_height = 1.75
	navmesh.agent_max_climb = 0.25
	navmesh.agent_max_slope = 46.0
	navmesh.cell_size = 0.25
	navmesh.cell_height = 0.25
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navmesh.filter_baking_aabb = map.nav_aabb()
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(navmesh, source, map)
	NavigationServer3D.bake_from_source_geometry_data(navmesh, source)
	var region := NavigationRegion3D.new()
	region.navigation_mesh = navmesh
	parent.add_child(region)
	return parent.get_world_3d().navigation_map


## Points de patrouille des bots.
static func roam_points(map: Node3D) -> Array:
	var points := []
	points.append_array(map.spawn_points())
	points.append_array(map.target_points())
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


## true si le personnage doit être recréé pour la réapparition : autre spécialiste
## ou autre classe (armes différentes).
static func needs_rebuild(node: Node, class_id: String, loadout: Dictionary) -> bool:
	if node.class_data.resource_path != class_id or node.weapons.size() < 2:
		return true
	return node.weapons[0].data.id != loadout.get("primary", node.weapons[0].data.id) \
		or node.weapons[1].data.id != loadout.get("secondary", node.weapons[1].data.id)


# ---------------------------------------------------------------- Explosions

## Victimes d'une explosion (roquette, grenade, lance-caca) :
## [{node, damage, direction}]. La cible touchée en plein (`direct`) prend les dégâts
## de l'arme, les autres des dégâts de zone qui baissent avec la distance (de
## splash_damage au centre à splash_min_damage au bord). Un mur entre le centre et la
## cible la protège. Le tireur prend self_damage_factor de ses propres dégâts de zone.
## `direction` : sens du recul (depuis le centre, un peu vers le haut).
static func explosion_victims(world: World3D, center: Vector3, weapon: WeaponData, shooter: Node, direct: Node) -> Array:
	var radius := maxf(weapon.splash_radius, 0.1)
	var shape := SphereShape3D.new()
	shape.radius = radius + 0.5
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), center)
	var space := world.direct_space_state
	var found := []
	var victims := []
	for hit in space.intersect_shape(query, 32):
		found.append(hit.collider)
	if direct != null and not direct in found:
		found.append(direct)
	for node in found:
		if not is_instance_valid(node) or not node.has_method("take_damage") or node in victims.map(func(v): return v.node):
			continue
		if node.get("alive") == false or (node.has_method("is_protected") and node.is_protected()):
			continue
		var point: Vector3 = (node as Node3D).global_position + Vector3.UP * body_height(node) * 0.5
		var distance := 0.0 if node == direct else center.distance_to(point)
		if distance > radius:
			continue
		if node != direct:
			var los := PhysicsRayQueryParameters3D.create(center, point)
			var exclude: Array[RID] = []
			for other in found:
				if other is CollisionObject3D:
					exclude.append((other as CollisionObject3D).get_rid())
			los.exclude = exclude
			if not space.intersect_ray(los).is_empty():
				continue       # un mur protège la cible
		var damage := float(weapon.damage) if node == direct and weapon.damage > 0 \
			else lerpf(weapon.splash_damage, weapon.splash_min_damage, clampf(distance / radius, 0.0, 1.0))
		if node == shooter:
			if weapon.self_damage_factor <= 0.0:
				continue
			damage *= weapon.self_damage_factor
		var away := point - center
		away.y = maxf(away.y, 0.0)
		var direction := (away.normalized() if away.length() > 0.05 else Vector3.ZERO) + Vector3.UP * 0.5
		victims.append({"node": node, "damage": int(round(damage)), "direction": direction.normalized()})
	return victims
