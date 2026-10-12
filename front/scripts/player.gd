extends CharacterBody3D
## Joueur local en vue à la troisième personne (caméra par-dessus l'épaule).
## - Souris : tourner la caméra (le personnage regarde là où on vise)
## - ZQSD / flèches : se déplacer   - Maj : courir   - Espace : sauter

@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var jump_velocity: float = 5.0
@export var acceleration: float = 12.0
@export var min_pitch_deg: float = -60.0
@export var max_pitch_deg: float = 45.0

@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	# Évite que la caméra "se cogne" contre le propre corps du joueur.
	spring_arm.add_excluded_object(get_rid())


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


func _physics_process(delta: float) -> void:
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
