class_name LegendaryCinematic
extends Node3D
## Cinématique d'apparition de l'arme légendaire (voir LegendaryEvent) : bandes noires,
## caméra qui descend du ciel en tournant autour du socle, colonne de lumière dorée,
## le Canon du Shōgun qui se forme en tournant, titre, son.
##
## Pendant la cinématique la partie est figée (Engine.time_scale = 0) : tout ici suit
## le temps réel (Time.get_ticks_msec), pas le `delta` du moteur. Construit par le
## code ; la partie (game.gd) la crée, puis la libère à la fin (signal `finished`).

signal finished

const PILLAR_HEIGHT := 60.0

var _center := Vector3.ZERO
var _duration := LegendaryEvent.CINEMATIC_TIME
var _start_ms := 0
var _done := false
var _camera: Camera3D
var _pillar: MeshInstance3D
var _pillar_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D
var _light: OmniLight3D
var _cannon: Node3D
var _bars: Array[ColorRect] = []
var _titles: Control


## Lance la cinématique autour de `center` (position du socle), pour `duration` s.
func play(center: Vector3, duration: float) -> void:
	_center = center
	_duration = maxf(duration, 0.5)
	_start_ms = Time.get_ticks_msec()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_scene()
	_build_overlay()
	Sfx.play("legendary", 0.0)
	_process(0.0)


func _build_scene() -> void:
	_camera = Camera3D.new()
	_camera.fov = 62.0
	add_child(_camera)
	_camera.make_current()

	# Colonne de lumière dorée qui descend du ciel.
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.6
	cylinder.bottom_radius = 1.6
	cylinder.height = PILLAR_HEIGHT
	_pillar = MeshInstance3D.new()
	_pillar.mesh = cylinder
	_pillar_mat = _glow_material(Color(LegendaryEvent.GOLD, 0.0))
	_pillar.material_override = _pillar_mat
	_pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pillar)

	# Anneau au sol.
	var disc := CylinderMesh.new()
	disc.top_radius = 3.0
	disc.bottom_radius = 3.0
	disc.height = 0.05
	var ring := MeshInstance3D.new()
	ring.mesh = disc
	_ring_mat = _glow_material(Color(LegendaryEvent.GOLD, 0.0))
	ring.material_override = _ring_mat
	add_child(ring)
	ring.global_position = _center + Vector3.UP * 0.2

	_light = OmniLight3D.new()
	_light.light_color = LegendaryEvent.GOLD
	_light.omni_range = 14.0
	add_child(_light)
	_light.global_position = _center + Vector3.UP * 2.5

	_cannon = Node3D.new()
	LegendaryEvent.build_cannon(_cannon)
	_cannon.scale = Vector3.ZERO
	add_child(_cannon)


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		root.add_child(bar)
		_bars.append(bar)
	_titles = VBoxContainer.new()
	_titles.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_titles.offset_top = -230.0
	_titles.offset_bottom = -110.0
	_titles.offset_left = -400.0
	_titles.offset_right = 400.0
	_titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_titles.modulate.a = 0.0
	root.add_child(_titles)
	var kicker := UiTheme.label("ARME LÉGENDAIRE", 22, Color.WHITE, true)
	kicker.add_theme_constant_override("outline_size", 8)
	kicker.add_theme_color_override("font_outline_color", Color(0.2, 0.08, 0.0))
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_titles.add_child(kicker)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	_titles.add_child(row)
	var name_label := UiTheme.label("CANON DU SHŌGUN", 54, LegendaryEvent.GOLD, true)
	name_label.add_theme_constant_override("outline_size", 10)
	name_label.add_theme_color_override("font_outline_color", Color(0.2, 0.08, 0.0))
	row.add_child(name_label)
	var kanji := UiTheme.label("将軍", 50, LegendaryEvent.GOLD)
	kanji.add_theme_font_override("font", JapaneseFont.font())
	row.add_child(kanji)
	var hint := UiTheme.label("Un tir, une élimination · traverse les murs · 6 tirs", 18, Color.WHITE)
	hint.add_theme_constant_override("outline_size", 6)
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_titles.add_child(hint)


func _glow_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = color
	return m


func _process(_delta: float) -> void:
	if _camera == null:
		return
	var seconds := (Time.get_ticks_msec() - _start_ms) / 1000.0
	var t := clampf(seconds / _duration, 0.0, 1.0)

	# Caméra : descend du ciel en tournant, finit près du socle.
	var approach := smoothstep(0.0, 0.75, t)
	var angle := lerpf(-0.7, 1.9, ease(t, 0.6))
	var radius := lerpf(26.0, 6.5, approach)
	var height := lerpf(30.0, 2.4, approach)
	var focus := _center + Vector3.UP * 1.6
	var wanted := _center + Vector3(sin(angle) * radius, height, cos(angle) * radius)
	# Intérieur (Hikari Mall) : la caméra reste du bon côté des plafonds et des murs.
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(focus, wanted))
	if not hit.is_empty():
		wanted = (hit.position as Vector3) + (focus - wanted).normalized() * 0.5
	_camera.global_position = wanted
	if wanted.distance_to(focus) > 0.3:
		_camera.look_at(focus, Vector3.UP)

	# Colonne : descend (0 -> 35 %), brille, puis s'efface à la fin.
	var fall := smoothstep(0.0, 0.35, t)
	_pillar.global_position = _center + Vector3.UP * lerpf(PILLAR_HEIGHT * 1.5, PILLAR_HEIGHT * 0.5, fall)
	var glow := fall * (1.0 - smoothstep(0.85, 1.0, t))
	# Plus discrète quand la caméra arrive près du socle (on doit voir l'arme).
	_pillar_mat.albedo_color = Color(LegendaryEvent.GOLD, lerpf(0.35, 0.12, approach) * glow)
	_ring_mat.albedo_color = Color(LegendaryEvent.GOLD, 0.3 * fall)
	_light.light_energy = (2.0 + 1.5 * sin(seconds * 6.0)) * fall

	# Le canon se forme (35 -> 55 %) puis tourne en flottant.
	var grow := smoothstep(0.35, 0.55, t)
	_cannon.scale = Vector3.ONE * 2.2 * ease(grow, 0.4)
	_cannon.global_position = _center + Vector3.UP * (1.6 + sin(seconds * 2.0) * 0.12)
	_cannon.rotation.y = seconds * 1.4

	# Bandes noires et titre.
	var bars := smoothstep(0.0, 0.1, t) * (1.0 - smoothstep(0.92, 1.0, t))
	var bar_height := get_viewport().get_visible_rect().size.y * 0.11 * bars
	_bars[0].offset_bottom = bar_height
	_bars[1].offset_top = -bar_height
	_titles.modulate.a = smoothstep(0.42, 0.52, t) * (1.0 - smoothstep(0.9, 0.98, t))

	if t >= 1.0 and not _done:
		_done = true
		finished.emit()
