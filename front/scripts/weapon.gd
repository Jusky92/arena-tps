extends Node3D
## Arme générique : son comportement vient entièrement de sa fiche WeaponData
## (dégâts, nombre de plombs, cadence, dispersion…). Le même script sert donc
## au fusil à pompe, à la mitraillette et au fusil de précision.

signal fired(recoil_deg: float)
signal ammo_changed(ammo: int, mag_size: int, reloading: bool)
signal hit_confirmed(killed: bool)

const MAX_PIERCE := 5  # nombre max de cibles traversées par une balle perforante

@onready var muzzle: Marker3D = $Muzzle

var data: WeaponData
var piercing: bool = false        ## activé par la capacité "Tir perforant"
var ammo: int = 0

var _shooter: CollisionObject3D   # celui qui tient l'arme (exclu des tirs)
var _camera: Camera3D
var _cooldown: float = 0.0
var _reload_timer: float = 0.0


func setup(weapon_data: WeaponData, shooter: CollisionObject3D, camera: Camera3D) -> void:
	data = weapon_data
	_shooter = shooter
	_camera = camera
	refill()


## Remet le chargeur plein (réapparition).
func refill() -> void:
	ammo = data.mag_size
	_reload_timer = 0.0
	_cooldown = 0.0
	ammo_changed.emit(ammo, data.mag_size, false)


func is_reloading() -> bool:
	return _reload_timer > 0.0


func reload_progress() -> float:
	return 1.0 - _reload_timer / data.reload_time if is_reloading() else 1.0


## À appeler à chaque image physique par le joueur.
## spread_factor < 1 rend le tir plus précis (ex. accroupi).
func update(delta: float, trigger_held: bool, trigger_pressed: bool, aiming: bool, spread_factor := 1.0) -> void:
	_cooldown = max(_cooldown - delta, 0.0)

	if is_reloading():
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			ammo = data.mag_size
			ammo_changed.emit(ammo, data.mag_size, false)
		return

	var wants_fire := trigger_held if data.automatic else trigger_pressed
	if wants_fire:
		_try_fire(aiming, spread_factor)


func start_reload() -> void:
	if is_reloading() or ammo == data.mag_size:
		return
	_reload_timer = data.reload_time
	ammo_changed.emit(ammo, data.mag_size, true)


func _try_fire(aiming: bool, spread_factor := 1.0) -> void:
	if _cooldown > 0.0:
		return
	if ammo <= 0:
		start_reload()
		return

	ammo -= 1
	_cooldown = 1.0 / data.fire_rate
	ammo_changed.emit(ammo, data.mag_size, false)

	var spread := (data.aim_spread_deg if aiming else data.spread_deg) * spread_factor
	var any_hit := false
	var any_kill := false
	for i in data.pellets:
		var result := _fire_pellet(spread)
		any_hit = any_hit or result.hit
		any_kill = any_kill or result.killed
	if any_hit:
		hit_confirmed.emit(any_kill)

	Effects.muzzle_flash(muzzle, data.tracer_color)
	fired.emit(data.recoil_deg)

	if ammo == 0:
		start_reload()  # rechargement automatique


## Un projectile. Le tir se fait en deux temps :
## 1. un rayon depuis la caméra (avec dispersion) trouve le point visé ;
## 2. un rayon depuis le canon vers ce point applique les dégâts
##    (on ne peut donc pas tirer "à travers" un mur collé au personnage).
func _fire_pellet(spread_deg: float) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var cam_from := _camera.global_position
	var cam_dir := _spread_direction(-_camera.global_basis.z, spread_deg)
	var cam_to := cam_from + cam_dir * data.max_range
	var aim_hit := _raycast(space, cam_from, cam_to, [])
	var aim_point: Vector3 = aim_hit.position if aim_hit else cam_to

	var from := muzzle.global_position
	var dir := (aim_point - from).normalized()
	var to := from + dir * data.max_range

	var result := {"hit": false, "killed": false}
	var exclude: Array[RID] = []
	var end_point := to
	var pierce_left := MAX_PIERCE if piercing else 1

	while pierce_left > 0:
		var hit := _raycast(space, from, to, exclude)
		if hit.is_empty():
			break
		end_point = hit.position
		var target: Object = hit.collider
		if target.has_method("is_protected") and target.is_protected():
			# Joueur sous protection d'apparition : la balle est déviée, aucun dégât.
			Effects.impact(_world(), hit.position, Color(0.35, 0.95, 1.0), 0.14)
			Sfx.play_at("deflect", hit.position, -6.0, randf_range(0.9, 1.1))
			break
		if target.has_method("take_damage"):
			Effects.impact(_world(), hit.position, Color(1, 0.25, 0.2), 0.09)
			var killed: bool = target.take_damage(data.damage, _shooter)
			result.hit = true
			result.killed = result.killed or killed
			exclude.append(hit.rid)
			pierce_left -= 1
		else:
			Effects.impact(_world(), hit.position, data.tracer_color)
			break  # un mur arrête toujours la balle

	var color := data.tracer_color.lightened(0.4) if piercing else data.tracer_color
	Effects.tracer(_world(), from, end_point, color)
	return result


## Direction légèrement déviée au hasard dans un cône de `spread_deg` degrés.
func _spread_direction(forward: Vector3, spread_deg: float) -> Vector3:
	if spread_deg <= 0.0:
		return forward
	var basis := _camera.global_basis
	var radius := tan(deg_to_rad(spread_deg)) * sqrt(randf())  # répartition uniforme dans le disque
	var angle := randf() * TAU
	return (forward + basis.x * cos(angle) * radius + basis.y * sin(angle) * radius).normalized()


func _raycast(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, extra_exclude: Array[RID]) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var exclude: Array[RID] = [_shooter.get_rid()]
	exclude.append_array(extra_exclude)
	query.exclude = exclude
	return space.intersect_ray(query)


## Nœud où placer les effets (la scène de jeu), pour qu'ils ne suivent pas le joueur.
func _world() -> Node:
	return get_tree().current_scene if get_tree().current_scene else _shooter.get_parent()
