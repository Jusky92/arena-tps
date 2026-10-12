extends CharacterBody3D
## Joueur local en vue à la troisième personne (caméra par-dessus l'épaule).
## - Souris : tourner la caméra (le personnage regarde là où on vise)
## - ZQSD / flèches : se déplacer   - Maj : courir   - Espace : sauter
## - Clic gauche : tirer   - R : recharger

## Émis quand un tir touche quelque chose qui peut prendre des dégâts.
signal hit_confirmed(killed: bool)
## Émis quand les munitions changent (pour mettre à jour le HUD).
signal ammo_changed(ammo: int, mag_size: int, reloading: bool)

@export_group("Déplacement")
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var jump_velocity: float = 5.0
@export var acceleration: float = 12.0
@export var min_pitch_deg: float = -60.0
@export var max_pitch_deg: float = 45.0

@export_group("Arme")
@export var damage: int = 20
@export var fire_rate: float = 8.0       # tirs par seconde
@export var max_range: float = 100.0     # portée en mètres
@export var mag_size: int = 12
@export var reload_time: float = 1.5     # secondes

@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var muzzle: Marker3D = $Gun/Muzzle

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _ammo: int
var _fire_cooldown: float = 0.0
var _reload_timer: float = 0.0


func _ready() -> void:
	# Évite que la caméra "se cogne" contre le propre corps du joueur.
	spring_arm.add_excluded_object(get_rid())
	_ammo = mag_size
	ammo_changed.emit.call_deferred(_ammo, mag_size, false)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sensitivity: float = Inputs.mouse_sensitivity
		# Gauche/droite : on tourne tout le personnage.
		rotate_y(-event.relative.x * sensitivity)
		# Haut/bas : on incline seulement la caméra, avec des limites.
		camera_pivot.rotation.x = clamp(
			camera_pivot.rotation.x - event.relative.y * sensitivity,
			deg_to_rad(min_pitch_deg),
			deg_to_rad(max_pitch_deg)
		)
	elif event.is_action_pressed("reload"):
		_start_reload()


func _physics_process(delta: float) -> void:
	_update_movement(delta)
	_update_weapon(delta)


# ---------------------------------------------------------------- Déplacement

func _update_movement(delta: float) -> void:
	# Gravité et saut.
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	# Direction relative à l'orientation du personnage (avant = vers la visée).
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed

	# Accélération douce plutôt qu'un arrêt/démarrage instantané.
	var target := direction * speed
	velocity.x = lerp(velocity.x, target.x, acceleration * delta)
	velocity.z = lerp(velocity.z, target.z, acceleration * delta)

	move_and_slide()


# ---------------------------------------------------------------- Arme

func _update_weapon(delta: float) -> void:
	_fire_cooldown = max(_fire_cooldown - delta, 0.0)

	# Rechargement en cours.
	if _reload_timer > 0.0:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			_ammo = mag_size
			ammo_changed.emit(_ammo, mag_size, false)
		return

	# On ne tire que si la souris est capturée (sinon le clic sert à la recapturer).
	if Input.is_action_pressed("fire") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		try_fire()


## Tente un tir. Renvoie true si un tir est parti.
func try_fire() -> bool:
	if _fire_cooldown > 0.0 or _reload_timer > 0.0:
		return false
	if _ammo <= 0:
		_start_reload()
		return false

	_ammo -= 1
	_fire_cooldown = 1.0 / fire_rate
	ammo_changed.emit(_ammo, mag_size, false)
	_shoot()

	if _ammo == 0:
		_start_reload()  # rechargement automatique
	return true


func _start_reload() -> void:
	if _reload_timer > 0.0 or _ammo == mag_size:
		return
	_reload_timer = reload_time
	ammo_changed.emit(_ammo, mag_size, true)


## Le tir se fait en deux rayons :
## 1. depuis la caméra, à travers le réticule : on trouve le point visé ;
## 2. depuis le canon vers ce point : on vérifie que rien ne bloque
##    (sinon on pourrait tirer "à travers" un mur juste devant le personnage).
func _shoot() -> void:
	var space := get_world_3d().direct_space_state

	# Rayon 1 : caméra -> centre de l'écran.
	var cam_from := camera.global_position
	var cam_to := cam_from - camera.global_basis.z * max_range
	var aim_hit := _raycast(space, cam_from, cam_to)
	var aim_point: Vector3 = aim_hit.position if aim_hit else cam_to

	# Rayon 2 : canon -> point visé (prolongé un peu pour bien toucher la surface).
	var from := muzzle.global_position
	var dir := (aim_point - from).normalized()
	var hit := _raycast(space, from, aim_point + dir * 0.5)
	var end_point: Vector3 = hit.position if hit else aim_point

	_spawn_tracer(from, end_point)

	if hit:
		_spawn_impact(hit.position)
		var target: Object = hit.collider
		if target.has_method("take_damage"):
			var killed: bool = target.take_damage(damage, self)
			hit_confirmed.emit(killed)


func _raycast(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]  # on ne se touche pas soi-même
	return space.intersect_ray(query)


# ---------------------------------------------------------------- Effets visuels

## Trait lumineux du canon jusqu'au point d'impact, visible une fraction de seconde.
func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_add_vertex(from)
	mesh.surface_add_vertex(to)
	mesh.surface_end()

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.9, 0.4)

	var line := MeshInstance3D.new()
	line.mesh = mesh
	line.material_override = material
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add_effect(line, 0.05)


## Petite boule à l'endroit touché.
func _spawn_impact(position_world: Vector3) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.6, 0.2)
	sphere.material = material

	var impact := MeshInstance3D.new()
	impact.mesh = sphere
	impact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	impact.position = position_world
	_add_effect(impact, 0.3)


## Ajoute un effet à la scène (pas au joueur, pour qu'il ne bouge pas avec lui)
## et le supprime après `lifetime` secondes.
func _add_effect(node: Node3D, lifetime: float) -> void:
	var root := get_parent()
	root.add_child(node)
	get_tree().create_timer(lifetime).timeout.connect(node.queue_free)
