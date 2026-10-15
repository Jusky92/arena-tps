class_name SettingsPanel
extends ScrollContainer
## Réglages du joueur : son, souris et touches. Utilisé par la page PARAMÈTRES du
## menu principal (roue crantée) et par le menu pause en partie.
##
## Son et souris : autoload Settings (user://parametres.cfg).
## Touches : autoload Inputs (user://touches.cfg). Clic sur une touche, puis appui
## sur la nouvelle touche ou le nouveau bouton de souris ; Échap annule, clic droit
## sur une touche l'efface. Une touche déjà prise est retirée de l'autre action.

var _values := {}                # clé de réglage -> [Label de la valeur, format]
var _sliders := {}               # clé de réglage -> HSlider
var _invert_button: Button
var _key_buttons := {}           # action -> [Button, Button]
var _keys_status: Label
## Saisie en cours : action et emplacement qui attendent une touche ("" = aucune).
var _listening_action := ""
var _listening_slot := 0


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 14)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(list)

	list.add_child(UiTheme.label("SON", 15, UiTheme.CYAN, true))
	list.add_child(_slider_row("master_volume", "Volume général", 0.0, 1.0, 0.01, _percent))
	list.add_child(_slider_row("sfx_volume", "Effets (tirs, impacts, capacités)", 0.0, 1.0, 0.01, _percent))
	list.add_child(_slider_row("ui_volume", "Interface (menus)", 0.0, 1.0, 0.01, _percent))

	list.add_child(UiTheme.spacer(Vector2(0, 4)))
	list.add_child(UiTheme.label("SOURIS", 15, UiTheme.CYAN, true))
	list.add_child(_slider_row("sensitivity", "Sensibilité de la caméra", 0.2, 3.0, 0.05, func(v: float) -> String: return "x%.2f" % v))
	var invert_row := HBoxContainer.new()
	var invert_label := UiTheme.label("Inverser l'axe vertical", 17, UiTheme.TEXT)
	invert_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	invert_row.add_child(invert_label)
	_invert_button = UiTheme.button("NON", false, UiTheme.CYAN, 38)
	_invert_button.toggle_mode = true
	_invert_button.custom_minimum_size.x = 110
	_invert_button.toggled.connect(func(on: bool) -> void:
		Settings.set_value("invert_y", on)
		_invert_button.text = "OUI" if on else "NON"
		Sfx.ui("ui_click"))
	invert_row.add_child(_invert_button)
	list.add_child(invert_row)
	var reset := UiTheme.button("SON ET SOURIS PAR DÉFAUT", false, UiTheme.CYAN, 40)
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.pressed.connect(func() -> void:
		Settings.reset_defaults()
		refresh()
		Sfx.ui("ui_click"))
	list.add_child(reset)

	list.add_child(UiTheme.spacer(Vector2(0, 4)))
	list.add_child(UiTheme.label("TOUCHES", 15, UiTheme.CYAN, true))
	_keys_status = UiTheme.label("", 14, UiTheme.MUTED)
	_keys_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(_keys_status)
	for entry in Inputs.REBINDABLE:
		list.add_child(_key_row(entry[0], entry[1]))
	var reset_keys := UiTheme.button("TOUCHES PAR DÉFAUT", false, UiTheme.CYAN, 40)
	reset_keys.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset_keys.pressed.connect(func() -> void:
		_stop_listening()
		Inputs.reset_bindings()
		_keys_status.text = "Touches par défaut rétablies."
		Sfx.ui("ui_click"))
	list.add_child(reset_keys)

	Inputs.bindings_changed.connect(_refresh_keys)
	visibility_changed.connect(func() -> void:
		if not is_visible_in_tree():
			_stop_listening()
			Settings.save_settings())
	refresh()


func _exit_tree() -> void:
	Settings.save_settings()


## Remet les curseurs et les touches sur les valeurs enregistrées.
func refresh() -> void:
	for key in _sliders:
		var value: float = Settings.get(key)
		(_sliders[key] as HSlider).set_value_no_signal(value)
		var entry: Array = _values[key]
		(entry[0] as Label).text = (entry[1] as Callable).call(value)
	_invert_button.set_pressed_no_signal(Settings.invert_y)
	_invert_button.text = "OUI" if Settings.invert_y else "NON"
	_stop_listening()


# ---------------------------------------------------------------- Son et souris

func _slider_row(key: String, title: String, min_value: float, max_value: float, step: float, format: Callable) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var top := HBoxContainer.new()
	var t := UiTheme.label(title, 17, UiTheme.TEXT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	var value_label := UiTheme.label("", 17, UiTheme.CYAN, true)
	top.add_child(value_label)
	row.add_child(top)

	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.scrollable = false       # la molette fait défiler la liste, pas le curseur
	slider.custom_minimum_size = Vector2(0, 24)
	slider.value_changed.connect(func(v: float) -> void:
		Settings.set_value(key, v)
		value_label.text = format.call(v))
	# Petit son de test quand on relâche le curseur d'un volume.
	slider.drag_ended.connect(func(_changed: bool) -> void:
		if key == "ui_volume":
			Sfx.ui("ui_click")
		elif key.ends_with("volume"):
			Sfx.play("hit"))
	row.add_child(slider)
	_sliders[key] = slider
	_values[key] = [value_label, format]
	return row


func _percent(v: float) -> String:
	return "%d %%" % roundi(v * 100.0)


# ---------------------------------------------------------------- Touches

func _key_row(action: String, title: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := UiTheme.label(title, 17, UiTheme.TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var buttons: Array[Button] = []
	for slot in Inputs.SLOTS:
		var b := UiTheme.button("", false, UiTheme.CYAN, 36)
		b.custom_minimum_size.x = 150
		b.clip_text = true
		b.tooltip_text = "Clic : changer la touche. Clic droit : l'effacer."
		b.pressed.connect(_start_listening.bind(action, slot))
		b.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT \
					and _listening_action.is_empty():
				Inputs.unbind(action, slot)
				Sfx.ui("ui_close", -4.0)
				accept_event())
		row.add_child(b)
		buttons.append(b)
	_key_buttons[action] = buttons
	return row


func _refresh_keys() -> void:
	for action in _key_buttons:
		var events := Inputs.events_of(action)
		var buttons: Array = _key_buttons[action]
		for slot in buttons.size():
			var b: Button = buttons[slot]
			if action == _listening_action and slot == _listening_slot:
				b.text = "…"
				b.add_theme_color_override("font_color", UiTheme.YELLOW)
			else:
				b.text = Inputs.event_label(events[slot]) if slot < events.size() else "—"
				b.remove_theme_color_override("font_color")
	if _listening_action.is_empty() and _keys_status.text.is_empty():
		_keys_status.text = "Clic sur une touche pour la changer, clic droit pour l'effacer."


func _start_listening(action: String, slot: int) -> void:
	Sfx.ui("ui_click")
	_listening_action = action
	_listening_slot = slot
	_keys_status.text = "Appuie sur la nouvelle touche (ou un bouton de la souris) pour « %s ». Échap pour annuler." % _action_title(action)
	_refresh_keys()


func _stop_listening() -> void:
	_listening_action = ""
	if is_instance_valid(_keys_status):
		_keys_status.text = ""
		_refresh_keys()


## Saisie d'une touche : passe avant tout le reste (le menu pause ne se ferme pas
## sur Échap, un clic ne déclenche pas de bouton).
func _input(event: InputEvent) -> void:
	if _listening_action.is_empty() or not event.is_pressed() or event.is_echo():
		return
	if not (event is InputEventKey or event is InputEventMouseButton):
		return
	get_viewport().set_input_as_handled()
	if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		Sfx.ui("ui_close", -4.0)
		_stop_listening()
		return
	var action := _listening_action
	_listening_action = ""
	var taken_from := Inputs.bind(action, _listening_slot, event)
	_keys_status.text = ("« %s » : %s." % [_action_title(action), Inputs.event_label(event)]) \
		+ (" Retirée de « %s »." % taken_from if not taken_from.is_empty() else "")
	Sfx.ui("ui_click")
	_refresh_keys()


func _action_title(action: String) -> String:
	for entry in Inputs.REBINDABLE:
		if entry[0] == action:
			return entry[1]
	return action
