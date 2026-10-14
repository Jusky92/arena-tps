extends Control
## Menu principal (après connexion) : comme si le multijoueur était en ligne.
##   JOUER         personnage, groupe, créer / rejoindre un serveur, entraînement
##   CLASSES       ouvre l'écran de choix de classe
##   STATISTIQUES  stats du joueur + classement mondial ou entre amis
##   AMIS          panneau de droite : statut des amis, invitation dans le groupe
## Toutes les données viennent de l'autoload Backend (simulé pour l'instant).

const GAME := "res://scenes/game.tscn"
const LOBBY := "res://scenes/lobby.tscn"
const CLASS_SELECT := "res://scenes/class_select.tscn"
const AUTH := "res://scenes/auth.tscn"
## Dernière adresse de connexion, gardée d'une partie à l'autre.
const ADDRESS_PATH := "user://reseau.cfg"

var _page_holder: MarginContainer
var _nav_buttons := {}
var _profile_box: HBoxContainer
var _friends_box: VBoxContainer
var _party_box: VBoxContainer
var _overlay: Control
var _address_field: LineEdit
var _online_error: Label


func _ready() -> void:
	theme = UiTheme.get_theme()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if not Backend.is_logged_in():
		await Backend.login("", "")   # lancement direct de cette scène : session invitée
	add_child(UiTheme.background())

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	root.add_child(_build_top_bar())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root.add_child(body)
	_page_holder = MarginContainer.new()
	_page_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		_page_holder.add_theme_constant_override("margin_" + side, 24 if side != "top" else 18)
	body.add_child(_page_holder)
	body.add_child(_build_social_panel())
	root.add_child(_build_bottom_bar())

	Backend.party_changed.connect(_refresh_party)
	Net.joined.connect(_on_net_joined)
	Net.connection_failed.connect(_on_net_failed)
	_refresh_profile()
	_refresh_friends()
	_show_page("play")


# =========================================================================== barres

func _build_top_bar() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiTheme.box(Color(0.02, 0.03, 0.05, 0.9), Color(0, 0, 0, 0), 0, 0, 24, 10))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	bar.add_child(row)

	var logo := HBoxContainer.new()
	logo.add_theme_constant_override("separation", 6)
	logo.add_child(UiTheme.title("ARENA", 24, Color.WHITE))
	var kana := UiTheme.label("ネオ江戸", 16, UiTheme.CYAN)
	kana.add_theme_font_override("font", JapaneseFont.font())
	logo.add_child(kana)
	logo.add_child(UiTheme.title("TPS", 24, UiTheme.CYAN))
	row.add_child(logo)
	row.add_child(UiTheme.spacer(Vector2(16, 0)))

	for page in [["JOUER", "play"], ["CLASSES", "classes"], ["STATISTIQUES", "stats"]]:
		var b := Button.new()
		b.text = page[0]
		b.flat = true
		b.add_theme_font_override("font", UiTheme.title_font())
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_color_override("font_color", UiTheme.MUTED)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.pressed.connect(_show_page.bind(page[1]))
		row.add_child(b)
		_nav_buttons[page[1]] = b

	row.add_child(UiTheme.spacer(Vector2.ZERO, true))
	_profile_box = HBoxContainer.new()
	_profile_box.add_theme_constant_override("separation", 12)
	row.add_child(_profile_box)

	var logout := Button.new()
	logout.text = "Déconnexion"
	logout.tooltip_text = "Se déconnecter"
	logout.pressed.connect(func() -> void:
		Backend.logout()
		get_tree().change_scene_to_file(AUTH))
	row.add_child(logout)
	var quit_button := Button.new()
	quit_button.text = "Quitter"
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	row.add_child(quit_button)
	return bar


func _build_bottom_bar() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiTheme.box(Color(0.02, 0.03, 0.05, 0.85), Color(0, 0, 0, 0), 0, 0, 24, 6))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)
	row.add_child(UiTheme.dot(UiTheme.GREEN, 8))
	row.add_child(UiTheme.label("Services : en ligne (simulés)", 15, UiTheme.MUTED))
	row.add_child(UiTheme.label("·  Région EU-Ouest  ·  Build %s" % Backend.BUILD_VERSION, 15, UiTheme.MUTED))
	row.add_child(UiTheme.spacer(Vector2.ZERO, true))
	row.add_child(UiTheme.label("CFA INSTA · Architecture SI · M2", 15, Color(UiTheme.MAGENTA, 0.8), true))
	return bar


func _refresh_profile() -> void:
	var p: Dictionary = await Backend.get_profile()
	for c in _profile_box.get_children():
		c.queue_free()
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", UiTheme.box(Color(UiTheme.MAGENTA, 0.85), Color(0, 0, 0, 0), 0, 4, 8, 2))
	var lvl := UiTheme.title(str(p.level), 15, Color(0.03, 0.03, 0.06))
	badge.add_child(lvl)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_profile_box.add_child(badge)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.add_child(UiTheme.label(p.username, 19, Color.WHITE, true))
	var xp := ProgressBar.new()
	xp.custom_minimum_size = Vector2(150, 5)
	xp.show_percentage = false
	xp.max_value = p.xp_next
	xp.value = p.xp
	info.add_child(xp)
	_profile_box.add_child(info)


# =========================================================================== pages

func _show_page(page: String) -> void:
	if page == "classes":
		get_tree().change_scene_to_file(CLASS_SELECT)
		return
	for key in _nav_buttons:
		var active: bool = key == page
		_nav_buttons[key].add_theme_color_override("font_color", UiTheme.CYAN if active else UiTheme.MUTED)
	for c in _page_holder.get_children():
		c.queue_free()
	match page:
		"play":
			_page_holder.add_child(_build_play_page())
		"stats":
			_page_holder.add_child(_build_stats_page())
		"servers":
			_page_holder.add_child(_build_server_page())


# --------------------------------------------------------------------------- JOUER

func _build_play_page() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)

	# Personnage choisi.
	var hero := VBoxContainer.new()
	hero.add_theme_constant_override("separation", 6)
	var cls: ClassData = GameState.selected_class
	hero.add_child(UiTheme.label("TA CLASSE", 14, UiTheme.MUTED, true))
	hero.add_child(UiTheme.title(cls.display_name.to_upper(), 34, cls.color.lightened(0.2)))
	var preview := CharacterPreview.new()
	preview.pose_names = ["Repos", "Visée", "Marche", "Accroupi"]
	preview.show_pose_label = false
	hero.add_child(preview)
	preview.setup(cls.character_design, cls.weapon.model, Vector2i(340, 400), 4.2, 1.0)
	var change := UiTheme.button("CHANGER DE CLASSE")
	change.pressed.connect(func() -> void: get_tree().change_scene_to_file(CLASS_SELECT))
	hero.add_child(change)
	row.add_child(hero)

	# Colonne de droite : mode, groupe, boutons.
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 14)
	row.add_child(col)

	var mode := UiTheme.panel()
	var mode_box := VBoxContainer.new()
	mode.add_child(mode_box)
	mode_box.add_child(UiTheme.label("MODE DE JEU", 14, UiTheme.MUTED, true))
	mode_box.add_child(UiTheme.title("MATCH À MORT", 26, Color.WHITE))
	mode_box.add_child(UiTheme.label("Chacun pour soi · 3 minutes · 8 joueurs max · map NEO-EDO", 18, UiTheme.MUTED))
	col.add_child(mode)

	var party := UiTheme.panel()
	_party_box = VBoxContainer.new()
	_party_box.add_theme_constant_override("separation", 8)
	party.add_child(_party_box)
	col.add_child(party)
	_refresh_party()

	col.add_child(UiTheme.spacer(Vector2.ZERO, false, true))

	# --- Jouer en ligne (vrai réseau) ---
	var online := UiTheme.panel(Color(UiTheme.CYAN, 0.07), Color(UiTheme.CYAN, 0.35))
	var online_box := VBoxContainer.new()
	online_box.add_theme_constant_override("separation", 10)
	online.add_child(online_box)
	online_box.add_child(UiTheme.label("JOUER EN LIGNE", 14, UiTheme.CYAN, true))
	var online_help := UiTheme.label("Entre l'adresse affichée par le serveur (ArenaTPS_Server) au démarrage.", 15, UiTheme.MUTED)
	online_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	online_box.add_child(online_help)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 10)
	_address_field = LineEdit.new()
	_address_field.placeholder_text = "adresse du serveur, ex. 192.168.1.20"
	_address_field.text = _saved_address()
	_address_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address_field.text_submitted.connect(func(_t: String) -> void: _join_online())
	join_row.add_child(_address_field)
	var join_button := UiTheme.button("REJOINDRE", true, UiTheme.MAGENTA, 46)
	join_button.custom_minimum_size.x = 170
	join_button.pressed.connect(_join_online)
	join_row.add_child(join_button)
	online_box.add_child(join_row)
	_online_error = UiTheme.label("", 15, UiTheme.RED)
	_online_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	online_box.add_child(_online_error)
	col.add_child(online)

	# --- Hors ligne ---
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	var solo := UiTheme.button("PARTIE SOLO (BOTS)", false, UiTheme.CYAN, 50)
	solo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	solo.tooltip_text = "Match à mort hors ligne contre des bots"
	solo.pressed.connect(_create_server)
	buttons.add_child(solo)
	var training := UiTheme.button("ENTRAÎNEMENT", false, UiTheme.CYAN, 50)
	training.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	training.tooltip_text = "Seul sur la map avec des mannequins d'entraînement"
	training.pressed.connect(_start_training)
	buttons.add_child(training)
	col.add_child(buttons)
	return row


# --------------------------------------------------------------------------- en ligne

## Rejoint le serveur dédié à partir de son adresse (IP ou IP:port).
func _join_online() -> void:
	Sfx.ui("ui_click")
	var address := _address_field.text.strip_edges()
	if address.is_empty():
		_online_error.text = "Entre l'adresse du serveur (celle affichée par ArenaTPS_Server)."
		return
	var port := Net.DEFAULT_PORT
	if address.contains(":"):
		var parts := address.split(":")
		address = parts[0]
		port = int(parts[1])
	if Net.is_connecting():
		return
	var error := Net.join(address, Backend.username(), port)
	if not error.is_empty():
		_show_online_error(error)
		return
	_save_address(_address_field.text.strip_edges())
	# On reste sur cette page tant que le serveur n'a pas répondu : le salon ne
	# s'ouvre que si la connexion a vraiment abouti.
	_online_error.add_theme_color_override("font_color", UiTheme.CYAN)
	while Net.is_connecting() and is_inside_tree():
		_online_error.text = "Connexion à %s:%d…  %d s" % [address, port, ceili(Net.connect_time_left())]
		await get_tree().create_timer(0.2).timeout


## Accepté par le serveur : salon, ou directement la partie si elle a déjà commencé.
func _on_net_joined() -> void:
	if Net.in_match:
		GameState.mode = "deathmatch"
		get_tree().change_scene_to_file(GAME)
	else:
		get_tree().change_scene_to_file(LOBBY)


func _on_net_failed(reason: String) -> void:
	if is_instance_valid(_online_error):
		_show_online_error(reason + "\nJournal détaillé : " + Net.log_file_path())


func _show_online_error(text: String) -> void:
	_online_error.add_theme_color_override("font_color", UiTheme.RED)
	_online_error.text = text


## La dernière adresse utilisée est gardée sur la machine, pour ne pas la retaper.
func _saved_address() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(ADDRESS_PATH) != OK:
		return ""
	return cfg.get_value("reseau", "derniere_adresse", "")


func _save_address(address: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(ADDRESS_PATH)
	cfg.set_value("reseau", "derniere_adresse", address)
	cfg.save(ADDRESS_PATH)


func _refresh_party() -> void:
	if not is_instance_valid(_party_box):
		return
	for c in _party_box.get_children():
		c.queue_free()
	var header := HBoxContainer.new()
	header.add_child(UiTheme.label("GROUPE", 14, UiTheme.MUTED, true))
	header.add_child(UiTheme.spacer(Vector2.ZERO, true))
	header.add_child(UiTheme.label("%d / 8" % Backend.party.size(), 15, UiTheme.CYAN, true))
	_party_box.add_child(header)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for i in 8:
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(120, 38)
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var filled := i < Backend.party.size()
		slot.add_theme_stylebox_override("panel", UiTheme.box(
			Color(UiTheme.CYAN, 0.12) if filled else Color(1, 1, 1, 0.03),
			Color(UiTheme.CYAN, 0.5) if filled else Color(1, 1, 1, 0.08), 1, 4, 10, 4))
		var text := ""
		if filled:
			text = ("★ " if i == 0 else "") + Backend.party[i]
		else:
			text = "Place libre"
		var l := UiTheme.label(text, 16, Color.WHITE if filled else Color(UiTheme.MUTED, 0.6), filled)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot.add_child(l)
		grid.add_child(slot)
	_party_box.add_child(grid)
	_party_box.add_child(UiTheme.label("Invite tes amis avec le bouton + dans la liste de droite. Les places libres seront ouvertes aux autres joueurs une fois la partie lancée.", 14, UiTheme.MUTED))
	(_party_box.get_child(_party_box.get_child_count() - 1) as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


# --------------------------------------------------------------------------- SERVEURS

func _build_server_page() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	var header := HBoxContainer.new()
	var back := Button.new()
	back.text = "← Retour"
	back.pressed.connect(_show_page.bind("play"))
	header.add_child(back)
	header.add_child(UiTheme.spacer(Vector2(12, 0)))
	header.add_child(UiTheme.title("SERVEURS PUBLICS", 24))
	header.add_child(UiTheme.spacer(Vector2.ZERO, true))
	var refresh := Button.new()
	refresh.text = "Actualiser"
	header.add_child(refresh)
	col.add_child(header)
	col.add_child(UiTheme.label("Parties en cours avec des places libres (build %s)." % Backend.BUILD_VERSION, 16, UiTheme.MUTED))

	var table := UiTheme.panel()
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	table.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 6)
	scroll.add_child(rows)
	col.add_child(table)

	var fill := func() -> void:
		for c in rows.get_children():
			c.queue_free()
		rows.add_child(UiTheme.label("Recherche des serveurs…", 17, UiTheme.MUTED))
		var servers: Array = await Backend.get_servers()
		if not is_instance_valid(rows):
			return
		for c in rows.get_children():
			c.queue_free()
		rows.add_child(_table_row(["SERVEUR", "MODE", "MAP", "JOUEURS", "PING", ""], true, [3.0, 1.6, 1.0, 1.0, 0.8, 1.2]))
		for s in servers:
			rows.add_child(_server_row(s))
	refresh.pressed.connect(fill)
	fill.call()
	return col


func _server_row(s: Dictionary) -> Control:
	var row := _table_row([s.name, s.mode, s.map, "%d / %d" % [s.players, s.max_players], "%d ms" % s.ping, ""], false, [3.0, 1.6, 1.0, 1.0, 0.8, 1.2])
	var cells := row.get_child(0) as HBoxContainer
	var ping_label := cells.get_child(4) as Label
	ping_label.add_theme_color_override("font_color", UiTheme.GREEN if s.ping < 30 else (UiTheme.YELLOW if s.ping < 60 else UiTheme.RED))
	var holder := cells.get_child(5)
	var join := UiTheme.button("REJOINDRE", true, UiTheme.MAGENTA, 34)
	join.add_theme_font_size_override("font_size", 13)
	join.pressed.connect(_join_server.bind(s))
	holder.add_child(join)
	return row


## Ligne de tableau : `weights` répartit la largeur des colonnes.
func _table_row(values: Array, header: bool, weights: Array) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.box(
		Color(0, 0, 0, 0) if header else Color(1, 1, 1, 0.035), Color(0, 0, 0, 0), 0, 4, 12, 6))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	for i in values.size():
		var cell: Control
		if i == values.size() - 1 and str(values[i]) == "" and not header:
			cell = HBoxContainer.new()
		else:
			cell = UiTheme.label(str(values[i]), 14 if header else 17, UiTheme.MUTED if header else Color.WHITE, header)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_stretch_ratio = weights[i]
		row.add_child(cell)
	return panel


# --------------------------------------------------------------------------- STATS

func _build_stats_page() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.add_child(UiTheme.title("STATISTIQUES", 24))

	var cards := GridContainer.new()
	cards.columns = 4
	cards.add_theme_constant_override("h_separation", 12)
	cards.add_theme_constant_override("v_separation", 12)
	col.add_child(cards)

	var switch := HBoxContainer.new()
	switch.add_theme_constant_override("separation", 8)
	switch.add_child(UiTheme.label("CLASSEMENT", 14, UiTheme.MUTED, true))
	switch.add_child(UiTheme.spacer(Vector2(10, 0)))
	var world := Button.new()
	world.text = "Mondial"
	var friends := Button.new()
	friends.text = "Entre amis"
	switch.add_child(world)
	switch.add_child(friends)
	col.add_child(switch)

	var table := UiTheme.panel()
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	table.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 4)
	scroll.add_child(rows)
	col.add_child(table)

	var fill_cards := func() -> void:
		var p: Dictionary = await Backend.get_profile()
		if not is_instance_valid(cards):
			return
		var data := [
			["ÉLIMINATIONS", str(p.kills), UiTheme.CYAN], ["K/D", "%.2f" % p.kd, UiTheme.MAGENTA],
			["VICTOIRES", str(p.wins), UiTheme.YELLOW], ["PARTIES", str(p.matches), UiTheme.GREEN],
			["MEILLEURE SÉRIE", str(p.best_streak), UiTheme.CYAN], ["TEMPS DE JEU", "%d min" % p.playtime_min, UiTheme.MAGENTA],
			["CLASSE FAVORITE", p.favorite_class, UiTheme.YELLOW], ["NIVEAU", str(p.level), UiTheme.GREEN],
		]
		for d in data:
			cards.add_child(_stat_card(d[0], d[1], d[2]))

	var fill := func(scope: String) -> void:
		world.add_theme_color_override("font_color", UiTheme.CYAN if scope == "world" else UiTheme.TEXT)
		friends.add_theme_color_override("font_color", UiTheme.CYAN if scope == "friends" else UiTheme.TEXT)
		for c in rows.get_children():
			c.queue_free()
		var data: Array = await Backend.get_leaderboard(scope)
		if not is_instance_valid(rows):
			return
		for c in rows.get_children():
			c.queue_free()
		var weights := [0.6, 2.4, 0.8, 1.0, 1.0, 0.8, 1.0]
		rows.add_child(_table_row(["#", "JOUEUR", "NIV.", "KILLS", "MORTS", "K/D", "VICTOIRES"], true, weights))
		for r in data:
			var row := _table_row(["%d" % r.rank, r.name, str(r.level), str(r.kills), str(r.deaths), "%.2f" % r.kd, str(r.wins)], false, weights)
			var cells := row.get_child(0) as HBoxContainer
			if r.rank <= 3:
				(cells.get_child(0) as Label).add_theme_color_override("font_color", [UiTheme.YELLOW, Color(0.8, 0.85, 0.9), Color(0.85, 0.55, 0.3)][r.rank - 1])
			if r.me:
				row.add_theme_stylebox_override("panel", UiTheme.box(Color(UiTheme.CYAN, 0.16), UiTheme.CYAN, 1, 4, 12, 6))
				(cells.get_child(1) as Label).text = "%s (toi)" % r.name
			rows.add_child(row)
	world.pressed.connect(fill.bind("world"))
	friends.pressed.connect(fill.bind("friends"))
	fill_cards.call()
	fill.call("world")
	return col


func _stat_card(title: String, value: String, color: Color) -> Control:
	var card := UiTheme.panel(UiTheme.PANEL, Color(color, 0.35))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	card.add_child(box)
	box.add_child(UiTheme.label(title, 13, UiTheme.MUTED, true))
	var number := UiTheme.label(value, 32, color, true)
	box.add_child(number)
	return card


# =========================================================================== AMIS

func _build_social_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(290, 0)
	panel.add_theme_stylebox_override("panel", UiTheme.box(Color(0.03, 0.04, 0.07, 0.88), Color(UiTheme.CYAN, 0.12), 1, 0, 16, 16))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	col.add_child(UiTheme.title("AMIS", 18))
	_friends_box = VBoxContainer.new()
	_friends_box.add_theme_constant_override("separation", 6)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(_friends_box)
	_friends_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	col.add_child(UiTheme.label("AJOUTER UN AMI", 13, UiTheme.MUTED, true))
	var add_row := HBoxContainer.new()
	var field := LineEdit.new()
	field.placeholder_text = "Pseudo"
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(field)
	var send := Button.new()
	send.text = "Envoyer"
	add_row.add_child(send)
	col.add_child(add_row)
	var feedback := UiTheme.label("", 14, UiTheme.GREEN)
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(feedback)
	send.pressed.connect(func() -> void:
		if field.text.strip_edges().is_empty():
			return
		feedback.text = "Demande d'ami envoyée à %s." % field.text.strip_edges()
		field.text = "")
	return panel


func _refresh_friends() -> void:
	var friends: Array = await Backend.get_friends()
	for c in _friends_box.get_children():
		c.queue_free()
	var online := friends.filter(func(f): return f.status != "offline").size()
	_friends_box.add_child(UiTheme.label("%d EN LIGNE · %d AU TOTAL" % [online, friends.size()], 13, UiTheme.MUTED, true))
	for f in friends:
		_friends_box.add_child(_friend_row(f))


func _friend_row(f: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.box(Color(1, 1, 1, 0.035), Color(0, 0, 0, 0), 0, 4, 10, 6))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var color: Color = {"online": UiTheme.GREEN, "in_match": UiTheme.YELLOW}.get(f.status, Color(UiTheme.MUTED, 0.5))
	row.add_child(UiTheme.dot(color, 10))
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", -2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(UiTheme.label("%s  · niv. %d" % [f.name, f.level], 17, Color.WHITE if f.status != "offline" else UiTheme.MUTED, true))
	info.add_child(UiTheme.label(f.activity, 14, UiTheme.MUTED))
	row.add_child(info)
	if f.status == "online":
		var invite := Button.new()
		invite.text = "+"
		invite.tooltip_text = "Inviter dans le groupe"
		invite.custom_minimum_size = Vector2(34, 34)
		invite.pressed.connect(func() -> void:
			invite.disabled = true
			invite.text = "…"
			var r: Dictionary = await Backend.invite_to_party(f.name)
			if is_instance_valid(invite):
				invite.text = "✓" if r.get("ok", false) else "!"
				invite.tooltip_text = "Dans le groupe" if r.get("ok", false) else r.get("error", ""))
		row.add_child(invite)
	return panel


# =========================================================================== lancement

func _create_server() -> void:
	_show_overlay("CRÉATION DU SERVEUR")
	var result: Dictionary = await Backend.create_server(_set_overlay_step)
	_launch(result, "deathmatch")


func _join_server(server: Dictionary) -> void:
	_show_overlay("CONNEXION AU SERVEUR")
	var result: Dictionary = await Backend.join_server(server, _set_overlay_step)
	_launch(result, "deathmatch")


func _start_training() -> void:
	GameState.mode = "training"
	get_tree().change_scene_to_file(GAME)


func _launch(result: Dictionary, mode: String) -> void:
	if not result.get("ok", false):
		_overlay.queue_free()
		return
	GameState.mode = mode
	# Le serveur est complété par des bots pour atteindre 6 joueurs au moins.
	GameState.bot_count = clampi(6 - Backend.party.size(), 3, 7)
	get_tree().change_scene_to_file(GAME)


func _show_overlay(title: String) -> void:
	_overlay = ColorRect.new()
	(_overlay as ColorRect).color = Color(0.01, 0.015, 0.03, 0.88)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	var t := UiTheme.title(title, 30, UiTheme.CYAN)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(420, 6)
	bar.show_percentage = false
	bar.name = "Bar"
	box.add_child(bar)
	var step := UiTheme.label("", 19, UiTheme.MUTED)
	step.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	step.name = "Step"
	box.add_child(step)
	var tween := bar.create_tween().set_loops()
	tween.tween_property(bar, "value", 100.0, 1.2)
	tween.tween_property(bar, "value", 0.0, 0.0)


func _set_overlay_step(text: String) -> void:
	if is_instance_valid(_overlay):
		var step := _overlay.find_child("Step", true, false) as Label
		if step:
			step.text = text
