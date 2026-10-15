extends Control
## Salon du serveur dédié (scenes/lobby.tscn), entre deux parties.
##
## Deux rôles :
##   CHEF   — le premier joueur connecté : il règle le nombre de bots et la durée,
##            puis lance la partie pour tout le monde. S'il part, le suivant prend sa place.
##   JOUEUR — il voit les réglages et attend le lancement ; il peut changer de classe.
## Sur un serveur de la Server List (partie lancée par un groupe), le chef est celui
## du groupe : il arrive avec ses derniers réglages (GameState.online_settings), peut
## les changer ici, puis lance la partie quand tout le monde est prêt.
##
## Tout passe par l'autoload Net (scripts/net/net.gd) ; le serveur fait foi.

const MAIN_MENU := "res://scenes/main_menu.tscn"
const GAME := "res://scenes/game.tscn"
const CLASS_SELECT := "res://scenes/class_select.tscn"
const STATUS_TEXT := {
	"idle": "En attente du lancement.",
	"reserved": "Réservé pour ton groupe : le chef règle et lance la partie quand tout le monde est prêt.",
	"in_progress": "Partie en cours.",
	"ending": "Fin de partie, retour au salon dans quelques secondes.",
}

var _players_box: VBoxContainer
var _status: Label
var _start_button: Button
var _bots_label: Label
var _bots_slider: HSlider
var _duration_label: Label
var _duration_slider: HSlider
var _map_picker: OptionButton
var _map_label: Label
var _server_label: Label
## Les curseurs étaient-ils à nous au dernier rafraîchissement ? Quand ils le
## deviennent (réservation reçue), ils repartent des réglages du serveur.
var _was_editable := false


func _ready() -> void:
	if Net.in_match:
		# Une nouvelle partie a commencé pendant qu'on regardait l'écran de fin.
		_on_match_starting.call_deferred()
		return
	theme = UiTheme.get_theme()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	add_child(UiTheme.background())
	_build()
	Net.lobby_changed.connect(_refresh)
	Net.match_starting.connect(_on_match_starting)
	Net.connection_failed.connect(_on_lost)
	Net.disconnected.connect(_on_lost)
	_refresh()


func _exit_tree() -> void:
	for signal_name in ["lobby_changed", "match_starting", "connection_failed", "disconnected"]:
		for connection in Net.get_signal_connection_list(signal_name):
			if connection.callable.get_object() == self:
				Net.disconnect(signal_name, connection.callable)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_leave()
	elif event.is_action_pressed("ui_accept") and Net.is_leader():
		Sfx.ui("ui_click")
		Net.request_start()


# ---------------------------------------------------------------- Construction

func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 18)
	margin.add_child(root)

	# En-tête.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	var title := UiTheme.title("SALON", 40, Color.WHITE)
	header.add_child(title)
	var kana := UiTheme.label("待合室", 20, UiTheme.CYAN)
	kana.add_theme_font_override("font", JapaneseFont.font())
	kana.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(kana)
	header.add_child(UiTheme.spacer(Vector2.ZERO, true))
	var leave := UiTheme.button("QUITTER LE SALON", false, UiTheme.RED, 44)
	leave.pressed.connect(_leave)
	header.add_child(leave)
	root.add_child(header)
	root.add_child(UiTheme.neon_line(UiTheme.CYAN, 2))

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 22)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)

	# Colonne gauche : joueurs connectés.
	var left := UiTheme.panel()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	var left_box := VBoxContainer.new()
	left_box.add_theme_constant_override("separation", 10)
	left.add_child(left_box)
	left_box.add_child(UiTheme.label("JOUEURS CONNECTÉS", 15, UiTheme.MUTED, true))
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 6)
	left_box.add_child(_players_box)
	left_box.add_child(UiTheme.spacer(Vector2.ZERO, false, true))
	var change := UiTheme.button("CHANGER DE CLASSE")
	change.pressed.connect(func() -> void: get_tree().change_scene_to_file(CLASS_SELECT))
	left_box.add_child(change)

	# Colonne droite : connexion et réglages (zone qui défile), puis le bouton de
	# lancement, toujours visible en bas même sur un petit écran.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 14)
	right.custom_minimum_size.x = 520
	columns.add_child(right)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	var scrolled := VBoxContainer.new()
	scrolled.add_theme_constant_override("separation", 14)
	scrolled.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(scrolled)
	scrolled.add_child(_build_connection_panel())
	scrolled.add_child(_build_settings_panel())

	_status = UiTheme.label("", 17, UiTheme.MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_status)

	_start_button = UiTheme.button("LANCER LA PARTIE  (Entrée)", true, UiTheme.CYAN, 58)
	_start_button.add_theme_font_size_override("font_size", 20)
	_start_button.pressed.connect(func() -> void:
		Sfx.ui("ui_click")
		Net.request_start())
	right.add_child(_start_button)


## Serveur rejoint et son état.
func _build_connection_panel() -> Control:
	var panel := UiTheme.panel()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.add_child(UiTheme.label("SERVEUR", 15, UiTheme.MUTED, true))
	_server_label = UiTheme.label("", 17, UiTheme.GREEN)
	_server_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_server_label)
	return panel


## Réglages de la partie : modifiables par le chef, affichés pour les autres.
func _build_settings_panel() -> Control:
	var panel := UiTheme.panel()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(UiTheme.label("RÉGLAGES DE LA PARTIE", 15, UiTheme.MUTED, true))

	var map_row := HBoxContainer.new()
	map_row.add_theme_constant_override("separation", 10)
	var map_title := UiTheme.label("Map", 17, UiTheme.TEXT)
	map_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_row.add_child(map_title)
	_map_picker = OptionButton.new()
	_map_picker.custom_minimum_size.x = 200
	for i in MapCatalog.MAPS.size():
		_map_picker.add_item(MapCatalog.MAPS[i].name, i)
	_map_picker.select(_map_index(Net.settings.get("map", MapCatalog.DEFAULT_ID)))
	_map_picker.item_selected.connect(func(_i: int) -> void: _push_settings())
	map_row.add_child(_map_picker)
	box.add_child(map_row)
	_map_label = UiTheme.label("", 14, UiTheme.MUTED)
	box.add_child(_map_label)

	var bots_row := HBoxContainer.new()
	var bots_title := UiTheme.label("Bots pour compléter", 17, UiTheme.TEXT)
	bots_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bots_row.add_child(bots_title)
	_bots_label = UiTheme.label("", 17, UiTheme.CYAN, true)
	bots_row.add_child(_bots_label)
	box.add_child(bots_row)
	_bots_slider = HSlider.new()
	_bots_slider.min_value = 0
	_bots_slider.max_value = Net.max_players - 1
	_bots_slider.step = 1
	_bots_slider.value = Net.settings.get("bots", 2)
	_bots_slider.custom_minimum_size = Vector2(0, 24)
	_bots_slider.value_changed.connect(func(_v: float) -> void: _push_settings())
	box.add_child(_bots_slider)

	var duration_row := HBoxContainer.new()
	var duration_title := UiTheme.label("Durée du match", 17, UiTheme.TEXT)
	duration_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	duration_row.add_child(duration_title)
	_duration_label = UiTheme.label("", 17, UiTheme.CYAN, true)
	duration_row.add_child(_duration_label)
	box.add_child(duration_row)
	_duration_slider = HSlider.new()
	_duration_slider.min_value = 60
	_duration_slider.max_value = 600
	_duration_slider.step = 30
	_duration_slider.value = Net.settings.get("duration", 180.0)
	_duration_slider.custom_minimum_size = Vector2(0, 24)
	_duration_slider.value_changed.connect(func(_v: float) -> void: _push_settings())
	box.add_child(_duration_slider)
	return panel


func _push_settings() -> void:
	var map_id := _picked_map()
	_show_settings(int(_bots_slider.value), _duration_slider.value, map_id)
	Net.request_settings(int(_bots_slider.value), _duration_slider.value, map_id)
	if not Net.lan_lobby:
		# Gardés pour le prochain lancement en ligne du groupe.
		GameState.online_settings.bots = int(_bots_slider.value)
		GameState.online_settings.duration = int(_duration_slider.value)


func _show_settings(bots: int, duration: float, map_id: String) -> void:
	_bots_label.text = "%d" % bots
	_duration_label.text = "%d:%02d" % [int(duration) / 60, int(duration) % 60]
	_map_label.text = MapCatalog.find(map_id).subtitle


func _map_index(map_id: String) -> int:
	for i in MapCatalog.MAPS.size():
		if MapCatalog.MAPS[i].id == map_id:
			return i
	return 0


func _picked_map() -> String:
	return MapCatalog.MAPS[maxi(_map_picker.selected, 0)].id


# ---------------------------------------------------------------- Mise à jour

func _refresh() -> void:
	if not is_instance_valid(_players_box):
		return
	for child in _players_box.get_children():
		child.queue_free()
	var ids := Net.players.keys()
	ids.sort()
	for id in ids:
		_players_box.add_child(_player_row(id))
	var count: int = Net.human_count()
	var leader := Net.is_leader()
	var editable := Net.can_edit_settings()
	# Réglages tenus par le serveur ; le chef garde la main sur ses curseurs.
	var bots: int = Net.settings.get("bots", 2)
	var duration: float = Net.settings.get("duration", 180.0)
	var map_id: String = Net.settings.get("map", MapCatalog.DEFAULT_ID)
	_bots_slider.editable = editable
	_duration_slider.editable = editable
	_map_picker.disabled = not editable
	if not editable or not _was_editable:
		_bots_slider.set_value_no_signal(bots)
		_duration_slider.set_value_no_signal(duration)
		_map_picker.select(_map_index(map_id))
		_show_settings(bots, duration, map_id)
	else:
		_show_settings(int(_bots_slider.value), _duration_slider.value, _picked_map())
	_was_editable = editable
	_server_label.text = "Connecté. %s" % STATUS_TEXT.get(Net.server_status, Net.server_status)
	var can_start := editable
	_start_button.disabled = not can_start
	_start_button.focus_mode = Control.FOCUS_ALL if can_start else Control.FOCUS_NONE
	if not Net.lan_lobby and Net.leader_id == 0:
		_start_button.text = "EN ATTENTE DU CHEF…"
		_status.text = "%d joueur(s) connecté(s). Le chef du groupe n'est pas encore là." % count
	elif leader and not can_start and not Net.lan_lobby:
		# Arrivé avant le battement de cœur qui annonce la réservation au serveur.
		_start_button.text = "RÉSERVATION EN COURS…"
		_status.text = "%d joueur(s) connecté(s). Le serveur confirme la réservation de ton groupe…" % count
	elif leader:
		_start_button.text = "LANCER LA PARTIE  (Entrée)"
		_status.text = "%d joueur(s) dans le salon. Tu es le chef : règle la partie et lance dès que tout le monde est là." % count
		if not Net.lan_lobby:
			_status.text += " Les places libres s'ouvrent aux autres joueurs pendant la partie."
	else:
		_start_button.text = "EN ATTENTE DU CHEF…"
		_status.text = "%d joueur(s) dans le salon. %s lancera la partie." % [count, Net.player_name_of(Net.leader_id)]


func _player_row(id: int) -> Control:
	var info: Dictionary = Net.players[id]
	var cls: ClassData = load(info.get("class_id", GameState.CLASSES[0].resource_path))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var is_bot: bool = Net.is_bot(id)
	row.add_child(UiTheme.dot(UiTheme.MUTED if is_bot else UiTheme.GREEN, 10))
	var name_label := UiTheme.label(info.get("name", "Joueur"), 19, Color.WHITE, true)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	if id == Net.my_id():
		row.add_child(UiTheme.label("toi", 15, UiTheme.CYAN))
	if id == Net.leader_id:
		row.add_child(UiTheme.label("chef", 15, UiTheme.YELLOW))
	row.add_child(UiTheme.label(cls.display_name, 17, cls.color.lightened(0.3), true))
	return row


func _on_match_starting() -> void:
	GameState.mode = "deathmatch"
	get_tree().change_scene_to_file(GAME)


func _on_lost(reason: String) -> void:
	_status.text = reason
	_status.add_theme_color_override("font_color", UiTheme.RED)
	await get_tree().create_timer(2.0).timeout
	get_tree().change_scene_to_file(MAIN_MENU)


func _leave() -> void:
	Sfx.ui("ui_close")
	Net.leave()
	get_tree().change_scene_to_file(MAIN_MENU)
