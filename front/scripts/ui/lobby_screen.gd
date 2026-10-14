extends Control
## Salon du serveur dédié (scenes/lobby.tscn), entre deux parties.
##
## Deux rôles :
##   CHEF   — le premier joueur connecté : il règle le nombre de bots et la durée,
##            puis lance la partie pour tout le monde. S'il part, le suivant prend sa place.
##   JOUEUR — il voit les réglages et attend le lancement ; il peut changer de classe.
##
## Tout passe par l'autoload Net (scripts/net/net.gd) ; le serveur fait foi.

const MAIN_MENU := "res://scenes/main_menu.tscn"
const GAME := "res://scenes/game.tscn"
const CLASS_SELECT := "res://scenes/class_select.tscn"
const STATUS_TEXT := {
	"idle": "En attente du lancement.",
	"reserved": "Réservé pour un groupe.",
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
var _server_label: Label


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

	var bots_row := HBoxContainer.new()
	var bots_title := UiTheme.label("Bots pour compléter", 17, UiTheme.TEXT)
	bots_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bots_row.add_child(bots_title)
	_bots_label = UiTheme.label("", 17, UiTheme.CYAN, true)
	bots_row.add_child(_bots_label)
	box.add_child(bots_row)
	_bots_slider = HSlider.new()
	_bots_slider.min_value = 0
	_bots_slider.max_value = 6
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
	_show_settings(int(_bots_slider.value), _duration_slider.value)
	Net.request_settings(int(_bots_slider.value), _duration_slider.value)


func _show_settings(bots: int, duration: float) -> void:
	_bots_label.text = "%d" % bots
	_duration_label.text = "%d:%02d" % [int(duration) / 60, int(duration) % 60]


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
	# Réglages tenus par le serveur ; le chef garde la main sur ses curseurs.
	var bots: int = Net.settings.get("bots", 2)
	var duration: float = Net.settings.get("duration", 180.0)
	_bots_slider.editable = leader
	_duration_slider.editable = leader
	if not leader:
		_bots_slider.set_value_no_signal(bots)
		_duration_slider.set_value_no_signal(duration)
		_show_settings(bots, duration)
	else:
		_show_settings(int(_bots_slider.value), _duration_slider.value)
	_server_label.text = "Connecté. %s" % STATUS_TEXT.get(Net.server_status, Net.server_status)
	var can_start := leader and Net.server_status == "idle"
	_start_button.disabled = not can_start
	_start_button.focus_mode = Control.FOCUS_ALL if can_start else Control.FOCUS_NONE
	if leader:
		_start_button.text = "LANCER LA PARTIE  (Entrée)"
		_status.text = "%d joueur(s) dans le salon. Tu es le chef : lance dès que tout le monde est là." % count
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
