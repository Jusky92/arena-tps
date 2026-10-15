extends CanvasLayer
## Menu pause (touche Échap) — pour le joueur local uniquement.
##
## La partie NE s'arrête PAS : les bots (et plus tard les autres joueurs) continuent
## à jouer, et notre personnage reste dans l'arène, immobile et vulnérable.
## Le menu se contente de couper les commandes du joueur (géré par la scène de jeu).
##
## Pages :
##   - principale : Reprendre, Changer de spécialiste, Changer de classe, Paramètres,
##     Quitter la partie ;
##   - spécialistes : choix du personnage utilisé à la prochaine apparition ;
##   - classes : choix de l'équipement (armes) utilisé à la prochaine apparition ;
##   - paramètres : son, souris et touches (SettingsPanel, comme la page PARAMÈTRES du menu) ;
##   - confirmation avant de quitter.
## Échap : revient à la page principale, puis ferme le menu.

signal resumed
signal quit_requested
signal class_selected(class_data: ClassData)
## Classe (équipement) choisie : indice dans GameState.loadouts.
signal loadout_selected(index: int)

const PANEL_BG := Color(0.03, 0.04, 0.075, 0.94)
const LEFT_WIDTH := 400.0
const PREVIEW_SIZE := Vector2i(220, 250)

var _root: Control
var _content: PanelContainer
var _pages := {}                 # nom -> Control
var _menu_buttons := {}          # nom de page -> bouton du menu de gauche
var _info_label: Label
var _class_cards := []           # [ClassData, bouton, style normal, carte]
var _current_class: ClassData
var _pending_class: ClassData
var _pending_loadout := false
var _loadouts_box: GridContainer
var _settings_panel: SettingsPanel
var _resume_button: Button
var _open := false


func _ready() -> void:
	layer = 20
	_build()
	_root.visible = false


func is_open() -> bool:
	return _open


## Ouvre le menu. current : spécialiste joué ; pending : spécialiste prévu pour la
## prochaine apparition (ou null) ; pending_loadout : la classe change à la prochaine apparition.
func open(current: ClassData, pending: ClassData, pending_loadout := false) -> void:
	_current_class = current
	_pending_class = pending
	_pending_loadout = pending_loadout
	_refresh_loadouts()
	_open = true
	_root.visible = true
	_show_page("")
	_refresh_class_cards()
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.12)
	_resume_button.grab_focus()


func close() -> void:
	if not _open:
		return
	_open = false
	Settings.save_settings()
	_root.visible = false


## Échap : une page ouverte se ferme d'abord, puis le menu.
func back() -> void:
	if _content.visible:
		Sfx.ui("ui_close", -4.0)
		_show_page("")
		_resume_button.grab_focus()
	else:
		resumed.emit()


## Texte d'information en bas à gauche (serveur, temps restant, score).
func set_info(text: String) -> void:
	_info_label.text = text


# ---------------------------------------------------------------- Construction

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiTheme.get_theme()
	add_child(_root)

	# Assombrit le jeu, qui reste visible (et continue) derrière.
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.03, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	# Colonne de gauche.
	var left := PanelContainer.new()
	left.add_theme_stylebox_override("panel", _left_style())
	left.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left.offset_right = LEFT_WIDTH
	_root.add_child(left)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	left.add_child(col)

	var live := HBoxContainer.new()
	live.add_theme_constant_override("separation", 8)
	live.add_child(UiTheme.dot(UiTheme.RED, 9))
	live.add_child(UiTheme.label("PARTIE EN COURS", 14, UiTheme.RED, true))
	col.add_child(live)
	col.add_child(UiTheme.title("PAUSE", 46, Color.WHITE))
	var warn := UiTheme.label("La partie continue pendant la pause : ton personnage reste dans l'arène et peut être touché.", 15, UiTheme.MUTED)
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(warn)
	col.add_child(UiTheme.neon_line(UiTheme.CYAN, 2))
	col.add_child(UiTheme.spacer(Vector2(0, 6)))

	_resume_button = _menu_button("REPRENDRE", "▶", true)
	_resume_button.pressed.connect(func() -> void: resumed.emit())
	col.add_child(_resume_button)
	_menu_buttons["classes"] = _menu_button("CHANGER DE SPÉCIALISTE", "◆")
	col.add_child(_menu_buttons["classes"])
	_menu_buttons["loadouts"] = _menu_button("CHANGER DE CLASSE", "▣")
	col.add_child(_menu_buttons["loadouts"])
	_menu_buttons["settings"] = _menu_button("PARAMÈTRES", "⚙")
	col.add_child(_menu_buttons["settings"])
	_menu_buttons["quit"] = _menu_button("QUITTER LA PARTIE", "⏻", false, UiTheme.RED)
	col.add_child(_menu_buttons["quit"])
	for page in _menu_buttons:
		_menu_buttons[page].pressed.connect(_toggle_page.bind(page))

	col.add_child(UiTheme.spacer(Vector2.ZERO, false, true))
	var info_panel := UiTheme.panel(Color(1, 1, 1, 0.03), Color(UiTheme.CYAN, 0.12))
	_info_label = UiTheme.label("", 15, UiTheme.TEXT)
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_panel.add_child(_info_label)
	col.add_child(info_panel)
	col.add_child(UiTheme.label("Échap : retour", 13, Color(UiTheme.MUTED, 0.8)))

	# Zone de droite : contenu de la page choisie.
	_content = PanelContainer.new()
	_content.add_theme_stylebox_override("panel", UiTheme.box(PANEL_BG, Color(UiTheme.CYAN, 0.3), 1, 8, 28, 24))
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.offset_left = LEFT_WIDTH + 36
	_content.offset_right = -36
	_content.offset_top = 48
	_content.offset_bottom = -48
	_root.add_child(_content)
	_pages["classes"] = _build_classes_page()
	_pages["loadouts"] = _build_loadouts_page()
	_pages["settings"] = _build_settings_page()
	_pages["quit"] = _build_quit_page()
	for page in _pages.values():
		_content.add_child(page)


func _left_style() -> StyleBoxFlat:
	var s := UiTheme.box(PANEL_BG, Color(0, 0, 0, 0), 0, 0, 36, 40)
	s.border_color = Color(UiTheme.CYAN, 0.35)
	s.border_width_right = 2
	return s


## Bouton de la colonne de gauche (icône + texte, aligné à gauche).
func _menu_button(text: String, icon: String, primary := false, accent := UiTheme.CYAN) -> Button:
	var b := UiTheme.button("%s   %s" % [icon, text], primary, accent, 54)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if not primary:
		b.add_theme_font_override("font", UiTheme.title_font())
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_stylebox_override("hover", UiTheme.box(Color(accent, 0.14), accent, 1, 4, 16, 8))
		b.add_theme_color_override("font_hover_color", accent.lightened(0.2))
		if accent != UiTheme.CYAN:
			b.add_theme_color_override("font_color", accent.lightened(0.15))
	return b


func _toggle_page(page: String) -> void:
	if _pages[page].visible and _content.visible:
		Sfx.ui("ui_close", -4.0)
		_show_page("")
	else:
		Sfx.ui("ui_open", -4.0)
		_show_page(page)


func _show_page(page: String) -> void:
	_content.visible = not page.is_empty()
	for page_name in _pages:
		_pages[page_name].visible = page_name == page
	for page_name in _menu_buttons:
		var b: Button = _menu_buttons[page_name]
		var accent := UiTheme.RED if page_name == "quit" else UiTheme.CYAN
		if page_name == page:
			b.add_theme_stylebox_override("normal", UiTheme.box(Color(accent, 0.2), accent, 1, 4, 16, 8))
		else:
			b.remove_theme_stylebox_override("normal")
	if page == "settings":
		_settings_panel.refresh()


func _page_header(title: String, subtitle: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.add_child(UiTheme.title(title, 28, Color.WHITE))
	var sub := UiTheme.label(subtitle, 16, UiTheme.MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(sub)
	box.add_child(UiTheme.neon_line(UiTheme.CYAN, 1))
	return box


# ---------------------------------------------------------------- Page : classes

func _build_classes_page() -> Control:
	var page := _page_header("CHANGER DE SPÉCIALISTE",
		"Le nouveau spécialiste sera utilisé à ta prochaine apparition. Ton score dans la partie est conservé.")
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 14)
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(cards)
	for i in GameState.CLASSES.size():
		cards.add_child(_class_card(GameState.CLASSES[i]))
	return page


func _class_card(data: ClassData) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := UiTheme.box(Color(0.05, 0.065, 0.1, 0.95), Color(data.color, 0.35), 1, 6, 12, 12)
	card.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)

	# Personnage 3D animé (rendu seulement quand la page est visible).
	var holder := CenterContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var preview := CharacterPreview.new()
	preview.show_pose_label = false
	preview.pose_names = ["Repos", "Visée", "Marche"]
	holder.add_child(preview)
	preview.setup(data.character_design, data.weapon.model, PREVIEW_SIZE, 3.7, 1.0)
	box.add_child(holder)

	box.add_child(UiTheme.title(data.display_name.to_upper(), 20, data.color.lightened(0.35)))
	box.add_child(_info_row("Points de vie", str(data.max_health)))
	box.add_child(_info_row("Vitesse", "%.1f m/s" % data.sprint_speed))
	box.add_child(_info_row("Capacité", data.ability_name))
	box.add_child(UiTheme.spacer(Vector2.ZERO, false, true))

	var button := UiTheme.button("CHOISIR", false, data.color, 42)
	button.add_theme_font_override("font", UiTheme.title_font())
	button.add_theme_font_size_override("font_size", 13)
	button.pressed.connect(_choose_class.bind(data))
	box.add_child(button)
	_class_cards.append([data, button, style, card])
	return card


func _info_row(title: String, value: String) -> Control:
	var row := HBoxContainer.new()
	var t := UiTheme.label(title, 14, UiTheme.MUTED)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(t)
	row.add_child(UiTheme.label(value, 14, UiTheme.TEXT, true))
	return row


func _choose_class(data: ClassData) -> void:
	Sfx.ui("ui_click")
	_pending_class = null if data == _current_class else data
	_refresh_class_cards()
	class_selected.emit(data)


func _refresh_class_cards() -> void:
	for entry in _class_cards:
		var data: ClassData = entry[0]
		var button: Button = entry[1]
		var card: PanelContainer = entry[3]
		var is_current := data == _current_class and _pending_class == null
		var is_next := data == _pending_class
		var was_current := data == _current_class and _pending_class != null
		if is_next:
			button.text = "✓ PROCHAINE APPARITION"
		elif is_current:
			button.text = "✓ CLASSE ACTUELLE"
		elif was_current:
			button.text = "GARDER CETTE CLASSE"
		else:
			button.text = "CHOISIR"
		button.disabled = is_current
		var highlight := is_next or is_current
		card.add_theme_stylebox_override("panel", UiTheme.box(
			Color(data.color, 0.12) if highlight else Color(0.05, 0.065, 0.1, 0.95),
			data.color if highlight else Color(data.color, 0.35), 2 if highlight else 1, 6, 12, 12))


# ---------------------------------------------------------------- Page : classes (équipement)

func _build_loadouts_page() -> Control:
	var page := _page_header("CHANGER DE CLASSE",
		"Arme principale, arme secondaire et 2 grenades. La classe choisie sera utilisée à ta prochaine apparition. Tes classes se créent dans l'accueil.")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	_loadouts_box = GridContainer.new()
	_loadouts_box.columns = 2
	_loadouts_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_loadouts_box.add_theme_constant_override("h_separation", 12)
	_loadouts_box.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_loadouts_box)
	return page


## Une carte par classe du joueur ; celle choisie est marquée.
func _refresh_loadouts() -> void:
	if _loadouts_box == null:
		return
	for c in _loadouts_box.get_children():
		c.queue_free()
	for i in GameState.loadouts.size():
		var l: Dictionary = GameState.loadouts[i]
		var selected := i == GameState.selected_loadout
		var primary := WeaponCatalog.find(l.primary)
		var secondary := WeaponCatalog.find(l.secondary)
		var b := UiTheme.button("", selected, UiTheme.CYAN, 74)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.text = "%s%s\n%s  ·  %s  ·  2 grenades" % ["✓ " if selected else "", l.name.to_upper(),
			primary.display_name if primary else "?", secondary.display_name if secondary else "?"]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func() -> void:
			Sfx.ui("ui_click")
			loadout_selected.emit(i)
			_refresh_loadouts())
		_loadouts_box.add_child(b)


# ---------------------------------------------------------------- Page : paramètres

func _build_settings_page() -> Control:
	var page := _page_header("PARAMÈTRES", "Les réglages sont enregistrés sur ton ordinateur et s'appliquent tout de suite.")
	_settings_panel = SettingsPanel.new()
	page.add_child(_settings_panel)
	return page


# ---------------------------------------------------------------- Page : quitter

func _build_quit_page() -> Control:
	var page := _page_header("QUITTER LA PARTIE ?",
		"Tu reviendras au menu principal. Le match en cours ne sera pas comptabilisé dans tes statistiques.")
	page.add_child(UiTheme.spacer(Vector2(0, 8)))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	var quit := UiTheme.button("QUITTER", true, UiTheme.RED, 48)
	quit.custom_minimum_size.x = 200
	quit.pressed.connect(func() -> void:
		Sfx.ui("ui_close")
		quit_requested.emit())
	buttons.add_child(quit)
	var cancel := UiTheme.button("ANNULER", false, UiTheme.CYAN, 48)
	cancel.custom_minimum_size.x = 200
	cancel.pressed.connect(func() -> void:
		Sfx.ui("ui_close", -4.0)
		_show_page("")
		_resume_button.grab_focus())
	buttons.add_child(cancel)
	page.add_child(buttons)
	return page
