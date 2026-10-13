extends CanvasLayer
## Interface en jeu : vie, capacité, munitions, réticule, effets de dégâts,
## écran de mort. Tout est construit ici en code ; on l'attache au joueur avec bind().

const FONT_BIG := 40
const PANEL_BG := Color(0.05, 0.06, 0.09, 0.6)

var _player: Node

var _health_bar: ProgressBar
var _health_fill: StyleBoxFlat
var _health_label: Label
var _class_label: Label
var _ability_bar: ProgressBar
var _ability_fill: StyleBoxFlat
var _ability_label: Label
var _weapon_label: Label
var _ammo_label: Label
var _reload_bar: ProgressBar
var _crosshair: Label
var _vignette: ColorRect
var _death_panel: Control
var _death_label: Label
var _hint: Label
var _crosshair_tween: Tween
var _vignette_tween: Tween


func _ready() -> void:
	_build()


## Relie le HUD à un joueur (appelé par la scène de jeu).
func bind(player: Node) -> void:
	_player = player
	var data: ClassData = player.class_data
	_class_label.text = data.display_name.to_upper()
	_class_label.add_theme_color_override("font_color", data.color.lightened(0.25))
	_ability_fill.bg_color = data.color
	_weapon_label.text = data.weapon.display_name
	player.health_changed.connect(_on_health_changed)
	player.damaged.connect(_on_damaged)
	player.ammo_changed.connect(_on_ammo_changed)
	player.hit_confirmed.connect(_on_hit_confirmed)
	# Affiche tout de suite l'état actuel (les signaux du joueur ont pu partir avant le branchement).
	_on_health_changed(player.health, data.max_health)
	_on_ammo_changed(player.weapon.ammo, data.weapon.mag_size, player.weapon.is_reloading())


func _process(_delta: float) -> void:
	if _player == null:
		return
	var data: ClassData = _player.class_data
	# Capacité : barre de recharge.
	var ratio: float = _player.ability_ready_ratio()
	_ability_bar.value = ratio
	if _player.ability_active():
		_ability_label.text = "%s  ACTIVE" % data.ability_name
	elif ratio >= 1.0:
		_ability_label.text = "[E]  %s  PRÊT" % data.ability_name
	else:
		_ability_label.text = "[E]  %s  %.1f s" % [data.ability_name, (1.0 - ratio) * data.ability_cooldown]
	_ability_fill.bg_color = data.color if ratio >= 1.0 else data.color.darkened(0.5)

	# Rechargement.
	var weapon: Node = _player.weapon
	_reload_bar.visible = weapon.is_reloading()
	_reload_bar.value = weapon.reload_progress()

	# Réticule masqué en courant, plus discret en visant.
	_crosshair.visible = _player.alive and not _player.is_sprinting()


# ---------------------------------------------------------------- Événements

func _on_health_changed(health: int, max_health: int) -> void:
	_health_bar.max_value = max_health
	var tween := create_tween()
	tween.tween_property(_health_bar, "value", float(health), 0.15)
	_health_label.text = "%d / %d" % [health, max_health]
	var ratio := float(health) / max_health
	_health_fill.bg_color = Color(0.9, 0.25, 0.25) if ratio < 0.35 else Color(0.35, 0.85, 0.45)


func _on_damaged(_amount: int) -> void:
	if _vignette_tween:
		_vignette_tween.kill()
	_vignette.color.a = 0.35
	_vignette_tween = create_tween()
	_vignette_tween.tween_property(_vignette, "color:a", 0.0, 0.4)


func _on_ammo_changed(ammo: int, mag_size: int, reloading: bool) -> void:
	_ammo_label.text = "RECHARGE…" if reloading else "%d / %d" % [ammo, mag_size]
	var low: bool = not reloading and ammo <= maxi(1, mag_size / 4)
	_ammo_label.add_theme_color_override("font_color", Color(1, 0.4, 0.3) if low else Color.WHITE)


## Réticule rouge quand on touche, X quand on élimine.
func _on_hit_confirmed(killed: bool) -> void:
	if _crosshair_tween:
		_crosshair_tween.kill()
	_crosshair.text = "✕" if killed else "+"
	_crosshair.modulate = Color(1, 0.25, 0.25)
	_crosshair.scale = Vector2.ONE * (1.6 if killed else 1.25)
	_crosshair_tween = create_tween().set_parallel()
	_crosshair_tween.tween_property(_crosshair, "scale", Vector2.ONE, 0.2)
	_crosshair_tween.tween_property(_crosshair, "modulate", Color.WHITE, 0.3 if killed else 0.12)
	_crosshair_tween.chain().tween_callback(func() -> void: _crosshair.text = "+")


func show_death(killer_name: String) -> void:
	_death_panel.visible = true
	_death_label.text = "ÉLIMINÉ" if killer_name.is_empty() else "ÉLIMINÉ PAR %s" % killer_name.to_upper()


func set_respawn_countdown(seconds: float) -> void:
	_hint.text = "Réapparition dans %d…" % ceili(seconds)


func hide_death() -> void:
	_death_panel.visible = false
	_hint.text = ""


# ---------------------------------------------------------------- Construction

func _build() -> void:
	# Flash rouge sur tout l'écran quand on prend des dégâts.
	_vignette = ColorRect.new()
	_vignette.color = Color(0.8, 0.0, 0.0, 0.0)
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vignette)

	# Aide des touches (haut gauche).
	var help := _label("Clic : tirer   Clic droit : viser   R : recharger   E : capacité   Maj : courir   Espace : sauter   Ctrl / C : s'accroupir   Échap : menu   F9 : test dégâts", 13, Color(1, 1, 1, 0.55))
	_place(help, Control.PRESET_TOP_LEFT, Rect2(16, 10, 1200, 24))
	add_child(help)

	# Réticule (centre).
	_crosshair = _label("+", 30, Color.WHITE)
	_crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_place(_crosshair, Control.PRESET_CENTER, Rect2(-20, -20, 40, 40))
	_crosshair.pivot_offset = Vector2(20, 20)
	_crosshair.add_theme_constant_override("outline_size", 6)
	_crosshair.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	add_child(_crosshair)

	# Bloc vie + capacité (bas gauche).
	var left := _panel()
	_place(left, Control.PRESET_BOTTOM_LEFT, Rect2(24, -24, 360, 0))
	add_child(left)
	var lbox := VBoxContainer.new()
	lbox.add_theme_constant_override("separation", 6)
	left.add_child(lbox)

	var top := HBoxContainer.new()
	_class_label = _label("CLASSE", 18, Color.WHITE)
	_class_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_class_label)
	_health_label = _label("100 / 100", 18, Color.WHITE)
	top.add_child(_health_label)
	lbox.add_child(top)

	_health_fill = _flat(Color(0.35, 0.85, 0.45), 4)
	_health_bar = _bar(_health_fill, 18)
	lbox.add_child(_health_bar)

	_ability_label = _label("[E] Capacité", 14, Color(1, 1, 1, 0.85))
	lbox.add_child(_ability_label)
	_ability_fill = _flat(Color.WHITE, 3)
	_ability_bar = _bar(_ability_fill, 8)
	_ability_bar.max_value = 1.0
	lbox.add_child(_ability_bar)

	# Bloc arme (bas droite).
	var right := _panel()
	_place(right, Control.PRESET_BOTTOM_RIGHT, Rect2(-284, -24, 260, 0))
	add_child(right)
	var rbox := VBoxContainer.new()
	rbox.add_theme_constant_override("separation", 2)
	right.add_child(rbox)
	_weapon_label = _label("Arme", 16, Color(1, 1, 1, 0.7))
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rbox.add_child(_weapon_label)
	_ammo_label = _label("0 / 0", FONT_BIG, Color.WHITE)
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rbox.add_child(_ammo_label)
	_reload_bar = _bar(_flat(Color(1, 0.85, 0.4), 3), 6)
	_reload_bar.max_value = 1.0
	_reload_bar.visible = false
	rbox.add_child(_reload_bar)

	# Écran de mort.
	_death_panel = ColorRect.new()
	(_death_panel as ColorRect).color = Color(0.25, 0.0, 0.0, 0.45)
	_death_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_panel.visible = false
	add_child(_death_panel)
	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	_death_panel.add_child(center)
	_death_label = _label("ÉLIMINÉ", 56, Color(1, 0.35, 0.3))
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_death_label)
	_hint = _label("", 22, Color.WHITE)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_hint)


## Ancre un élément à un coin de l'écran. `rect` = décalage depuis l'ancre + taille.
## Les éléments ancrés en bas grandissent vers le haut.
func _place(control: Control, preset: Control.LayoutPreset, rect: Rect2) -> void:
	control.set_anchors_preset(preset)
	control.offset_left = rect.position.x
	control.offset_right = rect.position.x + rect.size.x
	control.offset_top = rect.position.y - rect.size.y if control.anchor_top == 1.0 else rect.position.y
	control.offset_bottom = rect.position.y if control.anchor_top == 1.0 else rect.position.y + rect.size.y
	if control.anchor_top == 1.0:
		control.grow_vertical = Control.GROW_DIRECTION_BEGIN


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := _flat(PANEL_BG, 10)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel


func _bar(fill: StyleBoxFlat, height: int) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, height)
	bar.add_theme_stylebox_override("background", _flat(Color(1, 1, 1, 0.1), 4))
	bar.add_theme_stylebox_override("fill", fill)
	return bar


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _flat(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	return style
