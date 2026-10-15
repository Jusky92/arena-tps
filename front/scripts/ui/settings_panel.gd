class_name SettingsPanel
extends VBoxContainer
## Réglages du joueur, en trois onglets : VIDÉO, SON, COMMANDES (souris et touches).
## Utilisé par la page PARAMÈTRES du menu principal (roue crantée) et par le menu
## pause en partie.
##
## Vidéo, son et souris : autoload Settings (user://parametres.cfg).
## Touches : autoload Inputs (user://touches.cfg). Clic sur une touche, puis appui
## sur la nouvelle touche ou le nouveau bouton de souris ; Échap annule, clic droit
## sur une touche l'efface. Une touche déjà prise est retirée de l'autre action.
## Vidéo : les choix restent en attente jusqu'à APPLIQUER. Un changement d'affichage
## ou de résolution est alors à confirmer ; sans réponse avant CONFIRM_SECONDS,
## l'affichage précédent revient.

const TABS := [["video", "VIDÉO"], ["audio", "SON"], ["controls", "COMMANDES"]]
const CONFIRM_SECONDS := 15

## Onglet ouvert, gardé d'une ouverture à l'autre (menu principal et menu pause).
static var _last_tab := "video"

var _tab_buttons := {}           # onglet -> Button
var _tab_pages := {}             # onglet -> ScrollContainer
var _values := {}                # clé de réglage -> [Label de la valeur, format]
var _sliders := {}               # clé de réglage -> HSlider
var _invert_button: Button
var _quality_picker: OptionButton
var _quality_help: Label
var _mode_picker: OptionButton
var _resolution_picker: OptionButton
var _resolution_help: Label
## Résolutions de la liste, dans l'ordre des entrées.
var _resolutions: Array[Vector2i] = []
## Choix vidéo pas encore appliqués : clé de Settings -> valeur.
var _pending := {}
var _apply_button: Button
var _apply_status: Label
var _key_buttons := {}           # action -> [Button, Button]
var _keys_status: Label
## Saisie en cours : action et emplacement qui attendent une touche ("" = aucune).
var _listening_action := ""
var _listening_slot := 0
## Confirmation d'affichage en cours : couche par-dessus tout, affichage à rétablir.
var _confirm_layer: CanvasLayer
var _confirm_label: Label
var _confirm_previous := {}
var _confirm_left := 0.0


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 14)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	add_child(tabs)
	var group := ButtonGroup.new()
	for tab in TABS:
		var b := UiTheme.button(tab[1], false, UiTheme.CYAN, 40)
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size.x = 160
		b.pressed.connect(func() -> void:
			Sfx.ui("ui_click")
			_show_tab(tab[0]))
		tabs.add_child(b)
		_tab_buttons[tab[0]] = b
	add_child(UiTheme.neon_line(UiTheme.CYAN, 1))

	_tab_pages["video"] = _build_video_tab()
	_tab_pages["audio"] = _build_audio_tab()
	_tab_pages["controls"] = _build_controls_tab()
	for page in _tab_pages.values():
		add_child(page)

	Inputs.bindings_changed.connect(_refresh_keys)
	visibility_changed.connect(func() -> void:
		if not is_visible_in_tree():
			_stop_listening()
			_revert_display()          # masqué sans réponse : l'ancien affichage revient
			_pending = {}
			Settings.save_settings())
	refresh()
	_show_tab(_last_tab)


func _exit_tree() -> void:
	if not _confirm_previous.is_empty():
		_revert_display()          # page quittée sans répondre : l'ancien affichage revient
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
	_pending = {}
	_refresh_video()
	_stop_listening()


func _show_tab(tab: String) -> void:
	_last_tab = tab
	_stop_listening()
	if not _pending.is_empty():
		_pending = {}             # choix vidéo pas appliqués : abandonnés
		_refresh_video()
	for key in _tab_pages:
		_tab_pages[key].visible = key == tab
		_tab_buttons[key].set_pressed_no_signal(key == tab)


## Page d'onglet : une liste qui défile.
func _tab_page() -> Array:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 14)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	return [scroll, list]


func _reset_button(list: VBoxContainer, text: String, action: Callable) -> void:
	list.add_child(UiTheme.spacer(Vector2(0, 4)))
	var reset := UiTheme.button(text, false, UiTheme.CYAN, 40)
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.pressed.connect(func() -> void:
		action.call()
		Sfx.ui("ui_click"))
	list.add_child(reset)


# ---------------------------------------------------------------- Vidéo

func _build_video_tab() -> ScrollContainer:
	var parts := _tab_page()
	var list: VBoxContainer = parts[1]
	_quality_picker = _picker_row(list, "Qualité des graphismes")
	for i in Settings.QUALITY_NAMES.size():
		_quality_picker.add_item(Settings.QUALITY_NAMES[i], i)
	_quality_picker.item_selected.connect(func(index: int) -> void:
		_set_pending("quality", index))
	_quality_help = _help_label(list)
	_mode_picker = _picker_row(list, "Affichage")
	for i in Settings.WINDOW_MODES.size():
		_mode_picker.add_item(Settings.WINDOW_MODES[i][1], i)
	_mode_picker.item_selected.connect(func(index: int) -> void:
		_set_pending("window_mode", Settings.WINDOW_MODES[index][0]))
	_resolution_picker = _picker_row(list, "Résolution")
	_resolution_picker.item_selected.connect(func(index: int) -> void:
		_set_pending("resolution", _resolutions[index]))
	_resolution_help = _help_label(list)

	list.add_child(UiTheme.spacer(Vector2(0, 4)))
	var apply_row := HBoxContainer.new()
	apply_row.add_theme_constant_override("separation", 14)
	_apply_button = UiTheme.button("APPLIQUER", true, UiTheme.CYAN, 44)
	_apply_button.custom_minimum_size.x = 220
	_apply_button.pressed.connect(func() -> void:
		Sfx.ui("ui_click")
		_apply_video())
	apply_row.add_child(_apply_button)
	_apply_status = UiTheme.label("", 14, UiTheme.YELLOW)
	_apply_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	apply_row.add_child(_apply_status)
	list.add_child(apply_row)
	return parts[0]


## Ligne « titre … liste de choix » ; renvoie la liste.
func _picker_row(list: VBoxContainer, title: String) -> OptionButton:
	var row := HBoxContainer.new()
	var t := UiTheme.label(title, 17, UiTheme.TEXT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(t)
	var picker := OptionButton.new()
	picker.custom_minimum_size.x = 280
	row.add_child(picker)
	list.add_child(row)
	return picker


func _help_label(list: VBoxContainer) -> Label:
	var help := UiTheme.label("", 14, UiTheme.MUTED)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(help)
	return help


## Valeur affichée : le choix en attente, sinon le réglage en cours.
func _video_value(key: String) -> Variant:
	return _pending.get(key, Settings.get(key))


func _set_pending(key: String, value: Variant) -> void:
	if Settings.get(key) == value:
		_pending.erase(key)
	else:
		_pending[key] = value
	_refresh_video()


func _refresh_video() -> void:
	var quality: int = _video_value("quality")
	var mode: String = _video_value("window_mode")
	var resolution: Vector2i = _video_value("resolution")
	_quality_picker.select(quality)
	_quality_help.text = Settings.QUALITY_HELP[quality]
	for i in Settings.WINDOW_MODES.size():
		if Settings.WINDOW_MODES[i][0] == mode:
			_mode_picker.select(i)
	# La liste dépend de l'écran où se trouve la fenêtre.
	_resolutions = Settings.available_resolutions()
	if not resolution in _resolutions:
		_resolutions.append(resolution)
	_resolution_picker.clear()
	for i in _resolutions.size():
		var r := _resolutions[i]
		_resolution_picker.add_item("%d × %d" % [r.x, r.y], i)
		if r == resolution:
			_resolution_picker.select(i)
	_resolution_help.text = "Taille de la fenêtre." if mode == "windowed" \
		else "Résolution du rendu 3D : l'écran garde la sienne et l'interface reste nette."
	_apply_button.disabled = _pending.is_empty()
	_apply_status.text = "Modifications pas encore appliquées." if not _pending.is_empty() else ""


## APPLIQUER : tous les choix en attente d'un coup. Si l'affichage ou la résolution
## change, il faut confirmer avant CONFIRM_SECONDS.
func _apply_video() -> void:
	if _pending.is_empty():
		return
	var display_changed := _pending.has("window_mode") or _pending.has("resolution")
	if display_changed and _confirm_previous.is_empty():
		_confirm_previous = {"window_mode": Settings.window_mode, "resolution": Settings.resolution}
	for key in _pending:
		Settings.set(key, _pending[key])
	_pending = {}
	Settings.apply_video()
	_refresh_video()
	if display_changed:
		_show_confirm()
	else:
		Settings.save_settings()


func _show_confirm() -> void:
	_confirm_left = CONFIRM_SECONDS
	if is_instance_valid(_confirm_layer):
		return
	# Au-dessus de tout, menu pause compris.
	_confirm_layer = CanvasLayer.new()
	_confirm_layer.layer = 100
	add_child(_confirm_layer)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.015, 0.03, 0.75)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.theme = UiTheme.get_theme()
	_confirm_layer.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var panel := UiTheme.panel()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size.x = 480
	panel.add_child(box)
	box.add_child(UiTheme.title("GARDER CET AFFICHAGE ?", 26, Color.WHITE))
	_confirm_label = UiTheme.label("", 16, UiTheme.MUTED)
	_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_confirm_label)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)
	var cancel := UiTheme.button("ANNULER", false, UiTheme.RED, 46)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(func() -> void:
		Sfx.ui("ui_close", -4.0)
		_revert_display())
	buttons.add_child(cancel)
	var keep := UiTheme.button("GARDER", true, UiTheme.CYAN, 46)
	keep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	keep.pressed.connect(func() -> void:
		Sfx.ui("ui_click")
		_keep_display())
	buttons.add_child(keep)
	_update_confirm_text()
	keep.grab_focus.call_deferred()


func _update_confirm_text() -> void:
	_confirm_label.text = "Retour à l'affichage précédent dans %d s si tu ne confirmes pas." % ceili(_confirm_left)


func _process(delta: float) -> void:
	if _confirm_previous.is_empty():
		return
	_confirm_left -= delta
	if _confirm_left <= 0.0:
		_revert_display()
	elif is_instance_valid(_confirm_label):
		_update_confirm_text()


func _keep_display() -> void:
	_confirm_previous = {}
	_close_confirm()
	Settings.save_settings()


func _revert_display() -> void:
	if _confirm_previous.is_empty():
		return
	Settings.window_mode = _confirm_previous.window_mode
	Settings.resolution = _confirm_previous.resolution
	_confirm_previous = {}
	Settings.apply_video()
	Settings.save_settings()
	_close_confirm()
	if is_inside_tree():
		_refresh_video()


func _close_confirm() -> void:
	if is_instance_valid(_confirm_layer):
		_confirm_layer.queue_free()
	_confirm_layer = null


# ---------------------------------------------------------------- Son

func _build_audio_tab() -> ScrollContainer:
	var parts := _tab_page()
	var list: VBoxContainer = parts[1]
	list.add_child(_slider_row("master_volume", "Volume général", 0.0, 1.0, 0.01, _percent))
	list.add_child(_slider_row("sfx_volume", "Effets (tirs, impacts, capacités)", 0.0, 1.0, 0.01, _percent))
	list.add_child(_slider_row("ui_volume", "Interface (menus)", 0.0, 1.0, 0.01, _percent))
	_reset_button(list, "SON PAR DÉFAUT", func() -> void:
		Settings.reset_audio()
		refresh())
	return parts[0]


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


# ---------------------------------------------------------------- Commandes (souris et touches)

func _build_controls_tab() -> ScrollContainer:
	var parts := _tab_page()
	var list: VBoxContainer = parts[1]
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
	_reset_button(list, "SOURIS PAR DÉFAUT", func() -> void:
		Settings.reset_mouse()
		refresh())

	list.add_child(UiTheme.spacer(Vector2(0, 8)))
	list.add_child(UiTheme.label("TOUCHES", 15, UiTheme.CYAN, true))
	_keys_status = UiTheme.label("", 14, UiTheme.MUTED)
	_keys_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(_keys_status)
	for entry in Inputs.REBINDABLE:
		list.add_child(_key_row(entry[0], entry[1]))
	_reset_button(list, "TOUCHES PAR DÉFAUT", func() -> void:
		_stop_listening()
		Inputs.reset_bindings()
		_keys_status.text = "Touches par défaut rétablies.")
	return parts[0]


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


## Passe avant tout le reste (le menu pause ne se ferme pas sur Échap) :
## Échap annule la confirmation d'affichage ou la saisie d'une touche.
func _input(event: InputEvent) -> void:
	if not _confirm_previous.is_empty():
		if event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			Sfx.ui("ui_close", -4.0)
			_revert_display()
		return
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
