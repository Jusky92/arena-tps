class_name BotBrain
extends RefCounted
## Intelligence d'un bot : remplit des PlayerCommands à chaque image, exactement
## comme le clavier et la souris pour le joueur local.
##
##   Perception : cherche l'ennemi visible le plus proche (champ de vision + rayon de
##                vue : les murs bloquent), réagit aussi quand on lui tire dessus.
##   Combat     : temps de réaction, visée imparfaite qui s'affine, tir adapté à l'arme,
##                pas chassés, garde sa distance idéale, utilise sa capacité.
##   Patrouille : suit un chemin calculé sur le maillage de navigation de la map,
##                va voir la dernière position connue d'un ennemi.

const SIGHT_RANGE := 95.0
const FIELD_OF_VIEW_DEG := 75.0
const EYE_HEIGHT := 1.55

## Partie : fournit `players` (tous les joueurs), `roam_points` et `nav_map`.
var game
## Niveau du bot (0 = débutant, 1 = très fort) : réflexes, précision, vitesse de visée.
var skill := 0.55

## Niveaux proposés pour les parties solo. Chaque bot tire son `skill` entre min et
## max : des bots du même niveau ne jouent pas tous exactement pareil.
const LEVELS := [
	{"name": "Facile", "min": 0.1, "max": 0.35, "help": "Réagissent lentement et visent mal."},
	{"name": "Normal", "min": 0.35, "max": 0.75, "help": "Le niveau des serveurs en ligne."},
	{"name": "Difficile", "min": 0.65, "max": 0.9, "help": "Rapides et précis."},
	{"name": "Expert", "min": 0.9, "max": 1.0, "help": "Réflexes immédiats, visée presque parfaite."},
]
const NORMAL := 1


## `skill` d'un nouveau bot de ce niveau (indice dans LEVELS).
static func random_skill(level: int) -> float:
	var l: Dictionary = LEVELS[clampi(level, 0, LEVELS.size() - 1)]
	return randf_range(l.min, l.max)

var target: Node = null
var _attacker: Node = null
var _perceive_in := 0.0
var _reaction := 0.0
var _aim_error := Vector3.ZERO
var _last_seen_pos := Vector3.ZERO
var _last_seen_time := -100.0
var _goal := Vector3.ZERO
var _goal_reach := 2.5              # distance à laquelle le but est atteint (m)
var _path := PackedVector3Array()
var _path_index := 0
var _repath_in := 0.0
var _strafe_dir := 1.0
var _strafe_in := 0.0
var _burst_in := 0.0
var _burst_on := true
var _shot_in := 0.0
var _crouch_in := 0.0
var _crouch_burst := false
var _stuck := 0.0
var _time := 0.0


func fill(p: CharacterBody3D, cmd: PlayerCommands, delta: float) -> void:
	_time += delta
	_perceive_in -= delta
	if _perceive_in <= 0.0:
		_perceive(p)
		_perceive_in = 0.12 + randf() * 0.1
	# Cible disparue (joueur remplacé après un changement de classe), morte ou protégée.
	if not is_instance_valid(target) or not target.alive or target.spawn_protection > 0.0 \
			or (target.is_invisible() and p.global_position.distance_to(target.global_position) > INVISIBLE_SIGHT):
		target = null
	if not is_instance_valid(_attacker):
		_attacker = null
	if target:
		_combat(p, cmd, delta)
	else:
		_patrol(p, cmd, delta)
	_unstick(p, cmd, delta)


## Appelé quand le bot est touché : il se retourne vers l'agresseur.
func on_damaged(_p: CharacterBody3D, from: Node) -> void:
	if from and from.get("alive"):
		_attacker = from
		_last_seen_pos = from.global_position
		_last_seen_time = _time
		_perceive_in = 0.0


func reset() -> void:
	target = null
	_attacker = null
	_path = PackedVector3Array()
	_last_seen_time = -100.0


# --------------------------------------------------------------------------- perception

func _perceive(p: CharacterBody3D) -> void:
	var best: Node = null
	var best_distance := INF
	var forward := -p.global_transform.basis.z
	for other in game.players:
		if other == p or not other.alive or other.spawn_protection > 0.0:
			continue   # inutile de viser un joueur protégé (il vient d'apparaître)
		var to: Vector3 = other.global_position - p.global_position
		var distance := to.length()
		if distance > SIGHT_RANGE or distance >= best_distance:
			continue
		if other.is_invisible() and distance > INVISIBLE_SIGHT:
			continue   # invisible (super-pouvoir) : on ne le repère que tout près
		var flat := Vector3(to.x, 0, to.z).normalized()
		var in_view := forward.dot(flat) > cos(deg_to_rad(FIELD_OF_VIEW_DEG))
		if not in_view and distance > 7.0 and other != _attacker:
			continue
		if not _can_see(p, other):
			continue
		best = other
		best_distance = distance
	if best != target and best != null:
		_reaction = lerpf(0.75, 0.22, skill) + randf() * 0.25
		_aim_error = Vector3(randf_range(-1, 1), randf_range(-0.6, 0.8), randf_range(-1, 1)) * lerpf(1.4, 0.5, skill)
	target = best
	if target:
		_last_seen_pos = target.global_position
		_last_seen_time = _time


func _can_see(p: CharacterBody3D, other: Node) -> bool:
	var from := p.global_position + Vector3(0, EYE_HEIGHT, 0)
	var query := PhysicsRayQueryParameters3D.create(from, other.chest_position())
	query.exclude = [p.get_rid()]
	var hit := p.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider == other


# --------------------------------------------------------------------------- combat

## Distance de combat préférée selon l'arme en main (m). Par défaut : 28 m.
## Distance en dessous de laquelle on repère quand même un joueur invisible (m).
const INVISIBLE_SIGHT := 4.0

const PREFERRED_DISTANCE := {
	WeaponData.Model.SHOTGUN: 7.0, WeaponData.Model.SMG: 13.0, WeaponData.Model.ROCKET: 18.0,
	WeaponData.Model.FLAMER: 5.0, WeaponData.Model.LASER: 18.0, WeaponData.Model.KATANA: 1.6,
	WeaponData.Model.POOP: 12.0,
}


func _combat(p: CharacterBody3D, cmd: PlayerCommands, delta: float) -> void:
	var distance: float = p.global_position.distance_to(target.global_position)
	cmd.switch_to = _best_weapon(p, distance)
	var data: WeaponData = p.weapon.data
	var preferred: float = PREFERRED_DISTANCE.get(data.model, 28.0)

	# Visée : l'erreur diminue avec le temps passé sur la cible.
	_aim_error = _aim_error.lerp(Vector3.ZERO, minf(delta * lerpf(0.8, 2.6, skill), 1.0))
	var aim_point: Vector3 = target.chest_position() + _aim_error + target.velocity * 0.08
	var aimed := _look_at_point(p, cmd, aim_point, lerpf(4.0, 10.0, skill), delta)

	# Tir.
	_reaction -= delta
	var in_range := distance <= data.max_range * 0.9
	cmd.aim = data.model == WeaponData.Model.SNIPER and distance > 14.0
	if aimed and _reaction <= 0.0 and in_range:
		if data.automatic:
			_burst_in -= delta
			if _burst_in <= 0.0:
				_burst_on = not _burst_on
				_burst_in = randf_range(0.5, 0.9) if _burst_on else randf_range(0.15, 0.35)
			cmd.fire = _burst_on
		else:
			_shot_in -= delta
			if _shot_in <= 0.0:
				cmd.fire_pressed = true
				cmd.fire = true
				_shot_in = 1.0 / data.fire_rate + randf_range(0.1, 0.45)

	# Déplacement : pas chassés + garder la bonne distance.
	_strafe_in -= delta
	if _strafe_in <= 0.0:
		_strafe_dir = -_strafe_dir if randf() < 0.7 else _strafe_dir
		_strafe_in = randf_range(0.5, 1.5)
	var strafe := 0.35 if cmd.aim else 0.85
	var move := Vector2(_strafe_dir * strafe, 0.0)
	if distance > preferred + 5.0:
		var world_dir := _path_direction(p, target.global_position, delta)
		var local := p.global_transform.basis.inverse() * world_dir
		move = Vector2(local.x, local.z) + Vector2(_strafe_dir * 0.3, 0)
	elif distance < preferred - 3.0:
		move.y = 0.7
	cmd.move = move.limit_length(1.0)

	# Accroupi : le tireur s'accroupit pour viser de loin, les autres de temps en temps.
	_crouch_in -= delta
	if _crouch_in <= 0.0:
		_crouch_burst = randf() < (0.6 if data.model == WeaponData.Model.SNIPER else 0.15)
		_crouch_in = randf_range(0.8, 2.0)
	cmd.crouch = _crouch_burst and distance > 10.0

	# Super-pouvoir (bonus) : l'onde de choc quand la cible est proche, les autres tout de suite.
	if p.super_power >= 0 and randf() < 0.05:
		if p.super_power != Pickups.Super.SHOCKWAVE or distance < 7.0:
			cmd.use_super = true

	# Capacité de classe.
	match p.class_data.ability:
		ClassData.Ability.SHIELD:
			cmd.ability = p.health < p.class_data.max_health * 0.55
		ClassData.Ability.DASH:
			if distance > 7.0 and distance < 20.0 and randf() < 0.02:
				cmd.ability = true
				cmd.move = Vector2(0, -1)
		ClassData.Ability.PIERCE:
			cmd.ability = distance > 18.0 and randf() < 0.05
		ClassData.Ability.CHARGE:
			# Fonce sur la cible quand elle est proche et bien en face.
			if aimed and distance > 2.5 and distance < 9.0 and randf() < 0.06:
				cmd.ability = true


## Arme à prendre : la secondaire de corps à corps ou à flammes quand la cible est
## tout près, la secondaire quand la principale est vide, sinon la principale.
func _best_weapon(p: CharacterBody3D, distance: float) -> int:
	if p.special:
		return 2        # arme spéciale ramassée : on s'en sert tant qu'on l'a
	if p.weapons.size() < 2:
		return -1
	var primary: Node3D = p.weapons[0]
	var secondary: Node3D = p.weapons[1]
	var close_range: bool = secondary.data.kind in [WeaponData.Kind.MELEE, WeaponData.Kind.FLAME]
	if close_range:
		return 1 if distance < secondary.data.max_range * 0.9 else 0
	if primary.data.max_range * 0.9 < distance and secondary.data.max_range * 0.9 >= distance:
		return 1
	if primary.is_reloading() and not secondary.is_reloading():
		return 1
	return 0


# --------------------------------------------------------------------------- patrouille

func _patrol(p: CharacterBody3D, cmd: PlayerCommands, delta: float) -> void:
	var investigating := _time - _last_seen_time < 5.0
	if investigating:
		_goal = _last_seen_pos
	elif _goal == Vector3.ZERO or _flat_distance(p.global_position, _goal) < _goal_reach:
		_goal = _pick_roam_point(p)
		_repath_in = 0.0
	if investigating and p.global_position.distance_to(_goal) < 2.5:
		_last_seen_time = -100.0

	var world_dir := _path_direction(p, _goal, delta)
	_look_at_point(p, cmd, p.global_position + world_dir * 10.0 + Vector3(0, 1.4, 0), 5.0, delta)
	var local := p.global_transform.basis.inverse() * world_dir
	cmd.move = Vector2(local.x, local.z).limit_length(1.0)
	cmd.sprint = p.global_position.distance_to(_goal) > 12.0 and local.z < -0.7

	cmd.switch_to = 0
	if not p.weapon.data.unlimited() and p.weapon.ammo < p.weapon.data.mag_size / 2 and not p.weapon.is_reloading():
		cmd.reload = true


func _pick_roam_point(p: CharacterBody3D) -> Vector3:
	# Une fois sur deux, va chercher le bonus disponible le plus proche (à moins de 40 m).
	if randf() < 0.5 and "pickups" in game and game.pickups:
		var nearest := Vector3.ZERO
		var nearest_distance := 40.0
		for pos in game.pickups.available_positions():
			var d: float = p.global_position.distance_to(pos)
			if d < nearest_distance:
				nearest_distance = d
				nearest = pos
		if nearest != Vector3.ZERO:
			_goal_reach = 0.8           # aller jusque sur le socle pour ramasser le bonus
			return nearest
	_goal_reach = 2.5
	var points: Array = game.roam_points
	var best := Vector3.ZERO
	var best_score := -INF
	for i in 4:
		var candidate: Vector3 = points[randi() % points.size()]
		var score := p.global_position.distance_to(candidate) + randf() * 20.0
		if score > best_score:
			best_score = score
			best = candidate
	return best


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Direction (horizontale) à suivre pour aller vers `goal` en contournant les obstacles.
func _path_direction(p: CharacterBody3D, goal: Vector3, delta: float) -> Vector3:
	_repath_in -= delta
	if _repath_in <= 0.0 or _path.is_empty():
		_repath_in = 0.8
		if game.nav_map.is_valid():
			_path = NavigationServer3D.map_get_path(game.nav_map, p.global_position, goal, true)
		else:
			_path = PackedVector3Array()
		_path_index = 0
	while _path_index < _path.size():
		var point: Vector3 = _path[_path_index]
		var flat := Vector2(point.x - p.global_position.x, point.z - p.global_position.z)
		if flat.length() > 0.7:
			break
		_path_index += 1
	var next: Vector3 = _path[_path_index] if _path_index < _path.size() else goal
	var dir := next - p.global_position
	dir.y = 0
	return dir.normalized() if dir.length() > 0.05 else Vector3.ZERO


# --------------------------------------------------------------------------- outils

## Tourne la vue vers un point (vitesse limitée). Renvoie true si la visée est bonne.
## On vise depuis la caméra : c'est d'elle que partent les tirs.
func _look_at_point(p: CharacterBody3D, cmd: PlayerCommands, point: Vector3, turn_speed: float, delta: float) -> bool:
	var origin: Vector3 = p.camera.global_position
	var to := point - origin
	var horizontal := Vector2(to.x, to.z).length()
	var wanted_yaw := atan2(-to.x, -to.z)
	var wanted_pitch := atan2(to.y, horizontal)
	var d_yaw := wrapf(wanted_yaw - p.rotation.y, -PI, PI)
	var d_pitch: float = wanted_pitch - p.camera_pivot.rotation.x
	var step := turn_speed * delta
	cmd.look = Vector2(clampf(d_yaw, -step, step), clampf(d_pitch, -step, step))
	var tolerance := atan2(0.35, maxf(to.length(), 1.0)) + 0.01
	return absf(d_yaw) < tolerance * 2.0 and absf(d_pitch) < tolerance * 2.0


func _unstick(p: CharacterBody3D, cmd: PlayerCommands, delta: float) -> void:
	var speed := Vector2(p.velocity.x, p.velocity.z).length()
	if cmd.move.length() > 0.5 and speed < 0.6 and p.is_on_floor():
		_stuck += delta
		if _stuck > 0.45:
			cmd.jump = true
		if _stuck > 1.8:
			_stuck = 0.0
			_goal = _pick_roam_point(p)
			_path = PackedVector3Array()
			_strafe_dir = -_strafe_dir
	else:
		_stuck = maxf(_stuck - delta, 0.0)
