extends CharacterBody3D
## Joueur local en vue à la troisième personne (caméra par-dessus l'épaule).
## Ses statistiques, son arme, sa capacité et son apparence 3D viennent de sa classe.
##
## Souris : viser          Clic gauche : tirer     Clic droit : viser (zoom)
## ZQSD : se déplacer      Maj : courir            Espace : sauter
## Ctrl ou C : s'accroupir (maintenir)
## R : recharger           E : capacité            F9 : s'infliger 25 dégâts (test)

signal health_changed(health: int, max_health: int)
signal damaged(amount: int)
signal died(killer: Node)
signal ammo_changed(ammo: int, mag_size: int, reloading: bool)
signal hit_confirmed(killed: bool)

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

## Classe du joueur. Si rien n'est donné, on prend celle choisie dans le menu.
@export var class_data: ClassData

@onready var shield_mesh: MeshInstance3D = $Shield
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var weapon: Node3D = $Gun

## Corps 3D animé (construit au démarrage selon la classe).
var rig: CharacterRig

var health: int
var alive: bool = true
var kills: int = 0
var deaths: int = 0
var crouching: bool = false

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _aiming: bool = false
var _crouch_amount: float = 0.0      # 0 = debout, 1 = accroupi (lissé, pour la caméra)
var _capsule: CapsuleShape3D
var _ability_cooldown: float = 0.0
var _ability_time: float = 0.0       # temps restant de l'effet en cours
var _dash_direction := Vector3.ZERO
var _shake: float = 0.0


func _ready() -> void:
	if class_data == null:
		class_data = GameState.selected_class
	spring_arm.add_excluded_object(get_rid())
	# Rampes : on reste collé à la pente en descendant au lieu de "sauter" de petits bonds.
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(46.0)
	# Copie de la forme de collision : chaque joueur peut s'accroupir indépendamment.
	_capsule = collision.shape.duplicate()
	collision.shape = _capsule
	shield_mesh.visible = false

	# Corps 3D : squelette + armure de la classe + modèle d'arme dans les mains.
	rig = CharacterRig.new()
	rig.name = "Rig"
	add_child(rig)
	rig.build(class_data.character_design, class_data.weapon.model, weapon)

	weapon.ammo_changed.connect(func(a, m, r): ammo_changed.emit(a, m, r))
	weapon.hit_confirmed.connect(func(k): hit_confirmed.emit(k))
	weapon.fired.connect(_on_weapon_fired)
	weapon.setup(class_data.weapon, self, camera)

	health = class_data.max_health
	health_changed.emit.call_deferred(health, class_data.max_health)


func _unhandled_input(event: InputEvent) -> void:
	if not alive:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Sensibilité réduite en visant, proportionnelle au zoom.
		var zoom_factor := camera.fov / BASE_FOV
		var sensitivity: float = Inputs.mouse_sensitivity * zoom_factor
		rotate_y(-event.relative.x * sensitivity)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x - event.relative.y * sensitivity, MIN_PITCH, MAX_PITCH)
	elif event.is_action_pressed("reload"):
		weapon.start_reload()
	elif event.is_action_pressed("ability"):
		use_ability()
	elif event.is_action_pressed("debug_hurt"):
		take_damage(25, null)


func _physics_process(delta: float) -> void:
	_update_ability(delta)
	if not alive:
		return

	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	_aiming = captured and Input.is_action_pressed("aim")

	_update_crouch(delta)
	_update_movement(delta)
	weapon.update(delta,
		captured and Input.is_action_pressed("fire"),
		captured and Input.is_action_just_pressed("fire"),
		_aiming,
		CROUCH_SPREAD_FACTOR if crouching else 1.0)
	_update_camera(delta)

	# Le corps 3D est animé à partir de l'état du joueur (vitesse dans son repère).
	rig.set_state(basis.inverse() * velocity, is_on_floor(), 1.0 if crouching else 0.0,
		camera_pivot.rotation.x, is_sprinting(), _aiming)


# ---------------------------------------------------------------- Accroupi

func _update_crouch(delta: float) -> void:
	var wants := Input.is_action_pressed("crouch") and not is_dashing()
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
	elif Input.is_action_just_pressed("jump"):
		# Sauter depuis la position accroupie relève le joueur (s'il y a la place).
		if crouching and _can_stand():
			_set_crouching(false)
		if not crouching:
			velocity.y = class_data.jump_velocity

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()

	# Dash en cours : vitesse imposée, on ignore les touches.
	if is_dashing():
		velocity.x = _dash_direction.x * class_data.ability_strength
		velocity.z = _dash_direction.z * class_data.ability_strength
		move_and_slide()
		return

	var sprinting := Input.is_action_pressed("sprint") and not _aiming and not crouching and input.y < 0.0
	var speed := class_data.sprint_speed if sprinting else class_data.walk_speed
	if _aiming:
		speed *= AIM_SPEED_FACTOR
	if crouching:
		speed *= CROUCH_SPEED_FACTOR

	var target := direction * speed
	var accel := ACCELERATION if is_on_floor() else ACCELERATION * AIR_CONTROL
	velocity.x = lerp(velocity.x, target.x, accel * delta)
	velocity.z = lerp(velocity.z, target.z, accel * delta)
	move_and_slide()


func is_sprinting() -> bool:
	return Input.is_action_pressed("sprint") and not _aiming and not crouching \
		and Vector2(velocity.x, velocity.z).length() > class_data.walk_speed + 0.5


# ---------------------------------------------------------------- Caméra

func _update_camera(delta: float) -> void:
	var target_fov := BASE_FOV
	if _aiming:
		target_fov = class_data.weapon.aim_fov
	elif is_sprinting() or is_dashing():
		target_fov = SPRINT_FOV
	camera.fov = lerp(camera.fov, target_fov, 12.0 * delta)

	var target_distance := AIM_CAMERA_DISTANCE if _aiming else CAMERA_DISTANCE
	spring_arm.spring_length = lerp(spring_arm.spring_length, target_distance, 10.0 * delta)
	camera_pivot.position.y = lerpf(STAND_CAMERA_HEIGHT, CROUCH_CAMERA_HEIGHT, smoothstep(0.0, 1.0, _crouch_amount))
	shield_mesh.position.y = lerpf(0.95, 0.68, _crouch_amount)

	# Tremblement de caméra (tir, dégâts) qui s'atténue rapidement.
	_shake = move_toward(_shake, 0.0, delta * 4.0)
	camera.h_offset = randf_range(-1.0, 1.0) * _shake * 0.05
	camera.v_offset = randf_range(-1.0, 1.0) * _shake * 0.05


func _on_weapon_fired(recoil_deg: float) -> void:
	# Le recul fait remonter la visée : au joueur de compenser (moins en visant ou accroupi).
	var steady := (0.5 if _aiming else 1.0) * (0.7 if crouching else 1.0)
	var recoil := deg_to_rad(recoil_deg) * steady
	camera_pivot.rotation.x = clamp(camera_pivot.rotation.x + recoil, MIN_PITCH, MAX_PITCH)
	rotate_y(deg_to_rad(randf_range(-0.3, 0.3) * recoil_deg))
	_shake = min(_shake + recoil_deg * 0.15, 1.0)
	rig.kick(recoil_deg)


func is_aiming() -> bool:
	return _aiming


# ---------------------------------------------------------------- Capacité

func use_ability() -> bool:
	if not alive or _ability_cooldown > 0.0:
		return false
	_ability_cooldown = class_data.ability_cooldown
	_ability_time = class_data.ability_duration

	match class_data.ability:
		ClassData.Ability.SHIELD:
			shield_mesh.visible = true
		ClassData.Ability.DASH:
			var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
			if input == Vector2.ZERO:
				input = Vector2(0, -1)  # sans direction : dash vers l'avant
			_dash_direction = (transform.basis * Vector3(input.x, 0, input.y)).normalized()
			velocity.y = max(velocity.y, 1.5)  # petit décollage pour passer les bosses
			if crouching and _can_stand():
				_set_crouching(false)
		ClassData.Ability.PIERCE:
			weapon.piercing = true
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
	weapon.piercing = false
	_dash_direction = Vector3.ZERO


func is_dashing() -> bool:
	return class_data.ability == ClassData.Ability.DASH and _ability_time > 0.0


func is_shielded() -> bool:
	return class_data.ability == ClassData.Ability.SHIELD and _ability_time > 0.0


## 1.0 = capacité prête, 0.0 = vient d'être utilisée.
func ability_ready_ratio() -> float:
	return 1.0 - _ability_cooldown / class_data.ability_cooldown


func ability_active() -> bool:
	return _ability_time > 0.0


# ---------------------------------------------------------------- Vie et mort

## Inflige des dégâts. Renvoie true si ce coup a éliminé le joueur.
## Même méthode que les cibles : un tir ne fait pas la différence.
func take_damage(amount: int, from: Node) -> bool:
	if not alive:
		return false
	if is_shielded():
		amount = max(int(round(amount * class_data.ability_strength)), 1)
	health = max(health - amount, 0)
	_shake = min(_shake + 0.5, 1.0)
	rig.flash()
	damaged.emit(amount)
	health_changed.emit(health, class_data.max_health)
	if health == 0:
		_die(from)
		return true
	return false


func _die(killer: Node) -> void:
	alive = false
	deaths += 1
	_end_ability()
	velocity = Vector3.ZERO
	if crouching:
		_set_crouching(false)
	rig.play_death()
	collision.set_deferred("disabled", true)
	died.emit(killer)


## Fait réapparaître le joueur à `spawn_position`, PV et munitions au maximum.
func respawn(spawn_position: Vector3, yaw: float) -> void:
	global_position = spawn_position
	rotation.y = yaw
	camera_pivot.rotation.x = 0.0
	velocity = Vector3.ZERO
	health = class_data.max_health
	alive = true
	_ability_cooldown = 0.0
	_crouch_amount = 0.0
	rig.reset()
	collision.set_deferred("disabled", false)
	weapon.refill()
	health_changed.emit(health, class_data.max_health)
