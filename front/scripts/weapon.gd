extends Node3D
## Arme générique : son comportement vient entièrement de sa fiche WeaponData.
## Le même script sert à toutes les armes ; la façon de tirer dépend de `data.kind` :
##   HITSCAN    balles instantanées (mitraillette, pompe, précision, pistolet laser)
##   MELEE      coup de katana dans un arc devant le joueur
##   FLAME      ticks de flammes dans un cône à courte portée (brûlure)
##   PROJECTILE roquette ou boule du lance-caca, simulée par le serveur
##
## En ligne, chaque tir est annoncé au serveur (Net.fire) avant les impacts : c'est
## lui qui tient le chargeur et calcule les dégâts. Les projectiles partent par
## Net.fire_projectile (le serveur les simule). Hors ligne, tout se passe ici.

signal fired(recoil_deg: float)
signal ammo_changed(ammo: int, mag_size: int, reloading: bool)
signal hit_confirmed(killed: bool, headshot: bool)
## Arme spéciale (bonus) vide : le joueur la lâche.
signal emptied

const MAX_PIERCE := 5     # nombre max de cibles traversées par une balle perforante
const FIRING_HOLD := 0.2  # durée pendant laquelle l'arme est « en train de tirer » (vu par les autres)
const AIM_RAY := 300.0    # longueur du rayon de visée depuis la caméra (m)

@onready var muzzle: Marker3D = $Muzzle

var data: WeaponData
var piercing: bool = false        ## activé par la capacité "Flèche perforante" (balles seulement)
var ammo: int = 0
## > 0 : l'arme a tiré il y a peu (diffusé aux autres joueurs : flammes, coup de katana).
var firing_time := 0.0

var _shooter: CollisionObject3D   # celui qui tient l'arme (exclu des tirs)
var _camera: Camera3D
var _cooldown: float = 0.0
var _reload_timer: float = 0.0
var _remote_fx := 0.0             # cadence des effets d'un personnage distant


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
	return 1.0 - _reload_timer / data.reload_time if is_reloading() and data.reload_time > 0.0 else 1.0


## À appeler à chaque image physique par le joueur.
## spread_factor < 1 rend le tir plus précis (ex. accroupi).
func update(delta: float, trigger_held: bool, trigger_pressed: bool, aiming: bool, spread_factor := 1.0) -> void:
	_cooldown = max(_cooldown - delta, 0.0)
	firing_time = maxf(firing_time - delta, 0.0)

	if is_reloading():
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			ammo = data.mag_size
			ammo_changed.emit(ammo, data.mag_size, false)
		return

	var wants_fire := trigger_held if data.automatic else trigger_pressed
	if wants_fire:
		_try_fire(aiming, spread_factor)


## Annule le rechargement en cours (changement d'arme) : le chargeur reste tel quel.
func cancel_reload() -> void:
	if is_reloading():
		_reload_timer = 0.0
		ammo_changed.emit(ammo, data.mag_size, false)


func start_reload() -> void:
	if data.unlimited() or data.is_special() or is_reloading() or ammo == data.mag_size:
		return      # les armes spéciales ne se rechargent pas
	_reload_timer = data.reload_time
	ammo_changed.emit(ammo, data.mag_size, true)
	if _networked():
		Net.reload(_shooter.peer_id, _slot())


func _try_fire(aiming: bool, spread_factor := 1.0) -> void:
	if _cooldown > 0.0:
		return
	if not data.unlimited() and ammo <= 0:
		if data.is_special():
			emptied.emit()
		else:
			start_reload()
		return

	if not data.unlimited():
		ammo -= 1
		ammo_changed.emit(ammo, data.mag_size, false)
	_cooldown = 1.0 / data.fire_rate
	firing_time = FIRING_HOLD
	var spread := (data.aim_spread_deg if aiming else data.spread_deg) * spread_factor

	if data.kind == WeaponData.Kind.PROJECTILE:
		_launch(spread)       # annoncé au serveur par Net.fire_projectile
	else:
		if _networked():
			Net.fire(_shooter.peer_id, _slot())   # avant les impacts
		var result := {}
		match data.kind:
			WeaponData.Kind.MELEE:
				result = _swing()
			WeaponData.Kind.FLAME:
				result = _flame_tick()
			_:
				result = _fire_hitscan(spread)
		if result.hit:
			hit_confirmed.emit(result.killed, result.headshot)

	if data.kind != WeaponData.Kind.FLAME:
		Effects.muzzle_flash(muzzle, data.tracer_color)
	fired.emit(data.recoil_deg)

	if not data.unlimited() and ammo == 0:
		if data.is_special():
			emptied.emit()      # arme spéciale vide : elle disparaît
		else:
			start_reload()      # rechargement automatique


# ---------------------------------------------------------------- Balles

func _fire_hitscan(spread: float) -> Dictionary:
	var total := {"hit": false, "killed": false, "headshot": false}
	for i in data.pellets:
		var result := _fire_pellet(spread)
		total.hit = total.hit or result.hit
		total.killed = total.killed or result.killed
		total.headshot = total.headshot or result.headshot
	return total


## Un projectile. Le tir se fait en deux temps :
## 1. un rayon depuis la caméra (avec dispersion) trouve le point visé ;
## 2. un rayon depuis le canon vers ce point applique les dégâts
##    (on ne peut donc pas tirer "à travers" un mur collé au personnage).
func _fire_pellet(spread_deg: float) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var aim_point := _aim_point(spread_deg)
	var from := muzzle.global_position
	var dir := (aim_point - from).normalized()
	var to := from + dir * data.max_range

	var result := {"hit": false, "killed": false, "headshot": false}
	var exclude: Array[RID] = []
	var end_point := to
	var pierce_left := MAX_PIERCE if (piercing and data.is_hitscan()) or data.pierce_always else 1

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
			# Point touché par rapport aux pieds de la cible : donne la zone (tête / corps).
			var offset: Vector3 = hit.position - (target as Node3D).global_position
			var headshot := MatchRules.is_headshot(target, offset)
			Effects.impact(_world(), hit.position, Color(1, 0.85, 0.2) if headshot else Color(1, 0.25, 0.2), 0.12 if headshot else 0.09)
			var killed := _deal(target, offset, MatchRules.hit_damage(data, headshot), headshot)
			if _hears_impacts():
				Sfx.play_at("impact_body", hit.position, -8.0, 1.0, 40.0)
			result.hit = true
			result.killed = result.killed or killed
			result.headshot = result.headshot or headshot
			exclude.append(hit.rid)
			pierce_left -= 1
		else:
			Effects.impact(_world(), hit.position, data.tracer_color)
			if _hears_impacts():
				Sfx.play_at("impact_world", hit.position, -10.0, 1.0, 40.0)
			break  # un mur arrête toujours la balle

	if data.model == WeaponData.Model.LASER:
		Effects.laser_beam(_world(), from, end_point, data.tracer_color)
	else:
		var color := data.tracer_color.lightened(0.4) if piercing else data.tracer_color
		Effects.tracer(_world(), from, end_point, color)
	return result


# ---------------------------------------------------------------- Corps à corps et flammes

## Coup de katana : toutes les cibles dans l'arc, à portée et sans mur entre nous.
func _swing() -> Dictionary:
	var center := _chest()
	var forward := _aim_forward(true)
	Effects.slash(_world(), center, forward, data.max_range, data.tracer_color)
	var result := {"hit": false, "killed": false, "headshot": false}
	for target in _targets_in_cone(center, forward, data.max_range, data.arc_deg):
		var killed := _deal(target, _body_offset(target), data.damage, false)
		_push(target, (target.global_position - _shooter.global_position).normalized(), data.knockback)
		if not result.hit:
			Sfx.play_at("katana_hit", (target as Node3D).global_position + Vector3.UP, -2.0, 1.0, 40.0)
		result.hit = true
		result.killed = result.killed or killed
	return result


## Tick de flammes : dégâts à toutes les cibles du cône, plus une brûlure.
func _flame_tick() -> Dictionary:
	var from := muzzle.global_position
	var forward := _aim_forward(false)
	Effects.flame_puff(_world(), from, forward, data.max_range)
	var result := {"hit": false, "killed": false, "headshot": false}
	for target in _targets_in_cone(from, forward, data.max_range, data.arc_deg):
		var killed := _deal(target, _body_offset(target), data.damage, false)
		if not _networked() and target.has_method("apply_effect"):
			target.apply_effect("burn", data.burn_dps, data.burn_time, Vector3.ZERO, _shooter)
		result.hit = true
		result.killed = result.killed or killed
	return result


## Cibles (avec take_damage) dans un cône : distance, angle et ligne de vue.
func _targets_in_cone(origin: Vector3, forward: Vector3, reach: float, arc_deg: float) -> Array:
	var shape := SphereShape3D.new()
	shape.radius = reach
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), origin)
	query.exclude = [_shooter.get_rid()]
	var found := []
	var space := get_world_3d().direct_space_state
	for hit in space.intersect_shape(query, 32):
		var target: Object = hit.collider
		if not target.has_method("take_damage") or target in found:
			continue
		if target.has_method("is_protected") and target.is_protected():
			continue
		var point: Vector3 = (target as Node3D).global_position + _body_offset(target)
		var to_target := point - origin
		var flat := Vector3(to_target.x, 0, to_target.z)
		var flat_forward := Vector3(forward.x, 0, forward.z)
		if flat.length() > 0.3 and flat_forward.length() > 0.01 \
				and rad_to_deg(flat.angle_to(flat_forward)) > arc_deg / 2.0:
			continue
		var los := _raycast(space, origin, point, [])
		if not los.is_empty() and los.collider != target:
			continue
		found.append(target)
	return found


# ---------------------------------------------------------------- Projectiles

## Roquette ou lance-caca : part du canon vers le point visé.
func _launch(spread: float) -> void:
	var from := muzzle.global_position
	var dir := (_aim_point(spread) - from).normalized()
	if data.projectile_gravity > 0.0:
		dir = (dir + Vector3.UP * 0.12).normalized()   # tir en cloche : on vise un peu plus haut
	Projectile.launch(self, data, _shooter, _slot(), from, dir * data.projectile_speed)


# ---------------------------------------------------------------- Effets chez les autres

## Personnage distant (piloté par le réseau) en train de tirer : on rejoue les flammes
## et les coups de katana pour que tout le monde les voie (sans dégâts).
func play_remote_fire(delta: float) -> void:
	_remote_fx -= delta
	if _remote_fx > 0.0 or data == null:
		return
	_remote_fx = 1.0 / data.fire_rate
	var forward := -_shooter.global_basis.z
	match data.kind:
		WeaponData.Kind.FLAME:
			Effects.flame_puff(_world(), muzzle.global_position, forward, data.max_range)
		WeaponData.Kind.MELEE:
			Effects.slash(_world(), _chest(), forward, data.max_range, data.tracer_color)


# ---------------------------------------------------------------- Outils

## Applique un impact : en ligne, le serveur décide (on lui envoie cible, point,
## arme) ; hors ligne, dégâts directs. Renvoie true si la cible est éliminée.
func _deal(target: Object, offset: Vector3, damage: int, headshot: bool) -> bool:
	if Net.online and target.get("peer_id") != null and target.peer_id != 0:
		Net.hit(target.peer_id, offset, data.display_name, _shooter.peer_id if "peer_id" in _shooter else 0)
		return false      # l'élimination reviendra par le réseau (signal player_died)
	if _shooter.has_method("damage_multiplier"):
		damage = int(round(damage * _shooter.damage_multiplier()))     # Surcharge néon
	return target.take_damage(damage, _shooter, headshot)


## Recul donné par un coup (hors ligne ; en ligne c'est le serveur qui l'envoie).
func _push(target: Object, direction: Vector3, strength: float) -> void:
	if strength > 0.0 and not _networked() and target.has_method("apply_effect"):
		target.apply_effect("knockback", strength, 0.0, direction, _shooter)


## Point visé à l'écran (avec dispersion), trouvé par un rayon depuis la caméra.
## Le rayon va toujours loin (AIM_RAY) : la caméra est derrière le personnage, un
## rayon limité à la portée d'une arme courte (katana) s'arrêterait derrière lui.
## La portée de l'arme s'applique ensuite depuis le canon.
func _aim_point(spread_deg: float) -> Vector3:
	var space := get_world_3d().direct_space_state
	var cam_from := _camera.global_position
	var cam_dir := _spread_direction(-_camera.global_basis.z, spread_deg)
	var cam_to := cam_from + cam_dir * maxf(data.max_range, AIM_RAY)
	var aim_hit := _raycast(space, cam_from, cam_to, [])
	return aim_hit.position if aim_hit else cam_to


## Direction de visée : vers le point visé (`flat` = à l'horizontale, pour le katana).
func _aim_forward(flat: bool) -> Vector3:
	var dir := (_aim_point(0.0) - muzzle.global_position).normalized()
	if flat:
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.01 else -_shooter.global_basis.z
	return dir


func _chest() -> Vector3:
	return _shooter.chest_position() if _shooter.has_method("chest_position") else _shooter.global_position + Vector3.UP


## Point « milieu du corps » d'une cible, relatif à ses pieds.
func _body_offset(target: Object) -> Vector3:
	var height := MatchRules.body_height(target) if "collision" in target else 1.6
	return Vector3(0, height * 0.6, 0)


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


## Impacts de balles audibles seulement pour le joueur local (sinon, avec 16 joueurs
## et leurs rafales, ils satureraient le mixage).
func _hears_impacts() -> bool:
	return _shooter.get("is_local") == true and _shooter.get("is_remote") == false


## true si ce tir doit être annoncé au serveur (partie en ligne, personnage réseau).
func _networked() -> bool:
	return Net.online and "peer_id" in _shooter and _shooter.peer_id != 0


## Emplacement de cette arme dans la classe du tireur (0 = principale, 1 = secondaire).
func _slot() -> int:
	return (_shooter.weapons as Array).find(self) if "weapons" in _shooter else 0


## Nœud où placer les effets (la scène de jeu), pour qu'ils ne suivent pas le joueur.
func _world() -> Node:
	return get_tree().current_scene if get_tree().current_scene else _shooter.get_parent()
