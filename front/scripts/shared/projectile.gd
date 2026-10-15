class_name Projectile
extends Node3D
## Projectile simulé image par image : roquette, boule du lance-caca, grenade.
##
## Deux usages, même trajectoire :
##   - « qui fait foi » (authoritative = true) : sur le serveur dédié, ou hors ligne.
##     Il détecte les collisions, rebondit (grenade), puis émet `exploded` ; c'est la
##     partie (server_game.gd ou game.gd) qui applique les dégâts et les effets ;
##   - visuel seulement (authoritative = false) : sur les clients en ligne. Il suit la
##     même trajectoire pour l'affichage et disparaît quand le serveur annonce
##     l'explosion (Net.push_explosion), ou au bout de LIFETIME secondes.

signal exploded(projectile: Projectile, position: Vector3, direct_target: Node)

const LIFETIME := 8.0
const ARM_TIME := 0.08            # le tireur ne peut pas se toucher juste au départ
const RADIUS := 0.12              # rayon de collision (lancer de rayon + marge)
## Emplacement des grenades dans l'arsenal tenu par le serveur (0 = principale,
## 1 = secondaire, 2 = arme spéciale).
const GRENADE_SLOT := 9

var id := 0                       ## identifiant réseau (attribué par le serveur)
var data: WeaponData
var shooter: Node                 ## qui a tiré (peut avoir disparu entre-temps)
var shooter_id := 0
var velocity := Vector3.ZERO
var authoritative := true

var _age := 0.0
var _travelled := 0.0
var _done := false
var _visual: Node3D


func setup(weapon: WeaponData, from: Node, origin: Vector3, start_velocity: Vector3, is_authoritative: bool) -> void:
	data = weapon
	shooter = from
	shooter_id = from.peer_id if from != null and "peer_id" in from else 0
	velocity = start_velocity
	authoritative = is_authoritative
	position = origin


func _ready() -> void:
	if not Effects.headless():
		_visual = Effects.projectile_visual(data)
		add_child(_visual)


func _physics_process(delta: float) -> void:
	if _done:
		return
	_age += delta
	velocity.y -= data.projectile_gravity * delta
	var from := global_position
	var to := from + velocity * delta

	var bounces := data.fuse_time > 0.0 and data.bounce > 0.0
	# Grenade : rebonds calculés aussi pour l'affichage (même trajectoire, et le son du
	# rebond) ; l'explosion, elle, reste décidée par la version qui fait foi.
	if authoritative or bounces:
		var hit := _cast(from, to)
		if not hit.is_empty():
			var target: Object = hit.collider
			if bounces:
				var normal: Vector3 = hit.normal
				if velocity.length() > 2.0:
					Sfx.play_at("grenade_bounce", hit.position, -4.0, 1.0, 50.0)
				velocity = velocity.bounce(normal) * data.bounce
				to = (hit.position as Vector3) + normal * RADIUS
			else:
				global_position = hit.position
				_explode(target if target.has_method("take_damage") else null)
				return

	global_position = to
	_travelled += from.distance_to(to)
	if _visual and velocity.length_squared() > 0.01:
		_visual.look_at(global_position + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.RIGHT)

	if data.fuse_time > 0.0:
		if _age >= data.fuse_time and authoritative:
			_explode(null)
	elif _travelled >= data.max_range and authoritative:
		_explode(null)
	if _age >= LIFETIME:
		queue_free()


## Lancer de rayon du dernier pas (décor et personnages), sans le tireur au départ.
func _cast(from: Vector3, to: Vector3) -> Dictionary:
	if from.is_equal_approx(to):
		return {}
	var query := PhysicsRayQueryParameters3D.create(from, to + (to - from).normalized() * RADIUS)
	if _age < ARM_TIME and shooter != null and is_instance_valid(shooter) and shooter is CollisionObject3D:
		query.exclude = [(shooter as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	# Un personnage sous protection d'apparition ou mort ne fait pas exploser la roquette.
	if not hit.is_empty() and hit.collider.has_method("is_protected") and hit.collider.is_protected():
		return {}
	return hit


func _explode(direct_target: Node) -> void:
	if _done:
		return
	_done = true
	exploded.emit(self, global_position, direct_target)
	queue_free()


## Fin annoncée par le serveur (projectile visuel) : on le place à l'endroit exact.
func finish(at: Vector3) -> void:
	_done = true
	global_position = at
	queue_free()


## Lance un projectile. En ligne, c'est le serveur qui le simule et l'annonce à tous
## (Net.fire_projectile) ; hors ligne, la partie (groupe "projectile_host") le crée.
## `slot` : 0 = principale, 1 = secondaire, 2 = arme spéciale, GRENADE_SLOT = grenade
## (munitions tenues par le serveur).
static func launch(from_node: Node, weapon: WeaponData, shooter: Node, slot: int, origin: Vector3, start_velocity: Vector3) -> void:
	if Net.online and "peer_id" in shooter and shooter.peer_id != 0:
		Net.fire_projectile(shooter.peer_id, slot, origin, start_velocity)
		return
	var host := from_node.get_tree().get_first_node_in_group("projectile_host")
	if host:
		host.launch_projectile(weapon, shooter, origin, start_velocity)
