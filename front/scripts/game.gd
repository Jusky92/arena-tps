extends Node3D
## Scène de jeu : charge la map, fait apparaître le joueur (avec la classe choisie)
## et les cibles d'entraînement, relie le HUD, gère la mort et la réapparition,
## capture la souris, et revient au menu avec Échap.
##
## La map est une scène à part (scenes/maps/) : le futur serveur de jeu pourra
## charger exactement la même.

const RESPAWN_DELAY := 3.0      # secondes avant de réapparaître

const MapScene := preload("res://scenes/maps/arena.tscn")
const PlayerScene := preload("res://scenes/player.tscn")
const TargetScene := preload("res://scenes/target_dummy.tscn")

@onready var hud: CanvasLayer = $HUD

var map: ArenaMap
var player: CharacterBody3D

var _respawn_timer: float = 0.0
var _last_spawn_index: int = -1


func _ready() -> void:
	map = MapScene.instantiate()
	add_child(map)
	_spawn_targets()
	_spawn_player()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if _respawn_timer > 0.0:
		_respawn_timer -= delta
		hud.set_respawn_countdown(_respawn_timer)
		if _respawn_timer <= 0.0:
			_respawn_player()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("back_to_menu"):
		get_tree().change_scene_to_file("res://scenes/menu.tscn")
	# Si la souris a été libérée (Alt+Tab…), un clic la recapture.
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ---------------------------------------------------------------- Apparitions

func _spawn_targets() -> void:
	var index := 0
	for point in ArenaMap.TARGET_POINTS:
		var target := TargetScene.instantiate()
		target.crouched = index % 3 == 2   # un mannequin sur trois est accroupi
		add_child(target)
		target.global_position = point
		target.rotation.y = randf() * TAU
		index += 1


func _spawn_player() -> void:
	player = PlayerScene.instantiate()
	player.class_data = GameState.selected_class
	add_child(player)
	player.global_transform = _next_spawn()

	hud.bind(player)
	player.died.connect(_on_player_died)
	player.hit_confirmed.connect(func(killed: bool) -> void:
		if killed:
			player.kills += 1)


## Point d'apparition au hasard, jamais deux fois de suite le même.
## (Plus tard, côté serveur : choisir le point le plus éloigné des ennemis.)
func _next_spawn() -> Transform3D:
	var spawns := map.get_spawn_transforms()
	var index := randi() % spawns.size()
	if index == _last_spawn_index:
		index = (index + 1) % spawns.size()
	_last_spawn_index = index
	return spawns[index]


func _on_player_died(killer: Node) -> void:
	var killer_name := ""
	if killer != null and killer != player:
		killer_name = killer.name
	hud.show_death(killer_name)
	_respawn_timer = RESPAWN_DELAY


func _respawn_player() -> void:
	var spawn := _next_spawn()
	player.respawn(spawn.origin, spawn.basis.get_euler().y)
	hud.hide_death()
