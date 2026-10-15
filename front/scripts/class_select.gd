extends Control
## Écran de choix du spécialiste : une carte par spécialiste avec le personnage en
## 3D animé, ses statistiques et sa capacité. Les armes viennent de la classe
## (équipement) choisie dans l'accueil : n'importe quel spécialiste peut les porter.
## Les cartes sont générées depuis GameState.CLASSES : ajouter une classe
## l'ajoute automatiquement ici.
## Souris ou touches 1, 2, 3 pour choisir (retour au menu principal). Échap pour revenir.

const CARD_WIDTH := 270.0
const PREVIEW_SIZE := Vector2i(224, 200)
const BG_CARD := Color(0.05, 0.065, 0.1, 0.92)

# Valeurs de référence pour remplir les barres de stats.
const MAX_HEALTH_REF := 150.0
const MAX_SPEED_REF := 9.5
const MAX_JUMP_REF := 6.0
const MAX_COOLDOWN_REF := 14.0

@onready var cards_box: HBoxContainer = %Cards
@onready var back_button: Button = %BackButton


func _ready() -> void:
	theme = UiTheme.get_theme()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var background := UiTheme.background()
	add_child(background)
	move_child(background, 1)
	($Margin/VBox/TopBar/Title as Label).add_theme_font_override("font", UiTheme.title_font())
	back_button.pressed.connect(_go_back)
	for i in GameState.CLASSES.size():
		cards_box.add_child(_make_card(GameState.CLASSES[i], i))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_back()
	elif event is InputEventKey and event.pressed and not event.echo:
		# Touche physique : marche aussi en AZERTY sans appuyer sur Maj.
		var index: int = event.physical_keycode - KEY_1
		if index >= 0 and index < GameState.CLASSES.size():
			_choose(GameState.CLASSES[index])


func _choose(class_data: ClassData) -> void:
	GameState.select_specialist(class_data)
	var loadout := GameState.current_loadout()
	Net.set_loadout(class_data.resource_path, loadout.primary, loadout.secondary)
	_go_back()


## Ouvert depuis le salon d'une partie en ligne : on y retourne, toujours connecté.
func _go_back() -> void:
	if Net.online:
		get_tree().change_scene_to_file("res://scenes/lobby.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# ---------------------------------------------------------------- Construction des cartes

func _make_card(data: ClassData, index: int) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	var normal_style := _card_style(data.color, false)
	var hover_style := _card_style(data.color, true)
	card.add_theme_stylebox_override("panel", normal_style)
	card.mouse_entered.connect(func() -> void:
		card.add_theme_stylebox_override("panel", hover_style)
		_animate_scale(card, 1.03))
	card.mouse_exited.connect(func() -> void:
		card.add_theme_stylebox_override("panel", normal_style)
		_animate_scale(card, 1.0))
	card.resized.connect(func() -> void: card.pivot_offset = card.size / 2.0)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	card.add_child(box)

	# Personnage en 3D, avec le nom de la classe et la touche par-dessus.
	var preview_holder := Control.new()
	preview_holder.custom_minimum_size = Vector2(PREVIEW_SIZE)
	preview_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glow := ColorRect.new()
	glow.color = Color(data.color, 0.08)
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_holder.add_child(glow)
	var preview := CharacterPreview.new()
	preview_holder.add_child(preview)
	var primary := WeaponCatalog.find(GameState.current_loadout().primary)
	preview.setup(data.character_design, primary.model if primary else data.weapon.model, PREVIEW_SIZE)
	var name_label := _label(data.display_name.to_upper(), 26, Color.WHITE)
	name_label.add_theme_font_override("font", UiTheme.title_font())
	name_label.position = Vector2(10, 4)
	name_label.add_theme_constant_override("outline_size", 6)
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	preview_holder.add_child(name_label)
	var key_label := _label("[%d]" % (index + 1), 16, Color(1, 1, 1, 0.45))
	key_label.position = Vector2(PREVIEW_SIZE.x - 34, 10)
	preview_holder.add_child(key_label)
	box.add_child(preview_holder)

	var desc := _label(data.description, 13, Color(1, 1, 1, 0.75))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(desc)

	# Statistiques du spécialiste (les armes viennent de la classe choisie dans l'accueil).
	box.add_child(_stat_bar("Points de vie", data.max_health / MAX_HEALTH_REF, str(data.max_health), data.color))
	box.add_child(_stat_bar("Vitesse", data.sprint_speed / MAX_SPEED_REF, "%.1f m/s" % data.sprint_speed, data.color))
	box.add_child(_stat_bar("Saut", data.jump_velocity / MAX_JUMP_REF, "%.1f m/s" % data.jump_velocity, data.color))
	box.add_child(_stat_bar("Recharge de la capacité", 1.0 - data.ability_cooldown / MAX_COOLDOWN_REF,
		"%d s" % int(data.ability_cooldown), data.color))

	box.add_child(HSeparator.new())

	# Capacité.
	box.add_child(_label("CAPACITÉ [E]  ·  %s" % data.ability_name, 15, data.color.lightened(0.35)))
	var ability_desc := _label("%s (recharge %d s)" % [data.ability_description, int(data.ability_cooldown)], 12, Color(1, 1, 1, 0.6))
	ability_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(ability_desc)

	# Bouton.
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var button := Button.new()
	button.text = "%s %s" % ["SPÉCIALISTE ACTUEL ·" if data == GameState.selected_class else "CHOISIR", data.display_name.to_upper()]
	button.add_theme_font_override("font", UiTheme.title_font())
	button.add_theme_font_size_override("font_size", 14)
	button.custom_minimum_size = Vector2(0, 42)
	button.add_theme_stylebox_override("normal", _button_style(data.color.darkened(0.35)))
	button.add_theme_stylebox_override("hover", _button_style(data.color))
	button.add_theme_stylebox_override("pressed", _button_style(data.color.lightened(0.2)))
	button.add_theme_stylebox_override("focus", _button_style(data.color))
	button.pressed.connect(_choose.bind(data))
	UiTheme.add_hover_feedback(button)
	box.add_child(button)
	return card


func _stat_bar(title: String, ratio: float, value_text: String, color: Color) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var top := HBoxContainer.new()
	var t := _label(title, 13, Color(1, 1, 1, 0.8))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	top.add_child(_label(value_text, 13, Color.WHITE))
	row.add_child(top)

	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 7)
	bar.max_value = 1.0
	bar.value = clampf(ratio, 0.05, 1.0)
	bar.add_theme_stylebox_override("background", _flat(Color(1, 1, 1, 0.08), 2))
	bar.add_theme_stylebox_override("fill", _flat(color, 2))
	row.add_child(bar)
	return row


func _label(text: String, size: int, color: Color) -> Label:
	return UiTheme.label(text, size, color)


## Carte biseautée comme le reste de l'interface ; bordure et halo à la couleur de la classe au survol.
func _card_style(color: Color, hovered: bool) -> StyleBoxFlat:
	var style := UiTheme.box(BG_CARD, color if hovered else Color(1, 1, 1, 0.08), 2 if hovered else 1, 8, 22, 14)
	if hovered:
		style.border_width_left = 4
		style.shadow_color = Color(color, 0.35)
		style.shadow_size = 18
	return style


func _button_style(color: Color) -> StyleBoxFlat:
	return UiTheme.box(color, Color(1, 1, 1, 0.12), 1, 5, 16, 8)


func _flat(color: Color, radius: int) -> StyleBoxFlat:
	return UiTheme.box(color, Color(0, 0, 0, 0), 0, radius, 0, 0)


func _animate_scale(node: Control, target: float) -> void:
	var tween := node.create_tween()
	tween.tween_property(node, "scale", Vector2.ONE * target, 0.12).set_trans(Tween.TRANS_QUAD)
