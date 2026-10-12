extends Node3D
## Scène de jeu : construit l'arène 3D, fait apparaître le joueur et des cibles
## d'entraînement à des endroits aléatoires libres, gère le HUD, capture la
## souris, et revient au menu avec Échap.

const MAP_SIZE := 60.0          # l'arène fait 60 x 60 mètres, centrée sur (0, 0)
const WALL_HEIGHT := 4.0
const WALL_THICKNESS := 1.0
const FLOOR_COLOR := Color(0.32, 0.36, 0.3)
const WALL_COLOR := Color(0.45, 0.47, 0.55)
const OBSTACLE_COLOR := Color(0.7, 0.55, 0.35)
const TARGET_COUNT := 6         # nombre de cibles d'entraînement

# Obstacles : [position du centre au sol (x, z), taille (largeur x, hauteur, profondeur z)].
const OBSTACLES := [
	[Vector2(-12, -10), Vector3(6, 2, 1.5)],
	[Vector2(10, -14),  Vector3(1.5, 3, 8)],
	[Vector2(0, 0),     Vector3(6, 1, 6)],      # plateforme centrale (on peut sauter dessus)
	[Vector2(-15, 12),  Vector3(1.5, 2.5, 7)],
	[Vector2(14, 13),   Vector3(8, 1.5, 1.5)],
	[Vector2(-4, 18),   Vector3(2, 2, 2)],
	[Vector2(20, 0),    Vector3(2, 2, 2)],
	[Vector2(-22, -2),  Vector3(2, 2, 2)],
]

const PlayerScene := preload("res://scenes/player.tscn")
const TargetScene := preload("res://scenes/target_dummy.tscn")

@onready var ammo_label: Label = $HUD/AmmoLabel
@onready var crosshair: Label = $HUD/Crosshair

# Zones au sol occupées (pour éviter d'apparaître dans un mur), en 2D vue du dessus.
var _blocked: Array[Rect2] = []
var _crosshair_tween: Tween


func _ready() -> void:
	_build_floor()
	_build_walls()
	_spawn_targets()
	_spawn_player()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("back_to_menu"):
		get_tree().change_scene_to_file("res://scenes/menu.tscn")
	# Si la souris a été libérée (Alt+Tab…), un clic la recapture.
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ---------------------------------------------------------------- Arène

func _build_floor() -> void:
	# Le sol a une épaisseur de 1 m, sa surface est à y = 0.
	add_child(_make_box(Vector3(0, -0.5, 0), Vector3(MAP_SIZE, 1, MAP_SIZE), FLOOR_COLOR))


func _build_walls() -> void:
	var half := MAP_SIZE / 2.0
	var t := WALL_THICKNESS
	var h := WALL_HEIGHT
	var borders := [
		[Vector3(0, h / 2, -half), Vector3(MAP_SIZE, h, t)],  # nord
		[Vector3(0, h / 2, half),  Vector3(MAP_SIZE, h, t)],  # sud
		[Vector3(-half, h / 2, 0), Vector3(t, h, MAP_SIZE)],  # ouest
		[Vector3(half, h / 2, 0),  Vector3(t, h, MAP_SIZE)],  # est
	]
	for b in borders:
		add_child(_make_box(b[0], b[1], WALL_COLOR))

	for o in OBSTACLES:
		var ground: Vector2 = o[0]
		var size: Vector3 = o[1]
		add_child(_make_box(Vector3(ground.x, size.y / 2, ground.y), size, OBSTACLE_COLOR))
		_blocked.append(Rect2(ground.x - size.x / 2, ground.y - size.z / 2, size.x, size.z))


## Crée un bloc solide : un visuel (MeshInstance3D) + une collision (BoxShape3D).
func _make_box(center: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	body.add_child(visual)

	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	return body


# ---------------------------------------------------------------- Apparitions

func _spawn_targets() -> void:
	for i in TARGET_COUNT:
		var target := TargetScene.instantiate()
		add_child(target)
		var spot := _random_free_spot(1.5)
		target.global_position = Vector3(spot.x, 0.0, spot.y)
		# La cible occupe sa place : rien d'autre n'apparaîtra dessus.
		_blocked.append(Rect2(spot.x - 0.5, spot.y - 0.5, 1.0, 1.0))


func _spawn_player() -> void:
	var player := PlayerScene.instantiate()
	add_child(player)
	var spot := _random_free_spot(1.0)
	player.global_position = Vector3(spot.x, 0.1, spot.y)
	player.rotation.y = randf() * TAU  # orientation de départ aléatoire

	player.ammo_changed.connect(_on_ammo_changed)
	player.hit_confirmed.connect(_on_hit_confirmed)


## Tire une position au sol au hasard jusqu'à en trouver une hors des obstacles.
func _random_free_spot(margin: float) -> Vector2:
	var limit := MAP_SIZE / 2.0 - WALL_THICKNESS - margin
	for i in 100:
		var spot := Vector2(randf_range(-limit, limit), randf_range(-limit, limit))
		var free := true
		for rect in _blocked:
			if rect.grow(margin).has_point(spot):
				free = false
				break
		if free:
			return spot
	return Vector2(-25, -25)  # coin, toujours libre


# ---------------------------------------------------------------- HUD

func _on_ammo_changed(ammo: int, mag_size: int, reloading: bool) -> void:
	if reloading:
		ammo_label.text = "Rechargement…"
	else:
		ammo_label.text = "%d / %d" % [ammo, mag_size]


## Le réticule devient rouge (touché) ou se transforme en X (élimination).
func _on_hit_confirmed(killed: bool) -> void:
	if _crosshair_tween:
		_crosshair_tween.kill()
	crosshair.text = "X" if killed else "+"
	crosshair.modulate = Color(1, 0.2, 0.2)
	_crosshair_tween = create_tween()
	_crosshair_tween.tween_interval(0.25 if killed else 0.1)
	_crosshair_tween.tween_callback(func() -> void:
		crosshair.text = "+"
		crosshair.modulate = Color.WHITE
	)
