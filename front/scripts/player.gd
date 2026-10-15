extends CharacterBody3D
## Joueur (local ou bot) en vue à la troisième personne.
## Ses statistiques, sa capacité et son apparence 3D viennent de son spécialiste
## (class_data) ; ses deux armes et ses grenades viennent de sa classe (loadout).
##
## Entrées et simulation sont séparées :
##   - à chaque image, on récupère des PlayerCommands (clavier/souris pour le joueur
##     local, IA pour un bot via `brain`) ;
##   - puis on simule déplacement, tir, capacité... à partir de ces commandes.
## En multijoueur, le serveur de jeu fera tourner la même simulation à partir des
## commandes envoyées par chaque client.
##
## Protection d'apparition : pendant SPAWN_PROTECTION_TIME secondes après être apparu,
## le joueur ne prend aucun dégât (bulle lumineuse visible par tous). Elle s'arrête
## dès qu'il tire, pour qu'on ne puisse pas en profiter pour attaquer.
##
## Joueur local :
##   Souris : viser          Clic gauche : tirer     Clic droit : viser (zoom)
##   ZQSD : se déplacer      Maj : courir            Espace : sauter
##   Ctrl ou C : s'accroupir R : recharger           E : capacité
##   1 / 2 ou molette : arme principale / secondaire G : grenade
##   F9 : s'infliger 25 dégâts (test, seulement depuis l'éditeur ou un export debug)

signal health_changed(health: int, max_health: int)
## `source` = position du tireur, ou Vector3.INF si on ne la connaît pas (indicateur de provenance).
signal damaged(amount: int, source: Vector3)
signal died(killer: Node)
signal ammo_changed(ammo: int, mag_size: int, reloading: bool)
signal hit_confirmed(killed: bool, headshot: bool)
## Arme en main changée (0 = principale, 1 = secondaire).
signal weapon_switched(slot: int)
signal grenades_changed(count: int)
## Touché par le lance-caca : tache cartoon à l'écran pendant `duration` secondes.
signal splatted(duration: float)

const BASE_FOV := 70.0
const SPRINT_FOV := 78.0
const CAMERA_DISTANCE := 3.5
const AIM_CAMERA_DISTANCE := 2.2
const AIM_SPEED_FACTOR := 0.55     # on se déplace plus lentement en visant
const ACCELERATION := 12.0
const AIR_CONTROL := 0.35          # contrôle réduit en l'air
const MIN_PITCH := deg_to_rad(-60.0)
const MAX_PITCH := deg_to_rad(50.0)

# Accroupi : hitbox plus basse, plus lent, plus précis.
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.25
const CROUCH_SPEED_FACTOR := 0.5
const CROUCH_SPREAD_FACTOR := 0.6
const STAND_CAMERA_HEIGHT := 1.6
const CROUCH_CAMERA_HEIGHT := 1.12

## Charge de l'Oni : dégâts et poussée pour chaque ennemi percuté pendant la ruée.
## Le nom sert d'« arme » pour le serveur et le fil des éliminations.
const CHARGE_NAME := "Charge"
const CHARGE_DAMAGE := 30
const CHARGE_KNOCKBACK := 10.0
const CHARGE_REACH := 1.3

## Pas : un son tous les STRIDE mètres (plus longs en courant). Ceux des autres
## personnages sont placés dans le monde et portent à STEP_RANGE mètres.
const STRIDE_WALK := 1.9
const STRIDE_SPRINT := 2.4
const STEP_RANGE := 35.0
const LAND_SPEED := 6.0               # vitesse de chute au-delà de laquelle on entend l'atterrissage

## Temps pour changer d'arme (on ne peut pas tirer pendant ce délai).
const SWITCH_TIME := 0.4

## Durée de la protection d'apparition (secondes).
const SPAWN_PROTECTION_TIME := 3.0
const SpawnShieldShader := preload("res://shaders/spawn_shield.gdshader")

## Spécialiste du joueur. Si rien n'est donné, on prend celui choisi dans le menu.
@export var class_data: ClassData
## Classe (équipement) : {primary, secondary} = identifiants d'armes (WeaponCatalog).
## Vide : la classe choisie dans le menu pour le joueur local, l'arme par défaut du
## spécialiste sinon (mannequins, anciens appels).
@export var loadout: Dictionary = {}
## Nom affiché (tableau des scores, fil des éliminations).
@export var player_name := "Joueur"
## true = contrôlé au clavier/souris et suivi par la caméra.
@export var is_local := true
## true = personnage d'un autre joueur, piloté par les états reçus du réseau.
## Il n'est pas simulé ici : on lisse sa position et on rejoue son animation.
@export var is_remote := false
## Identifiant réseau : peer du joueur, négatif pour un bot de l'hôte, 0 hors ligne.
@export var peer_id := 0

@onready var shield_mesh: MeshInstance3D = $Shield
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
## Arme en main (une des deux de `weapons`).
@onready var weapon: Node3D = $Gun
## Armes de la classe : [principale, secondaire].
var weapons: Array[Node3D] = []
## Emplacement de l'arme en main (0 = principale, 1 = secondaire).
var weapon_slot := 0
## Grenades restantes pour cette vie.
var grenades := WeaponCatalog.GRENADES_PER_LIFE

## Corps 3D animé : HumanRig (humain cyberpunk) ou CharacterRig (robot procédural).
## Les deux exposent les mêmes fonctions (set_state, kick, flash, play_death, reset).
var rig
## IA du bot (null pour le joueur local). Doit avoir fill(player, commands, delta).
var brain

var health: int
var alive: bool = true
var kills: int = 0
var deaths: int = 0
var streak: int = 0
var best_streak: int = 0
var crouching: bool = false
## Secondes de protection d'apparition restantes (0 = vulnérable).
var spawn_protection: float = 0.0
## true si le dernier coup reçu était un tir à la tête (fil des éliminations hors ligne).
var last_headshot := false
## false = le joueur local ne contrôle plus son personnage (menu pause ouvert).
## La simulation continue : il tombe, peut être touché, etc.
var input_enabled: bool = true

var _cmd := PlayerCommands.new()
var _look_accum := Vector2.ZERO
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _aiming: bool = false
var _crouch_amount: float = 0.0      # 0 = debout, 1 = accroupi (lissé, pour la caméra)
var _capsule: CapsuleShape3D
var _ability_cooldown: float = 0.0
var _ability_time: float = 0.0       # temps restant de l'effet en cours
var _dash_direction := Vector3.ZERO
var _charge_hits: Array = []           # ennemis déjà percutés pendant la charge en cours
var _stride := 0.0                      # distance parcourue depuis le dernier pas
var _was_on_floor := true
var _fall_speed := 0.0                  # vitesse de chute max depuis qu'on a quitté le sol
var _shake: float = 0.0
var _spawn_shield: MeshInstance3D
var _spawn_shield_mat: ShaderMaterial
# Dernier état reçu du réseau (personnages distants).
var _net_position := Vector3.ZERO
var _net_yaw := 0.0
var _net_velocity := Vector3.ZERO
var _net_pitch := 0.0
var _net_floor := true
var _net_crouch := 0.0
var _net_sprint := false
var _net_aim := false
var _net_slot := 0
var _switch_time := 0.0              # > 0 : changement d'arme en cours
var _wheel_switch := -1              # changement demandé à la molette (lu à la prochaine image)
var _net_trigger := false            # personnage distant en train de tirer (flammes, katana)
# Effets subis : ralentissement (lance-caca) et, hors ligne, brûlure (lance-flammes).
var _slow_factor := 0.0
var _slow_time := 0.0
var _burn_dps := 0.0
var _burn_time := 0.0
var _burn_pending := 0.0
var _burn_source: Node = null


func _ready() -> void:
	if class_data == null:
		class_data = GameState.selected_class
	spring_arm.add_excluded_object(get_rid())
	# Seul MON personnage filme l'écran. La caméra de la scène est inactive par
	# défaut : sinon chaque bot ou joueur distant qui apparaît la volerait.
	if is_local and not is_remote:
		camera.make_current()
	else:
		camera.current = false
	# Rampes : on reste collé à la pente en descendant au lieu de "sauter" de petits bonds.
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(46.0)
	# Copie de la forme de collision : chaque joueur peut s'accroupir indépendamment.
	_capsule = collision.shape.duplicate()
	collision.shape = _capsule
	shield_mesh.visible = false
	_build_spawn_shield()

	# Classe : arme principale et secondaire (la seconde est une copie du nœud $Gun).
	var datas := _loadout_weapons()
	var second: Node3D = weapon.duplicate()
	second.name = "Gun2"
	add_child(second)
	weapons = [weapon, second]

	# Corps 3D : personnage du spécialiste + modèles des deux armes dans les mains.
	rig = HumanRig.new() if HumanDesigns.has_design(class_data.character_design) else CharacterRig.new()
	rig.name = "Rig"
	add_child(rig)
	rig.build(class_data.character_design, datas[0].model, weapons[0])
	rig.add_weapon(datas[1].model, weapons[1])

	for i in weapons.size():
		var w := weapons[i]
		w.ammo_changed.connect(_on_weapon_ammo_changed.bind(w))
		w.hit_confirmed.connect(func(k, h): hit_confirmed.emit(k, h))
		w.fired.connect(_on_weapon_fired)
		w.setup(datas[i], self, camera)
	_select_weapon(0)

	health = class_data.max_health
	health_changed.emit.call_deferred(health, class_data.max_health)


## Souris : on cumule le mouvement, il sera appliqué dans la simulation.
func _unhandled_input(event: InputEvent) -> void:
	if not is_local or is_remote or not alive or not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var zoom_factor := camera.fov / BASE_FOV   # moins sensible en visant
		var sensitivity: float = Settings.mouse_sensitivity() * zoom_factor
		var invert := -1.0 if Settings.invert_y else 1.0
		_look_accum += Vector2(-event.relative.x, -event.relative.y * invert) * sensitivity
	elif event.is_action_pressed("weapon_next") or event.is_action_pressed("weapon_prev"):
		_wheel_switch = 1 - weapon_slot     # deux armes : la molette alterne
	elif OS.is_debug_build() and event.is_action_pressed("debug_hurt"):
		take_damage(25, null)


func _physics_process(delta: float) -> void:
	_update_ability(delta)
	_update_spawn_protection(delta)
	_update_effects(delta)
	_update_footsteps(delta)
	if is_remote:
		_follow_net_state(delta)
		return
	if not alive:
		return

	# 1. Entrées -> commandes.
	_cmd.clear()
	if is_local:
		_read_local_commands()
	elif brain:
		brain.fill(self, _cmd, delta)

	# 2. Simulation à partir des commandes.
	rotate_y(_cmd.look.x)
	camera_pivot.rotation.x = clamp(camera_pivot.rotation.x + _cmd.look.y, MIN_PITCH, MAX_PITCH)
	_aiming = _cmd.aim
	if _cmd.switch_to >= 0:
		switch_weapon(_cmd.switch_to)
	_switch_time = maxf(_switch_time - delta, 0.0)
	if _cmd.reload:
		weapon.start_reload()
	if _cmd.ability:
		use_ability()
	if _cmd.grenade:
		throw_grenade()

	_update_crouch(delta)
	_update_movement(delta)
	var can_fire := _switch_time <= 0.0
	weapon.update(delta, _cmd.fire and can_fire, _cmd.fire_pressed and can_fire, _aiming, CROUCH_SPREAD_FACTOR if crouching else 1.0)
	_update_camera(delta)

	# 3. Le corps 3D est animé à partir de l'état (vitesse dans le repère du joueur).
	rig.set_state(basis.inverse() * velocity, is_on_floor(), 1.0 if crouching else 0.0,
		camera_pivot.rotation.x, is_sprinting(), _aiming)


func _read_local_commands() -> void:
	if not input_enabled:
		_look_accum = Vector2.ZERO
		return   # commandes vides : le personnage s'arrête et ne tire plus
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	_cmd.move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	_cmd.look = _look_accum
	_look_accum = Vector2.ZERO
	_cmd.jump = Input.is_action_just_pressed("jump")
	_cmd.crouch = Input.is_action_pressed("crouch")
	_cmd.sprint = Input.is_action_pressed("sprint")
	_cmd.fire = captured and Input.is_action_pressed("fire")
	_cmd.fire_pressed = captured and Input.is_action_just_pressed("fire")
	_cmd.aim = captured and Input.is_action_pressed("aim")
	_cmd.reload = Input.is_action_just_pressed("reload")
	_cmd.ability = Input.is_action_just_pressed("ability")
	_cmd.grenade = captured and Input.is_action_just_pressed("grenade")
	if Input.is_action_just_pressed("weapon_1"):
		_cmd.switch_to = 0
	elif Input.is_action_just_pressed("weapon_2"):
		_cmd.switch_to = 1
	elif _wheel_switch >= 0:
		_cmd.switch_to = _wheel_switch
	_wheel_switch = -1


# ---------------------------------------------------------------- Réseau

## État de ce personnage, à envoyer aux autres machines (20 fois par seconde).
## Volontairement court : des clés d'une lettre, et rien qui puisse se recalculer.
func net_state() -> Dictionary:
	return {
		"p": global_position,
		"y": rotation.y,
		"x": camera_pivot.rotation.x,
		"v": basis.inverse() * velocity,
		"f": is_on_floor(),
		"c": 1.0 if crouching else 0.0,
		"s": is_sprinting(),
		"a": _aiming,
		"w": weapon_slot,
		"t": weapon.firing_time > 0.0,
	}


## État reçu pour un personnage distant.
func apply_net_state(state: Dictionary) -> void:
	_net_position = state.get("p", _net_position)
	_net_yaw = state.get("y", _net_yaw)
	_net_velocity = state.get("v", Vector3.ZERO)
	_net_pitch = state.get("x", 0.0)
	_net_floor = state.get("f", true)
	_net_crouch = state.get("c", 0.0)
	_net_sprint = state.get("s", false)
	_net_aim = state.get("a", false)
	_net_slot = state.get("w", 0)
	_net_trigger = state.get("t", false)


## Lissage : on rattrape la dernière position reçue au lieu de téléporter.
## Au-delà de 6 m d'écart (apparition, dash, paquet perdu), on se replace d'un coup.
func _follow_net_state(delta: float) -> void:
	if not alive:
		return
	if global_position.distance_to(_net_position) > 6.0:
		global_position = _net_position
	else:
		global_position = global_position.lerp(_net_position, clampf(delta * 14.0, 0.0, 1.0))
	rotation.y = lerp_angle(rotation.y, _net_yaw, clampf(delta * 14.0, 0.0, 1.0))
	camera_pivot.rotation.x = lerpf(camera_pivot.rotation.x, _net_pitch, clampf(delta * 10.0, 0.0, 1.0))
	velocity = basis * _net_velocity
	_aiming = _net_aim
	if _net_slot != weapon_slot and _net_slot >= 0 and _net_slot < weapons.size():
		_select_weapon(_net_slot)
	if _net_trigger:
		weapon.play_remote_fire(delta)
	if (_net_crouch > 0.5) != crouching:
		_set_crouching(_net_crouch > 0.5)
	rig.set_state(_net_velocity, _net_floor, _net_crouch, _net_pitch, _net_sprint, _net_aim)


## Place le personnage sans lissage (apparition, changement de classe).
func teleport(to: Vector3, yaw: float) -> void:
	global_position = to
	rotation.y = yaw
	_net_position = to
	_net_yaw = yaw


# ---------------------------------------------------------------- Accroupi

func _update_crouch(delta: float) -> void:
	var wants := _cmd.crouch and not is_dashing()
	if wants and not crouching:
		_set_crouching(true)
	elif not wants and crouching and _can_stand():
		_set_crouching(false)
	_crouch_amount = move_toward(_crouch_amount, 1.0 if crouching else 0.0, delta * 7.0)


func _set_crouching(value: bool) -> void:
	crouching = value
	var height := CROUCH_HEIGHT if value else STAND_HEIGHT
	_capsule.height = height
	collision.position.y = height / 2.0


## Vérifie qu'il y a la place de se relever (pas de plafond juste au-dessus).
func _can_stand() -> bool:
	var standing := CapsuleShape3D.new()
	standing.radius = _capsule.radius
	standing.height = STAND_HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = standing
	query.transform = Transform3D(Basis(), global_position + Vector3(0, STAND_HEIGHT / 2.0 + 0.02, 0))
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


# ---------------------------------------------------------------- Déplacement

func _update_movement(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif _cmd.jump:
		# Sauter depuis la position accroupie relève le joueur (s'il y a la place).
		if crouching and _can_stand():
			_set_crouching(false)
		if not crouching:
			velocity.y = class_data.jump_velocity

	var direction := (transform.basis * Vector3(_cmd.move.x, 0.0, _cmd.move.y)).normalized()

	# Dash ou charge en cours : vitesse imposée, on ignore les commandes.
	if is_dashing() or is_charging():
		velocity.x = _dash_direction.x * class_data.ability_strength
		velocity.z = _dash_direction.z * class_data.ability_strength
		move_and_slide()
		if is_charging():
			_charge_contacts()
		return

	var sprinting := _cmd.sprint and not _aiming and not crouching and _cmd.move.y < 0.0
	var speed := class_data.sprint_speed if sprinting else class_data.walk_speed
	if _slow_time > 0.0:
		speed *= 1.0 - _slow_factor
	if _aiming:
		speed *= AIM_SPEED_FACTOR
	if crouching:
		speed *= CROUCH_SPEED_FACTOR

	var target := direction * speed * minf(_cmd.move.length(), 1.0)
	var accel := ACCELERATION if is_on_floor() else ACCELERATION * AIR_CONTROL
	velocity.x = lerp(velocity.x, target.x, accel * delta)
	velocity.z = lerp(velocity.z, target.z, accel * delta)
	move_and_slide()


func is_sprinting() -> bool:
	return _cmd.sprint and not _aiming and not crouching \
		and Vector2(velocity.x, velocity.z).length() > class_data.walk_speed + 0.5


# ---------------------------------------------------------------- Caméra

func _update_camera(delta: float) -> void:
	var target_fov := BASE_FOV
	if _aiming:
		target_fov = weapon.data.aim_fov
	elif is_sprinting() or is_dashing() or is_charging():
		target_fov = SPRINT_FOV
	camera.fov = lerp(camera.fov, target_fov, 12.0 * delta)

	var target_distance := AIM_CAMERA_DISTANCE if _aiming else CAMERA_DISTANCE
	spring_arm.spring_length = lerp(spring_arm.spring_length, target_distance, 10.0 * delta)
	camera_pivot.position.y = lerpf(STAND_CAMERA_HEIGHT, CROUCH_CAMERA_HEIGHT, smoothstep(0.0, 1.0, _crouch_amount))
	shield_mesh.position.y = lerpf(0.95, 0.68, _crouch_amount)
	_spawn_shield.position.y = lerpf(0.95, 0.7, _crouch_amount)

	# Tremblement de caméra (tir, dégâts) qui s'atténue rapidement.
	_shake = move_toward(_shake, 0.0, delta * 4.0)
	camera.h_offset = randf_range(-1.0, 1.0) * _shake * 0.05
	camera.v_offset = randf_range(-1.0, 1.0) * _shake * 0.05


func _on_weapon_fired(recoil_deg: float) -> void:
	# Tirer met fin à la protection d'apparition.
	if spawn_protection > 0.0:
		end_spawn_protection()
	# Lance-flammes : un son tous les 3 ticks environ (ses bouffées durent plus qu'un tick).
	if weapon.data.kind != WeaponData.Kind.FLAME or randf() < 0.34:
		_play_sound(Sfx.shot_sound(weapon.data.model), -3.0, randf_range(0.95, 1.05))
	# Le recul fait remonter la visée : au joueur de compenser (moins en visant ou accroupi).
	var steady := (0.5 if _aiming else 1.0) * (0.7 if crouching else 1.0)
	var recoil := deg_to_rad(recoil_deg) * steady
	camera_pivot.rotation.x = clamp(camera_pivot.rotation.x + recoil, MIN_PITCH, MAX_PITCH)
	rotate_y(deg_to_rad(randf_range(-0.3, 0.3) * recoil_deg))
	_shake = min(_shake + recoil_deg * 0.15, 1.0)
	rig.kick(recoil_deg)


func _on_weapon_ammo_changed(ammo: int, mag_size: int, reloading: bool, from: Node3D) -> void:
	if from != weapon:
		return      # l'arme rangée ne parle pas au HUD
	if reloading and alive:
		_play_sound("reload", -6.0)
	ammo_changed.emit(ammo, mag_size, reloading)


func is_aiming() -> bool:
	return _aiming


## Point visé par les autres (milieu du torse), utile pour l'IA.
func chest_position() -> Vector3:
	return global_position + Vector3(0, (CROUCH_HEIGHT if crouching else STAND_HEIGHT) * 0.62, 0)


## Son émis par ce joueur : non spatialisé pour le joueur local, placé dans le monde pour les autres.
func _play_sound(sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not is_inside_tree():
		return
	if is_local:
		Sfx.play(sound, volume_db, pitch)
	else:
		Sfx.play_at(sound, chest_position(), volume_db + 2.0, pitch)


# ---------------------------------------------------------------- Capacité

func use_ability() -> bool:
	if not alive or _ability_cooldown > 0.0:
		return false
	_ability_cooldown = class_data.ability_cooldown
	_ability_time = class_data.ability_duration
	_play_sound(Sfx.ability_sound(class_data.ability), -4.0)

	match class_data.ability:
		ClassData.Ability.SHIELD:
			shield_mesh.visible = true
		ClassData.Ability.DASH:
			var input := _cmd.move
			if input == Vector2.ZERO:
				input = Vector2(0, -1)  # sans direction : dash vers l'avant
			_dash_direction = (transform.basis * Vector3(input.x, 0, input.y)).normalized()
			velocity.y = max(velocity.y, 1.5)  # petit décollage pour passer les bosses
			if crouching and _can_stand():
				_set_crouching(false)
		ClassData.Ability.CHARGE:
			# Ruée droit devant (là où regarde le personnage).
			_dash_direction = -global_basis.z
			_dash_direction.y = 0.0
			_dash_direction = _dash_direction.normalized()
			_charge_hits.clear()
			velocity.y = max(velocity.y, 1.0)
			if crouching and _can_stand():
				_set_crouching(false)
		ClassData.Ability.PIERCE:
			for w in weapons:
				w.piercing = true      # ne joue que sur les armes à balles (voir weapon.gd)
	return true


func _update_ability(delta: float) -> void:
	_ability_cooldown = max(_ability_cooldown - delta, 0.0)
	if _ability_time > 0.0:
		_ability_time -= delta
		if _ability_time <= 0.0:
			_end_ability()


func _end_ability() -> void:
	_ability_time = 0.0
	shield_mesh.visible = false
	for w in weapons:
		w.piercing = false
	_dash_direction = Vector3.ZERO


func is_dashing() -> bool:
	return class_data.ability == ClassData.Ability.DASH and _ability_time > 0.0


func is_charging() -> bool:
	return class_data.ability == ClassData.Ability.CHARGE and _ability_time > 0.0


## Pendant la charge : chaque ennemi percuté (une fois) prend des dégâts et est
## projeté. En ligne, on le signale au serveur, qui vérifie et applique.
func _charge_contacts() -> void:
	var shape := SphereShape3D.new()
	shape.radius = CHARGE_REACH
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), chest_position() + _dash_direction * 0.5)
	query.exclude = [get_rid()]
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 16):
		var target: Object = hit.collider
		if not target.has_method("take_damage") or target in _charge_hits:
			continue
		if target.has_method("is_protected") and target.is_protected():
			continue
		_charge_hits.append(target)
		var push := (_dash_direction + Vector3.UP * 0.4).normalized()
		if Net.online and peer_id != 0 and target.get("peer_id") != null and target.peer_id != 0:
			Net.hit(target.peer_id, Vector3(0, 1.0, 0), CHARGE_NAME, peer_id)
		else:
			var killed: bool = target.take_damage(CHARGE_DAMAGE, self)
			if target.has_method("apply_effect"):
				target.apply_effect("knockback", CHARGE_KNOCKBACK, 0.0, push, self)
			hit_confirmed.emit(killed, false)
		_shake = minf(_shake + 0.4, 1.0)
		rig.kick(4.0)


func is_shielded() -> bool:
	return class_data.ability == ClassData.Ability.SHIELD and _ability_time > 0.0


## 1.0 = capacité prête, 0.0 = vient d'être utilisée.
func ability_ready_ratio() -> float:
	return 1.0 - _ability_cooldown / class_data.ability_cooldown


func ability_active() -> bool:
	return _ability_time > 0.0


# ---------------------------------------------------------------- Protection d'apparition

## Bulle lumineuse autour du personnage, visible pendant la protection.
func _build_spawn_shield() -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.62
	mesh.height = 2.05
	mesh.radial_segments = 32
	mesh.rings = 12
	_spawn_shield_mat = ShaderMaterial.new()
	_spawn_shield_mat.shader = SpawnShieldShader
	_spawn_shield = MeshInstance3D.new()
	_spawn_shield.name = "SpawnShield"
	_spawn_shield.mesh = mesh
	_spawn_shield.material_override = _spawn_shield_mat
	_spawn_shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spawn_shield.position.y = 0.95
	_spawn_shield.visible = false
	add_child(_spawn_shield)


func start_spawn_protection(duration := SPAWN_PROTECTION_TIME) -> void:
	spawn_protection = duration
	_spawn_shield.visible = true
	_spawn_shield_mat.set_shader_parameter("strength", 1.0)


func end_spawn_protection() -> void:
	spawn_protection = 0.0
	_spawn_shield.visible = false


func is_protected() -> bool:
	return alive and spawn_protection > 0.0


func _update_spawn_protection(delta: float) -> void:
	if spawn_protection <= 0.0:
		return
	spawn_protection = maxf(spawn_protection - delta, 0.0)
	if spawn_protection == 0.0 or not alive:
		end_spawn_protection()
	else:
		_spawn_shield_mat.set_shader_parameter("strength", spawn_protection / SPAWN_PROTECTION_TIME)


# ---------------------------------------------------------------- Vie et mort

## Inflige des dégâts. Renvoie true si ce coup a éliminé le joueur.
## Même méthode que les cibles : un tir ne fait pas la différence.
func take_damage(amount: int, from: Node, headshot := false) -> bool:
	if not alive:
		return false
	if is_protected():
		return false     # protection d'apparition : aucun dégât (le tir est dévié, voir weapon.gd)
	if is_shielded():
		amount = max(int(round(amount * class_data.ability_strength)), 1)
	health = max(health - amount, 0)
	_shake = min(_shake + 0.5, 1.0)
	rig.flash()
	last_headshot = headshot
	damaged.emit(amount, (from as Node3D).global_position if from is Node3D else Vector3.INF)
	health_changed.emit(health, class_data.max_health)
	if brain and from:
		brain.on_damaged(self, from)
	if health == 0:
		_die(from)
		return true
	return false


func _die(killer: Node) -> void:
	alive = false
	deaths += 1
	streak = 0
	_end_ability()
	end_spawn_protection()
	velocity = Vector3.ZERO
	if crouching:
		_set_crouching(false)
	rig.play_death()
	collision.set_deferred("disabled", true)
	died.emit(killer)


## Mort annoncée par le réseau : même effet visuel que `_die`, mais sans décompte
## local (en ligne, c'est l'hôte qui tient les scores).
func net_die() -> void:
	if not alive:
		return
	alive = false
	health = 0
	_end_ability()
	end_spawn_protection()
	velocity = Vector3.ZERO
	if crouching:
		_set_crouching(false)
	rig.play_death()
	collision.set_deferred("disabled", true)


## Fait réapparaître le joueur à `spawn_position`, PV et munitions au maximum,
## avec la protection d'apparition.
func respawn(spawn_position: Vector3, yaw: float) -> void:
	global_position = spawn_position
	rotation.y = yaw
	_net_position = spawn_position
	_net_yaw = yaw
	camera_pivot.rotation.x = 0.0
	velocity = Vector3.ZERO
	health = class_data.max_health
	alive = true
	_ability_cooldown = 0.0
	_crouch_amount = 0.0
	rig.reset()
	collision.set_deferred("disabled", false)
	for w in weapons:
		w.refill()
	_select_weapon(0)
	grenades = WeaponCatalog.GRENADES_PER_LIFE
	grenades_changed.emit(grenades)
	_slow_time = 0.0
	_burn_time = 0.0
	health_changed.emit(health, class_data.max_health)
	start_spawn_protection()
	_play_sound("spawn", -8.0)


## Compte une élimination (appelé par la partie).
func add_kill() -> void:
	kills += 1
	streak += 1
	best_streak = maxi(best_streak, streak)


# ---------------------------------------------------------------- Armes de la classe

## Fiches des deux armes de la classe : [principale, secondaire].
func _loadout_weapons() -> Array[WeaponData]:
	var l := loadout
	if l.is_empty() and is_local and not is_remote:
		l = GameState.current_loadout()
	var primary := WeaponCatalog.find(str(l.get("primary", "")))
	var secondary := WeaponCatalog.find(str(l.get("secondary", "")))
	if primary == null or primary.slot != WeaponData.Slot.PRIMARY:
		primary = class_data.weapon
	if secondary == null or secondary.slot != WeaponData.Slot.SECONDARY:
		secondary = WeaponCatalog.find(WeaponCatalog.DEFAULT_LOADOUTS[0].secondary)
	var out: Array[WeaponData] = [primary, secondary]
	return out


## Passe à l'arme principale (0) ou secondaire (1). Le rechargement en cours est
## annulé ; on ne peut pas tirer pendant SWITCH_TIME secondes.
func switch_weapon(slot: int) -> void:
	if slot == weapon_slot or slot < 0 or slot >= weapons.size() or not alive:
		return
	weapon.cancel_reload()
	_select_weapon(slot)
	_switch_time = SWITCH_TIME
	_play_sound("switch", -6.0)


func _select_weapon(slot: int) -> void:
	weapon_slot = slot
	weapon = weapons[slot]
	rig.show_weapon(weapon)
	weapon_switched.emit(slot)
	ammo_changed.emit(weapon.ammo, weapon.data.mag_size, weapon.is_reloading())


## Arme de la classe d'après son nom affiché (null si le joueur ne l'a pas).
func weapon_named(display_name: String) -> WeaponData:
	for w in weapons:
		if w.data.display_name == display_name:
			return w.data
	return null


# ---------------------------------------------------------------- Grenades et effets subis

## Lance une grenade devant soi (2 par vie). En ligne, le serveur la simule.
func throw_grenade() -> bool:
	if not alive or grenades <= 0 or _switch_time > 0.0:
		return false
	grenades -= 1
	grenades_changed.emit(grenades)
	if spawn_protection > 0.0:
		end_spawn_protection()
	var data := WeaponCatalog.GRENADE
	var aim := -camera.global_basis.z if camera else -global_basis.z
	var direction := (aim + Vector3.UP * 0.35).normalized()
	var origin := chest_position() + Vector3.UP * 0.3 + (-global_basis.z) * 0.4
	Projectile.launch(self, data, self, 2, origin, direction * data.projectile_speed + velocity * 0.5)
	_play_sound("grenade_throw", -2.0)
	return true


## Effet subi (décidé par le serveur en ligne, ou par l'arme hors ligne) :
##   "slow"      : vitesse x (1 - value) pendant `duration` secondes (lance-caca)
##   "splat"     : tache cartoon à l'écran pendant `duration` secondes (lance-caca)
##   "knockback" : poussée de `value` m/s dans `direction` (explosions, katana, Charge)
##   "burn"      : hors ligne seulement, `value` dégâts/s pendant `duration` secondes
func apply_effect(kind: String, value: float, duration: float, direction := Vector3.ZERO, source: Node = null) -> void:
	if not alive:
		return
	match kind:
		"slow":
			_slow_factor = clampf(value, 0.0, 0.9)
			_slow_time = maxf(_slow_time, duration)
		"splat":
			splatted.emit(duration)
		"knockback":
			velocity += direction * value
			velocity.y = maxf(velocity.y, value * 0.35)
		"burn":
			_burn_dps = value
			_burn_time = duration
			_burn_source = source


## true pendant un ralentissement (affiché par le HUD).
func is_slowed() -> bool:
	return _slow_time > 0.0


func _update_effects(delta: float) -> void:
	_slow_time = maxf(_slow_time - delta, 0.0)
	if _burn_time > 0.0 and alive:
		_burn_time -= delta
		_burn_pending += _burn_dps * delta
		if _burn_pending >= 1.0:
			var amount := int(_burn_pending)
			_burn_pending -= amount
			take_damage(amount, _burn_source if is_instance_valid(_burn_source) else null)


# ---------------------------------------------------------------- Pas

## Pas et atterrissages, pour tous les personnages (joueur local, bots, joueurs
## distants) : on entend arriver les autres. Rien sur le serveur dédié.
func _update_footsteps(delta: float) -> void:
	if Effects.headless() or not alive or not is_inside_tree():
		return
	var grounded := _net_floor if is_remote else is_on_floor()
	if not grounded:
		_fall_speed = maxf(_fall_speed, -velocity.y)
	elif not _was_on_floor:
		if _fall_speed > LAND_SPEED:
			_step_sound("land", 0.0)
		_fall_speed = 0.0
		_stride = 0.0
	_was_on_floor = grounded
	if not grounded or is_dashing() or is_charging():
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed < 1.0:
		_stride = 0.0
		return
	_stride += speed * delta
	var running := speed > class_data.walk_speed + 0.5
	if _stride >= (STRIDE_SPRINT if running else STRIDE_WALK):
		_stride = 0.0
		var volume := 0.0 if running else -5.0
		if crouching:
			volume -= 8.0           # accroupi : presque silencieux
		_step_sound("step", volume)


func _step_sound(sound: String, volume_db: float) -> void:
	if is_local and not is_remote:
		Sfx.play(sound, volume_db - 14.0)          # ses propres pas : discrets
	else:
		Sfx.play_at(sound, global_position, volume_db - 2.0, 1.0, STEP_RANGE)
