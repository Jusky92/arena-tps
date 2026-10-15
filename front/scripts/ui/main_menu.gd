extends Control
## Menu principal (après connexion).
##   JOUER         classe, groupe, lancement en ligne, serveurs publics, LAN (hors ligne seulement), bots
##   CLASSES       ouvre l'écran de choix de classe
##   STATISTIQUES  stats et succès du joueur, classements (XP, victoires, éliminations)
##   AMIS          tiroir à droite (bouton sous la barre de navigation) : présence,
##                 demandes d'ami, ajout, invitation dans le groupe
## Toutes les données viennent de l'autoload Backend (vrai back, ou simulé hors ligne).
##
## Lancer une partie en ligne : le chef du groupe (ou un joueur seul) demande un
## serveur (Backend.launch_party) ; chaque membre reçoit son ticket (le chef dans
## la réponse, les autres par le service temps réel : Backend.match_ready) et se
## connecte au serveur de jeu avec (Net.join).

const GAME := "res://scenes/game.tscn"
const LOBBY := "res://scenes/lobby.tscn"
const CLASS_SELECT := "res://scenes/class_select.tscn"
const AUTH := "res://scenes/auth.tscn"
## Dernière adresse de connexion, gardée d'une partie à l'autre.
const ADDRESS_PATH := "user://reseau.cfg"
const BOARDS := [["XP", "xp"], ["VICTOIRES", "wins"], ["ÉLIMINATIONS", "kills"]]

var _page_holder: MarginContainer
var _nav_buttons := {}
var _profile_box: HBoxContainer
var _friends_box: VBoxContainer
var _party_box: VBoxContainer
var _services_label: Label
var _services_dot: Panel
var _overlay: Control
var _address_field: LineEdit
var _online_error: Label
var _launch_button: Button
var _friends_button: Button
var _drawer: PanelContainer
var _drawer_tween: Tween

const DRAWER_WIDTH := 340.0
## Écart avec le bord droit de l'écran, le même que celui du bouton AMIS.
const DRAWER_MARGIN := 24.0
## Tiroir d'amis ouvert ou fermé, gardé d'un écran à l'autre (choix de classe, partie).
static var _drawer_open := false


func _ready() -> void:
	theme = UiTheme.get_theme()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if not Backend.is_logged_in():
		if not Backend.is_simulated():
			get_tree().change_scene_to_file.call_deferred(AUTH)
			return
		await Backend.login("joueur@exemple.fr", "")   # lancement direct de cette scène : session hors ligne
	add_child(UiTheme.background())

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	root.add_child(_build_top_bar())

	root.add_child(_build_friends_toggle())

	# La page occupe toute la largeur ; le tiroir d'amis glisse par-dessus, à droite.
	var body := Control.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.clip_contents = true
	root.add_child(body)
	_page_holder = MarginContainer.new()
	_page_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		_page_holder.add_theme_constant_override("margin_" + side, 24 if side != "top" else 6)
	body.add_child(_page_holder)
	_drawer = _build_social_panel()
	body.add_child(_drawer)
	_set_drawer(_drawer_open, false)
	root.add_child(_build_bottom_bar())

	Backend.party_changed.connect(_refresh_party)
	Backend.party_changed.connect(_refresh_friends)    # bouton + réservé au chef
	Backend.invites_changed.connect(_refresh_party)
	Backend.friends_changed.connect(_refresh_friends)
	Backend.match_ready.connect(_on_match_ready)
	Backend.session_lost.connect(_on_session_lost)
	Backend.services_changed.connect(_refresh_services)
	Backend.toast.connect(_show_toast)
	Net.joined.connect(_on_net_joined)
	Net.connection_failed.connect(_on_net_failed)
	_refresh_profile()
	_refresh_friends()
	_refresh_services()
	Backend.refresh_friends()
	_show_page("play")
	Backend.leave_solo_party()


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


## Bouton rectangulaire en haut à droite, sous la barre de navigation : ouvre et ferme le tiroir d'amis.
func _build_friends_toggle() -> Control:
	var row := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		row.add_theme_constant_override("margin_" + side, 24 if side in ["left", "right"] else 10 if side == "top" else 0)
	_friends_button = UiTheme.button("AMIS", false, UiTheme.CYAN, 40)
	_friends_button.toggle_mode = true
	_friends_button.custom_minimum_size.x = 260
	_friends_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_friends_button.tooltip_text = "Afficher ou masquer la liste d'amis"
	_friends_button.toggled.connect(func(on: bool) -> void: _set_drawer(on))
	row.add_child(_friends_button)
	return row


## Ouvre ou ferme le tiroir d'amis (glissement depuis le bord droit).
func _set_drawer(open: bool, animate := true) -> void:
	_drawer_open = open
	if is_instance_valid(_friends_button):
		_friends_button.set_pressed_no_signal(open)
		_update_friends_button()
	if not is_instance_valid(_drawer):
		return
	if _drawer_tween:
		_drawer_tween.kill()
	var left := -DRAWER_WIDTH - DRAWER_MARGIN if open else 0.0
	if open:
		_drawer.visible = true
	if not animate:
		_drawer.offset_left = left
		_drawer.offset_right = left + DRAWER_WIDTH
		_drawer.visible = open
		return
	_drawer_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_drawer_tween.tween_property(_drawer, "offset_left", left, 0.22)
	_drawer_tween.tween_property(_drawer, "offset_right", left + DRAWER_WIDTH, 0.22)
	if not open:
		_drawer_tween.chain().tween_callback(func() -> void: _drawer.visible = false)


## Texte du bouton : amis en ligne, et demandes reçues en magenta.
func _update_friends_button() -> void:
	if not is_instance_valid(_friends_button):
		return
	var online: int = Backend.friends.filter(func(f): return f.status != "offline").size()
	var text := "AMIS  ·  %d EN LIGNE" % online
	var requests: int = Backend.incoming.size()
	if requests > 0:
		text += "  ·  %d DEMANDE%s" % [requests, "S" if requests > 1 else ""]
	_friends_button.text = text + ("   ▸" if _drawer_open else "   ◂")
	var accent := UiTheme.MAGENTA if requests > 0 else Color.WHITE
	_friends_button.add_theme_color_override("font_color", accent)
	_friends_button.add_theme_color_override("font_hover_color", accent)
	_friends_button.add_theme_color_override("font_pressed_color", accent)


func _build_bottom_bar() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiTheme.box(Color(0.02, 0.03, 0.05, 0.85), Color(0, 0, 0, 0), 0, 0, 24, 6))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)
	_services_dot = UiTheme.dot(UiTheme.GREEN, 8)
	row.add_child(_services_dot)
	_services_label = UiTheme.label("", 15, UiTheme.MUTED)
	row.add_child(_services_label)
	row.add_child(UiTheme.label("·  Build %s" % Backend.BUILD_VERSION, 15, UiTheme.MUTED))
	row.add_child(UiTheme.spacer(Vector2.ZERO, true))
	row.add_child(UiTheme.label("CFA INSTA · Architecture SI · M2", 15, Color(UiTheme.MAGENTA, 0.8), true))
	return bar


func _refresh_services() -> void:
	if not is_instance_valid(_services_label):
		return
	var color := UiTheme.YELLOW
	if Backend.is_simulated():
		_services_label.text = "Hors ligne (back simulé) : parties LAN par adresse"
	elif Backend.services_online():
		_services_label.text = "Services : connectés (%s)" % Backend.host
		color = UiTheme.GREEN
	else:
		_services_label.text = "Services : connexion au temps réel… (%s)" % Backend.host
	_services_dot.add_theme_stylebox_override("panel", UiTheme.box(color, Color(0, 0, 0, 0), 0, 4, 0, 0))


func _refresh_profile() -> void:
	var p: Dictionary = await Backend.get_profile()
	if not is_instance_valid(_profile_box):
		return
	for c in _profile_box.get_children():
		c.queue_free()
	if not p.ok:
		_profile_box.add_child(UiTheme.label(Backend.username(), 19, Color.WHITE, true))
		return
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", UiTheme.box(Color(UiTheme.MAGENTA, 0.85), Color(0, 0, 0, 0), 0, 4, 8, 2))
	badge.add_child(UiTheme.title(str(p.level), 15, Color(0.03, 0.03, 0.06)))
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.tooltip_text = "Niveau %d · %d / %d XP" % [p.level, p.xp_in_level, p.xp_to_next_level]
	_profile_box.add_child(badge)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.add_child(UiTheme.label(p.username, 19, Color.WHITE, true))
	var xp := ProgressBar.new()
	xp.custom_minimum_size = Vector2(150, 5)
	xp.show_percentage = false
	xp.max_value = p.xp_to_next_level
	xp.value = p.xp_in_level
	info.add_child(xp)
	_profile_box.add_child(info)


## Court message en bas à droite, qui disparaît seul.
func _show_toast(text: String) -> void:
	var toast := PanelContainer.new()
	toast.add_theme_stylebox_override("panel", UiTheme.box(Color(0.05, 0.07, 0.12, 0.95), UiTheme.CYAN, 1, 6, 16, 10))
	toast.add_child(UiTheme.label(text, 17, Color.WHITE, true))
	toast.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	toast.position = get_viewport_rect().size - Vector2(460, 120)
	add_child(toast)
	var tween := toast.create_tween()
	tween.tween_interval(4.0)
	tween.tween_property(toast, "modulate:a", 0.0, 0.6)
	tween.tween_callback(toast.queue_free)


func _on_session_lost(reason: String) -> void:
	_show_toast(reason)
	await get_tree().create_timer(1.5).timeout
	get_tree().change_scene_to_file(AUTH)


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

	# Colonne de droite : groupe, lancement, LAN, hors ligne (défile sur petit écran).
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 14)
	scroll.add_child(col)

	# Invitations reçues, puis le groupe (ou le bouton pour en créer un).
	_party_box = VBoxContainer.new()
	_party_box.add_theme_constant_override("separation", 8)
	col.add_child(_party_box)
	_refresh_party()

	# --- En ligne, avec le back : groupe -> serveur dédié ---
	var launch_row := HBoxContainer.new()
	launch_row.add_theme_constant_override("separation", 12)
	_launch_button = UiTheme.button("LANCER EN LIGNE", true, UiTheme.CYAN, 58)
	_launch_button.add_theme_font_size_override("font_size", 20)
	_launch_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_launch_button.tooltip_text = "Réserve un serveur de jeu pour ton groupe (ou pour toi seul)"
	_launch_button.pressed.connect(_launch_online)
	launch_row.add_child(_launch_button)
	var servers := UiTheme.button("SERVEURS PUBLICS", false, UiTheme.MAGENTA, 58)
	servers.custom_minimum_size.x = 210
	servers.tooltip_text = "Rejoindre une partie en cours qui a des places libres"
	servers.pressed.connect(_show_page.bind("servers"))
	launch_row.add_child(servers)
	col.add_child(launch_row)
	_update_launch_button()

	# --- LAN par adresse : seulement hors ligne (back simulé), avec le vrai back on passe par les tickets ---
	if Backend.is_simulated():
		var online := UiTheme.panel(Color(UiTheme.CYAN, 0.07), Color(UiTheme.CYAN, 0.35))
		var online_box := VBoxContainer.new()
		online_box.add_theme_constant_override("separation", 10)
		online.add_child(online_box)
		online_box.add_child(UiTheme.label("REJOINDRE PAR ADRESSE (LAN)", 14, UiTheme.CYAN, true))
		var online_help := UiTheme.label("Pour un serveur lancé en mode LAN : entre l'adresse qu'il affiche au démarrage.", 15, UiTheme.MUTED)
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

	# --- Hors ligne (ne compte pas dans les statistiques) ---
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	var solo := UiTheme.button("PARTIE SOLO (BOTS)", false, UiTheme.CYAN, 50)
	solo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	solo.tooltip_text = "Match à mort hors ligne contre des bots (ne compte pas dans les statistiques)"
	solo.pressed.connect(_start_solo)
	buttons.add_child(solo)
	var training := UiTheme.button("ENTRAÎNEMENT", false, UiTheme.CYAN, 50)
	training.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	training.tooltip_text = "Seul sur la map avec des mannequins d'entraînement"
	training.pressed.connect(_start_training)
	buttons.add_child(training)
	col.add_child(buttons)
	return row


func _update_launch_button() -> void:
	if not is_instance_valid(_launch_button):
		return
	var leader := Backend.is_party_leader()
	_launch_button.disabled = not leader or Backend.is_simulated()
	if Backend.is_simulated():
		_launch_button.text = "LANCER EN LIGNE (connecte-toi au back)"
	elif not leader:
		_launch_button.text = "LE CHEF LANCE LA PARTIE…"
	else:
		var count: int = Backend.party_members().size()
		_launch_button.text = "LANCER EN LIGNE" if count <= 1 else "LANCER EN LIGNE (%d JOUEURS)" % count


# --------------------------------------------------------------------------- groupe

func _refresh_party() -> void:
	_update_launch_button()
	if not is_instance_valid(_party_box):
		return
	for c in _party_box.get_children():
		c.queue_free()

	# Invitations reçues.
	for invite in Backend.invites:
		var banner := PanelContainer.new()
		banner.add_theme_stylebox_override("panel", UiTheme.box(Color(UiTheme.MAGENTA, 0.14), UiTheme.MAGENTA, 1, 4, 10, 6))
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		banner.add_child(line)
		var text := UiTheme.label("%s t'invite dans son groupe." % invite.from_name, 17, Color.WHITE, true)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
		var accept := UiTheme.button("REJOINDRE", true, UiTheme.MAGENTA, 34)
		accept.pressed.connect(func() -> void:
			accept.disabled = true
			var r: Dictionary = await Backend.accept_invite(invite.invite_id)
			if not r.ok:
				_show_toast(r.message))
		line.add_child(accept)
		var ignore := Button.new()
		ignore.text = "Ignorer"
		ignore.pressed.connect(Backend.dismiss_invite.bind(invite.invite_id))
		line.add_child(ignore)
		_party_box.add_child(banner)

	if Backend.party.is_empty():
		_party_box.add_child(_build_no_party())
	else:
		_party_box.add_child(_build_party_panel())


## Pas de groupe (cas par défaut) : bouton pour en créer un.
func _build_no_party() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var create := UiTheme.button("CRÉER UN GROUPE", false, UiTheme.CYAN, 46)
	create.custom_minimum_size.x = 210
	create.tooltip_text = "Crée un groupe dont tu es le chef, puis invite tes amis"
	create.pressed.connect(func() -> void:
		create.disabled = true
		var r: Dictionary = await Backend.create_party()
		if not r.ok:
			if is_instance_valid(create):
				create.disabled = false
			_show_toast(r.message))
	row.add_child(create)
	return row


## Encadré GROUPE : membres et places libres, exclusion (chef), quitter ou supprimer.
func _build_party_panel() -> Control:
	var panel := UiTheme.panel()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var members: Array = Backend.party_members()
	var leader_id: String = Backend.party.get("leader_id", "")
	var i_lead := Backend.is_party_leader()
	var header := HBoxContainer.new()
	header.add_child(UiTheme.label("GROUPE", 14, UiTheme.MUTED, true))
	header.add_child(UiTheme.spacer(Vector2.ZERO, true))
	header.add_child(UiTheme.label("%d / 8" % members.size(), 15, UiTheme.CYAN, true))
	# Seul dans le groupe : le quitter le supprime (côté back aussi).
	var alone := members.size() <= 1
	var leave := Button.new()
	leave.text = "Supprimer le groupe" if alone else "Quitter le groupe"
	leave.pressed.connect(func() -> void:
		leave.disabled = true
		var r: Dictionary = await Backend.leave_party()
		if not r.ok:
			if is_instance_valid(leave):
				leave.disabled = false
			_show_toast(r.message))
	header.add_child(UiTheme.spacer(Vector2(10, 0)))
	header.add_child(leave)
	box.add_child(header)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for i in 8:
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(120, 38)
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var filled := i < members.size()
		slot.add_theme_stylebox_override("panel", UiTheme.box(
			Color(UiTheme.CYAN, 0.12) if filled else Color(1, 1, 1, 0.03),
			Color(UiTheme.CYAN, 0.5) if filled else Color(1, 1, 1, 0.08), 1, 4, 10, 4))
		var line := HBoxContainer.new()
		slot.add_child(line)
		var text := "Place libre"
		if filled:
			var m: Dictionary = members[i]
			text = ("★ " if m.user_id == leader_id else "") + m.username + (" (toi)" if m.user_id == Backend.user_id() else "")
		var l := UiTheme.label(text, 16, Color.WHITE if filled else Color(UiTheme.MUTED, 0.6), filled)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		line.add_child(l)
		if filled and i_lead and members[i].user_id != Backend.user_id():
			var kick := Button.new()
			kick.text = "✕"
			kick.flat = true
			kick.tooltip_text = "Exclure du groupe"
			var member_id: String = members[i].user_id
			kick.pressed.connect(func() -> void:
				var r: Dictionary = await Backend.kick_from_party(member_id)
				if not r.ok:
					_show_toast(r.message))
			line.add_child(kick)
		grid.add_child(slot)
	box.add_child(grid)
	var help := UiTheme.label("Invite tes amis en ligne avec le bouton + dans la liste de droite. Le chef lance la partie : chacun rejoint le serveur automatiquement, et les places libres s'ouvrent aux autres joueurs.", 14, UiTheme.MUTED)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(help)
	return panel


# --------------------------------------------------------------------------- lancement en ligne

## Chef : réserve un serveur pour le groupe et s'y connecte avec son ticket.
func _launch_online() -> void:
	if Net.online or Net.is_connecting():
		return
	_show_overlay("RÉSERVATION D'UN SERVEUR")
	_set_overlay_step("Demande d'un serveur libre…")
	var r: Dictionary = await Backend.launch_party()
	if not r.ok:
		_overlay_error(r.message)
		Backend.leave_solo_party()
		return
	_connect_with_ticket(r)


## Membre d'un groupe : le chef a lancé, voici notre ticket (service temps réel).
func _on_match_ready(info: Dictionary) -> void:
	if Net.online or Net.is_connecting():
		return            # le chef est déjà en route avec la réponse du lancement
	_show_overlay("TON GROUPE A UN SERVEUR")
	_connect_with_ticket(info)


## Connexion au serveur de jeu avec un ticket (lancement ou serveur public).
func _connect_with_ticket(info: Dictionary) -> void:
	_set_overlay_step("Connexion à %s:%d…" % [info.address, info.port])
	var error := Net.join(info.address, Backend.username(), info.port, info.ticket)
	if not error.is_empty():
		_overlay_error(error)


# --------------------------------------------------------------------------- LAN par adresse

## Rejoint un serveur LAN à partir de son adresse (IP ou IP:port), sans ticket.
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
	Backend.leave_solo_party()     # lancement solo : le serveur n'a pas pu être rejoint
	if is_instance_valid(_overlay):
		_overlay_error(reason)     # connexion avec un ticket (lancement, serveur public)
		return
	if is_instance_valid(_online_error):
		_show_online_error(reason + "\nJournal détaillé : " + Net.log_file_path())
	else:
		_show_toast(reason)


func _show_online_error(text: String) -> void:
	if not is_instance_valid(_online_error):
		_show_toast(text)
		return
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


# --------------------------------------------------------------------------- SERVEURS PUBLICS

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
		var r: Dictionary = await Backend.get_servers()
		if not is_instance_valid(rows):
			return
		for c in rows.get_children():
			c.queue_free()
		if not r.ok:
			var error := UiTheme.label(r.message, 17, UiTheme.YELLOW)
			error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			rows.add_child(error)
			return
		if r.servers.is_empty():
			rows.add_child(UiTheme.label("Aucune partie en cours avec des places libres. Lance la tienne depuis JOUER !", 17, UiTheme.MUTED))
			return
		rows.add_child(_table_row(["SERVEUR", "RÉGION", "MAP", "JOUEURS", ""], true, [3.0, 1.0, 1.2, 1.0, 1.2]))
		for s in r.servers:
			rows.add_child(_server_row(s))
	refresh.pressed.connect(fill)
	fill.call()
	return col


func _server_row(s: Dictionary) -> Control:
	var row := _table_row([s.name, str(s.region).to_upper(), str(s.map).to_upper(), "%d / %d" % [s.players, s.max_players], ""],
		false, [3.0, 1.0, 1.2, 1.0, 1.2])
	var cells := row.get_child(0) as HBoxContainer
	var holder := cells.get_child(4)
	var join := UiTheme.button("REJOINDRE", true, UiTheme.MAGENTA, 34)
	join.add_theme_font_size_override("font_size", 13)
	join.pressed.connect(_join_public.bind(s))
	holder.add_child(join)
	return row


## Rejoint une partie en cours : ticket à usage unique (30 s), puis connexion.
func _join_public(server: Dictionary) -> void:
	if Net.online or Net.is_connecting():
		return
	_show_overlay("CONNEXION AU SERVEUR")
	_set_overlay_step("Demande d'un ticket pour %s…" % server.name)
	var r: Dictionary = await Backend.get_join_ticket(server.server_id)
	if not r.ok:
		_overlay_error(r.message)
		return
	_connect_with_ticket(r)


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
	var title_row := HBoxContainer.new()
	title_row.add_child(UiTheme.title("STATISTIQUES", 24))
	title_row.add_child(UiTheme.spacer(Vector2(16, 0)))
	var note := UiTheme.label("Seules les parties en ligne (serveur dédié) comptent.", 15, UiTheme.MUTED)
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(note)
	col.add_child(title_row)

	var cards := GridContainer.new()
	cards.columns = 4
	cards.add_theme_constant_override("h_separation", 12)
	cards.add_theme_constant_override("v_separation", 12)
	col.add_child(cards)

	var middle := HBoxContainer.new()
	middle.add_theme_constant_override("separation", 14)
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(middle)

	# Classement.
	var board := VBoxContainer.new()
	board.add_theme_constant_override("separation", 8)
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_stretch_ratio = 1.6
	middle.add_child(board)
	var switch := HBoxContainer.new()
	switch.add_theme_constant_override("separation", 8)
	switch.add_child(UiTheme.label("CLASSEMENT", 14, UiTheme.MUTED, true))
	switch.add_child(UiTheme.spacer(Vector2(10, 0)))
	var type_buttons := {}
	for entry in BOARDS:
		var b := Button.new()
		b.text = entry[0]
		switch.add_child(b)
		type_buttons[entry[1]] = b
	switch.add_child(UiTheme.spacer(Vector2.ZERO, true))
	var around := CheckButton.new()
	around.text = "Autour de moi"
	switch.add_child(around)
	board.add_child(switch)
	var table := UiTheme.panel()
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	table.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 4)
	scroll.add_child(rows)
	board.add_child(table)

	# Succès.
	var achievements_panel := UiTheme.panel()
	achievements_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var achievements := VBoxContainer.new()
	achievements.add_theme_constant_override("separation", 8)
	achievements_panel.add_child(achievements)
	middle.add_child(achievements_panel)

	var fill_profile := func() -> void:
		var p: Dictionary = await Backend.get_profile()
		if not is_instance_valid(cards):
			return
		if not p.ok:
			cards.add_child(UiTheme.label(p.message, 17, UiTheme.YELLOW))
			return
		var unlocked: Array = p.achievements.filter(func(a): return a.unlocked_at != null)
		var data := [
			["PARTIES", str(p.matches), UiTheme.GREEN], ["VICTOIRES", str(p.wins), UiTheme.YELLOW],
			["ÉLIMINATIONS", str(p.kills), UiTheme.CYAN], ["K/D", "%.2f" % p.kd, UiTheme.MAGENTA],
			["MORTS", str(p.deaths), UiTheme.CYAN], ["NIVEAU", str(p.level), UiTheme.GREEN],
			["XP TOTALE", str(p.xp), UiTheme.MAGENTA], ["SUCCÈS", "%d / %d" % [unlocked.size(), p.achievements.size()], UiTheme.YELLOW],
		]
		for d in data:
			cards.add_child(_stat_card(d[0], d[1], d[2]))
		achievements.add_child(UiTheme.label("SUCCÈS", 14, UiTheme.MUTED, true))
		for a in p.achievements:
			var done: bool = a.unlocked_at != null
			var line := VBoxContainer.new()
			line.add_theme_constant_override("separation", -2)
			line.add_child(UiTheme.label(("✓ " if done else "· ") + Backend.achievement_name(a.id, a.name), 17,
				UiTheme.YELLOW if done else UiTheme.MUTED, true))
			var desc := UiTheme.label(Backend.achievement_description(a.id, a.description), 14, UiTheme.MUTED)
			desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			line.add_child(desc)
			achievements.add_child(line)

	var state := {"type": "xp"}
	var fill := func() -> void:
		for key in type_buttons:
			type_buttons[key].add_theme_color_override("font_color", UiTheme.CYAN if key == state.type else UiTheme.TEXT)
		for c in rows.get_children():
			c.queue_free()
		var r: Dictionary = await Backend.get_leaderboard(state.type, around.button_pressed)
		if not is_instance_valid(rows):
			return
		for c in rows.get_children():
			c.queue_free()
		if not r.ok:
			rows.add_child(UiTheme.label(r.message, 17, UiTheme.YELLOW))
			return
		if r.entries.is_empty():
			rows.add_child(UiTheme.label("Personne n'a encore terminé de partie en ligne." if not around.button_pressed
				else "Termine une partie en ligne pour apparaître au classement.", 17, UiTheme.MUTED))
			return
		var weights := [0.6, 3.0, 1.2]
		var column: String = {"xp": "XP", "wins": "VICTOIRES", "kills": "ÉLIMINATIONS"}[state.type]
		rows.add_child(_table_row(["#", "JOUEUR", column], true, weights))
		for e in r.entries:
			var row := _table_row(["%d" % e.rank, e.username, str(e.value)], false, weights)
			var cells := row.get_child(0) as HBoxContainer
			if e.rank <= 3:
				(cells.get_child(0) as Label).add_theme_color_override("font_color", [UiTheme.YELLOW, Color(0.8, 0.85, 0.9), Color(0.85, 0.55, 0.3)][e.rank - 1])
			if e.me:
				row.add_theme_stylebox_override("panel", UiTheme.box(Color(UiTheme.CYAN, 0.16), UiTheme.CYAN, 1, 4, 12, 6))
				(cells.get_child(1) as Label).text = "%s (toi)" % e.username
			rows.add_child(row)
	for key in type_buttons:
		type_buttons[key].pressed.connect(func() -> void:
			state.type = key
			fill.call())
	around.toggled.connect(func(_on: bool) -> void: fill.call())
	fill_profile.call()
	fill.call()
	return col


func _stat_card(title: String, value: String, color: Color) -> Control:
	var card := UiTheme.panel(UiTheme.PANEL, Color(color, 0.35))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	card.add_child(box)
	box.add_child(UiTheme.label(title, 13, UiTheme.MUTED, true))
	box.add_child(UiTheme.label(value, 32, color, true))
	return card


# =========================================================================== AMIS

## Tiroir d'amis, ancré au bord droit du corps de page (placé par _set_drawer).
func _build_social_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_bottom = -10
	panel.offset_top = 6
	panel.add_theme_stylebox_override("panel", UiTheme.box(Color(0.03, 0.04, 0.07), Color(UiTheme.CYAN, 0.35), 1, 6, 16, 16))
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

	# Ajout d'un ami : recherche par pseudo, puis choix dans les résultats.
	col.add_child(UiTheme.label("AJOUTER UN AMI", 13, UiTheme.MUTED, true))
	var add_row := HBoxContainer.new()
	var field := LineEdit.new()
	field.placeholder_text = "Pseudo (ou une partie)"
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(field)
	var search := Button.new()
	search.text = "Chercher"
	add_row.add_child(search)
	col.add_child(add_row)
	var results := VBoxContainer.new()
	results.add_theme_constant_override("separation", 4)
	col.add_child(results)
	var feedback := UiTheme.label("", 14, UiTheme.GREEN)
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(feedback)
	var run_search := func() -> void:
		for c in results.get_children():
			c.queue_free()
		feedback.text = ""
		var r: Dictionary = await Backend.search_users(field.text)
		if not is_instance_valid(results):
			return
		if not r.ok:
			feedback.add_theme_color_override("font_color", UiTheme.RED)
			feedback.text = r.message
			return
		if r.users.is_empty():
			feedback.add_theme_color_override("font_color", UiTheme.MUTED)
			feedback.text = "Aucun joueur trouvé."
			return
		for u in r.users.slice(0, 6):
			var line := HBoxContainer.new()
			var user_label := UiTheme.label(u.username, 16, Color.WHITE, true)
			user_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(user_label)
			var add := Button.new()
			add.text = "Ajouter"
			add.pressed.connect(func() -> void:
				add.disabled = true
				var sent: Dictionary = await Backend.send_friend_request(u.user_id)
				if not is_instance_valid(feedback):
					return
				feedback.add_theme_color_override("font_color", UiTheme.GREEN if sent.ok else UiTheme.RED)
				feedback.text = sent.message if not sent.message.is_empty() else "Demande envoyée à %s." % u.username
				for c in results.get_children():
					c.queue_free())
			line.add_child(add)
			results.add_child(line)
	search.pressed.connect(run_search)
	field.text_submitted.connect(func(_t: String) -> void: run_search.call())
	return panel


func _refresh_friends() -> void:
	_update_friends_button()
	if not is_instance_valid(_friends_box):
		return
	for c in _friends_box.get_children():
		c.queue_free()

	if not Backend.incoming.is_empty():
		_friends_box.add_child(UiTheme.label("DEMANDES REÇUES", 13, UiTheme.MAGENTA, true))
		for q in Backend.incoming:
			_friends_box.add_child(_request_row(q, true))
	var friends: Array = Backend.friends
	var online := friends.filter(func(f): return f.status != "offline").size()
	_friends_box.add_child(UiTheme.label("%d EN LIGNE · %d AU TOTAL" % [online, friends.size()], 13, UiTheme.MUTED, true))
	if friends.is_empty():
		var hint := UiTheme.label("Pas encore d'amis : cherche un pseudo ci-dessous.", 14, UiTheme.MUTED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_friends_box.add_child(hint)
	for f in friends:
		_friends_box.add_child(_friend_row(f))
	if not Backend.outgoing.is_empty():
		_friends_box.add_child(UiTheme.label("DEMANDES ENVOYÉES", 13, UiTheme.MUTED, true))
		for q in Backend.outgoing:
			_friends_box.add_child(_request_row(q, false))


## Demande d'ami reçue (Accepter / Refuser) ou envoyée (Annuler).
func _request_row(q: Dictionary, received: bool) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.box(Color(1, 1, 1, 0.035), Color(0, 0, 0, 0), 0, 4, 10, 6))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	var name_label := UiTheme.label(q.username, 16, Color.WHITE if received else UiTheme.MUTED, true)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	row.add_child(name_label)
	if received:
		var accept := Button.new()
		accept.text = "✓"
		accept.tooltip_text = "Accepter"
		accept.pressed.connect(func() -> void:
			accept.disabled = true
			var r: Dictionary = await Backend.accept_friend_request(q.request_id)
			if not r.ok:
				_show_toast(r.message))
		row.add_child(accept)
	var decline := Button.new()
	decline.text = "✕"
	decline.tooltip_text = "Refuser" if received else "Annuler la demande"
	decline.pressed.connect(func() -> void:
		decline.disabled = true
		var r: Dictionary = await Backend.decline_friend_request(q.request_id)
		if not r.ok:
			_show_toast(r.message))
	row.add_child(decline)
	return panel


func _friend_row(f: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.box(Color(1, 1, 1, 0.035), Color(0, 0, 0, 0), 0, 4, 10, 6))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var in_match: bool = f.status == "online" and f.activity == "in_match"
	var color: Color = UiTheme.YELLOW if in_match else (UiTheme.GREEN if f.status == "online" else Color(UiTheme.MUTED, 0.5))
	row.add_child(UiTheme.dot(color, 10))
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", -2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(UiTheme.label(f.username, 17, Color.WHITE if f.status != "offline" else UiTheme.MUTED, true))
	var activity := "En partie" if in_match else ("Dans le menu" if f.status == "online" else "Hors ligne")
	info.add_child(UiTheme.label(activity, 14, UiTheme.MUTED))
	row.add_child(info)
	if f.status == "online" and not in_match and Backend.is_party_leader():
		var already: bool = Backend.party_members().any(func(m): return m.user_id == f.user_id)
		if not already:
			var invite := Button.new()
			invite.text = "+"
			invite.tooltip_text = "Inviter dans le groupe"
			invite.custom_minimum_size = Vector2(34, 34)
			invite.pressed.connect(func() -> void:
				invite.disabled = true
				invite.text = "…"
				var r: Dictionary = await Backend.invite_to_party(f.user_id)
				if is_instance_valid(invite):
					invite.text = "✓" if r.ok else "!"
					invite.tooltip_text = r.get("message", "") if r.ok else r.message
				if not r.ok:
					_show_toast(r.message))
			row.add_child(invite)
	var remove := Button.new()
	remove.text = "⋯"
	remove.flat = true
	remove.tooltip_text = "Retirer de mes amis"
	remove.pressed.connect(func() -> void:
		if remove.text != "Retirer ?":
			remove.text = "Retirer ?"      # deuxième clic pour confirmer
			return
		var r: Dictionary = await Backend.remove_friend(f.user_id)
		if not r.ok:
			_show_toast(r.message))
	row.add_child(remove)
	return panel


# =========================================================================== hors ligne

func _start_solo() -> void:
	GameState.mode = "deathmatch"
	# Le match est complété par des bots pour atteindre 6 joueurs au moins.
	GameState.bot_count = 5
	get_tree().change_scene_to_file(GAME)


func _start_training() -> void:
	GameState.mode = "training"
	get_tree().change_scene_to_file(GAME)


# =========================================================================== écran d'attente

func _show_overlay(title: String) -> void:
	_close_overlay()
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


## Échec pendant l'écran d'attente : le message reste affiché jusqu'à FERMER.
func _overlay_error(message: String) -> void:
	if not is_instance_valid(_overlay):
		_show_toast(message)
		return
	var bar := _overlay.find_child("Bar", true, false) as ProgressBar
	if bar:
		bar.visible = false
	var step := _overlay.find_child("Step", true, false) as Label
	if step:
		step.text = message
		step.add_theme_color_override("font_color", UiTheme.RED)
		step.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		step.custom_minimum_size.x = 520
		var close := UiTheme.button("FERMER", true, UiTheme.RED, 46)
		close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		close.custom_minimum_size.x = 200
		close.pressed.connect(_close_overlay)
		step.get_parent().add_child(close)
		close.grab_focus()


func _close_overlay() -> void:
	if is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
