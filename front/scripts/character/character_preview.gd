class_name CharacterPreview
extends SubViewportContainer
## Petite scène 3D dans l'interface : un personnage qui tourne lentement et
## enchaîne ses animations (repos, marche, course, accroupi, saut, visée).
## Utilisée sur l'écran de choix de classe.

## Poses présentées en boucle : [nom, vitesse locale, au sol, accroupi, visée verticale, sprint].
const POSES := [
	["Repos", Vector3.ZERO, true, 0.0, 0.0, false],
	["Marche", Vector3(0, 0, -4.5), true, 0.0, 0.0, false],
	["Course", Vector3(0, 0, -8.5), true, 0.0, 0.0, true],
	["Accroupi", Vector3(0, 0, -1.5), true, 1.0, 0.0, false],
	["Saut", Vector3(0, 2.5, -4.0), false, 0.0, 0.0, false],
	["Visée", Vector3.ZERO, true, 0.0, 0.35, false],
]
const POSE_DURATION := 2.2

var rig   # HumanRig ou CharacterRig
var pose_label: Label
var _pose_index := 0
var _pose_time := 0.0
var _viewport: SubViewport
var _time := 0.0


## Poses jouées (noms de POSES). Vide = toutes.
var pose_names: Array = []
var show_pose_label := true
var _poses: Array = []


## design_id : apparence (tank, assassin, tireur), weapon_kind : modèle d'arme.
## camera_distance / camera_height : cadrage (plus loin = personnage plus petit).
func setup(design_id: String, weapon_kind: int, size_px: Vector2i, camera_distance := 4.3, camera_height := 1.05) -> void:
	_poses = POSES.filter(func(p): return pose_names.is_empty() or pose_names.has(p[0]))
	stretch = true
	custom_minimum_size = size_px
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true          # chaque aperçu a son propre monde 3D
	_viewport.transparent_bg = true        # on voit le fond de la carte derrière
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.size = size_px
	add_child(_viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.68)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_ACES

	var camera := Camera3D.new()
	camera.environment = env
	camera.fov = 30.0
	_viewport.add_child(camera)
	# Orientation calculée à la main : le nœud n'est pas forcément déjà dans la scène.
	var eye := Vector3(0, camera_height, camera_distance)
	camera.transform = Transform3D(Basis.looking_at(Vector3(0, 0.88, 0) - eye, Vector3.UP), eye)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.5
	_viewport.add_child(key)
	key.rotation_degrees = Vector3(-35, 25, 0)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.8
	rim.light_color = Color(0.7, 0.8, 1.0)
	_viewport.add_child(rim)
	rim.rotation_degrees = Vector3(-20, 160, 0)

	rig = HumanRig.new() if HumanDesigns.has_design(design_id) else CharacterRig.new()
	_viewport.add_child(rig)
	rig.build(design_id, weapon_kind)
	rig.rotation.y = PI

	pose_label = Label.new()
	pose_label.add_theme_font_size_override("font_size", 12)
	pose_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	pose_label.position = Vector2(8, size_px.y - 22)
	pose_label.visible = show_pose_label
	add_child(pose_label)
	_apply_pose()


func _process(delta: float) -> void:
	if rig == null:
		return
	# Oscille autour de la vue de face (trois quarts gauche <-> trois quarts droit).
	_time += delta
	rig.rotation.y = PI + 0.25 + sin(_time * 0.7) * 0.7
	_pose_time += delta
	if _pose_time > POSE_DURATION:
		_pose_time = 0.0
		_pose_index = (_pose_index + 1) % _poses.size()
	_apply_pose()


func _apply_pose() -> void:
	var p: Array = _poses[_pose_index]
	rig.set_state(p[1], p[2], p[3], p[4], p[5], false)
	pose_label.text = p[0]
