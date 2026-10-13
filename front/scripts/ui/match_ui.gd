extends CanvasLayer
## Interface de la partie (en plus du HUD du joueur) :
##   - chronomètre et meneur en haut au centre ;
##   - fil des éliminations en haut à droite ;
##   - bannière "ÉLIMINATION" quand le joueur local élimine quelqu'un ;
##   - tableau des scores (maintenir Tab) ;
##   - écran de fin de partie avec le classement final.

signal play_again
signal back_to_menu

var _timer_label: Label
var _leader_label: Label
var _feed: VBoxContainer
var _banner: Label
var _scoreboard: Control
var _scoreboard_rows: VBoxContainer
var _scoreboard_title: Label
var _end_screen: Control


func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.get_theme()
	add_child(root)

	# Chronomètre.
	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.offset_left = -160
	top.offset_right = 160
	top.offset_top = 8
	top.alignment = BoxContainer.ALIGNMENT_BEGIN
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var timer_panel := PanelContainer.new()
	timer_panel.add_theme_stylebox_override("panel", UiTheme.box(Color(0.02, 0.03, 0.06, 0.75), Color(UiTheme.CYAN, 0.4), 1, 6, 18, 2))
	timer_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	timer_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_timer_label = UiTheme.title("3:00", 26, Color.WHITE)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_panel.add_child(_timer_label)
	top.add_child(timer_panel)
	_leader_label = UiTheme.label("", 16, Color(1, 1, 1, 0.9), true)
	_leader_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_leader_label.add_theme_constant_override("outline_size", 6)
	_leader_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	top.add_child(_leader_label)

	# Fil des éliminations.
	_feed = VBoxContainer.new()
	_feed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_feed.offset_left = -430
	_feed.offset_right = -16
	_feed.offset_top = 40
	_feed.add_theme_constant_override("separation", 4)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_feed)

	# Bannière.
	_banner = UiTheme.title("", 28, UiTheme.MAGENTA)
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.offset_left = -300
	_banner.offset_right = 300
	_banner.offset_top = 70
	_banner.offset_bottom = 120
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_constant_override("outline_size", 8)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_banner.modulate.a = 0.0
	root.add_child(_banner)

	# Tableau des scores.
	_scoreboard = _build_board_panel()
	_scoreboard.visible = false
	root.add_child(_scoreboard)


## Affiche le temps restant (secondes) et le meneur.
func set_time(seconds: float, leader_name: String, leader_kills: int) -> void:
	var s := maxi(int(ceil(seconds)), 0)
	_timer_label.text = "%d:%02d" % [s / 60, s % 60]
	_timer_label.add_theme_color_override("font_color", UiTheme.RED if s <= 15 else Color.WHITE)
	_leader_label.text = "MENEUR : %s (%d)" % [leader_name, leader_kills] if leader_kills > 0 else "MATCH À MORT"


func hide_timer() -> void:
	_timer_label.get_parent().visible = false
	_leader_label.text = "ENTRAÎNEMENT · ÉCHAP POUR QUITTER"


## Ajoute une ligne "tueur [arme] victime" au fil des éliminations.
func add_kill(killer: String, victim: String, weapon: String, killer_local: bool, victim_local: bool) -> void:
	var panel := PanelContainer.new()
	var border := UiTheme.CYAN if killer_local else (UiTheme.RED if victim_local else Color(1, 1, 1, 0.1))
	panel.add_theme_stylebox_override("panel", UiTheme.box(Color(0.02, 0.03, 0.06, 0.7), border, 1, 4, 10, 3))
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	row.add_child(UiTheme.label(killer, 17, UiTheme.CYAN if killer_local else Color.WHITE, true))
	row.add_child(UiTheme.label("[%s]" % weapon, 15, UiTheme.MUTED))
	row.add_child(UiTheme.label(victim, 17, UiTheme.RED if victim_local else Color.WHITE, true))
	_feed.add_child(panel)
	if _feed.get_child_count() > 6:
		_feed.get_child(0).queue_free()
	var tween := panel.create_tween()
	tween.tween_interval(5.0)
	tween.tween_property(panel, "modulate:a", 0.0, 0.6)
	tween.tween_callback(panel.queue_free)


func show_banner(text: String, color := UiTheme.MAGENTA) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.modulate.a = 1.0
	_banner.scale = Vector2.ONE * 1.25
	_banner.pivot_offset = Vector2(300, 25)
	var tween := _banner.create_tween().set_parallel()
	tween.tween_property(_banner, "scale", Vector2.ONE, 0.2)
	tween.chain().tween_interval(1.0)
	tween.chain().tween_property(_banner, "modulate:a", 0.0, 0.4)


## Tableau des scores pendant la partie.
func show_scoreboard(rows: Array, visible_now: bool, subtitle: String) -> void:
	_scoreboard.visible = visible_now
	if visible_now:
		_scoreboard_title.text = subtitle
		_fill_rows(_scoreboard_rows, rows)


## Écran de fin : classement final, place du joueur, boutons.
func show_end_screen(rows: Array, local_rank: int, subtitle: String) -> void:
	_scoreboard.visible = false
	_end_screen = ColorRect.new()
	(_end_screen as ColorRect).color = Color(0.01, 0.015, 0.03, 0.82)
	_end_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	get_child(0).add_child(_end_screen)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_screen.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	center.add_child(col)

	var won := local_rank == 1
	var headline := UiTheme.title("VICTOIRE" if won else "PARTIE TERMINÉE", 52, UiTheme.YELLOW if won else UiTheme.CYAN)
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(headline)
	var place := UiTheme.label("Tu termines %s sur %d · Vainqueur : %s" % [_ordinal(local_rank), rows.size(), rows[0].name], 22, Color.WHITE, true)
	place.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(place)
	var sub := UiTheme.label(subtitle, 16, UiTheme.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	var board := UiTheme.panel()
	board.custom_minimum_size = Vector2(760, 0)
	var rows_box := VBoxContainer.new()
	rows_box.add_theme_constant_override("separation", 3)
	board.add_child(rows_box)
	_fill_rows(rows_box, rows)
	col.add_child(board)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	var again := UiTheme.button("REJOUER", true, UiTheme.CYAN, 48)
	again.custom_minimum_size.x = 220
	again.pressed.connect(func() -> void: play_again.emit())
	buttons.add_child(again)
	var menu := UiTheme.button("MENU PRINCIPAL", false, UiTheme.CYAN, 48)
	menu.custom_minimum_size.x = 220
	menu.pressed.connect(func() -> void: back_to_menu.emit())
	buttons.add_child(menu)
	col.add_child(buttons)
	again.grab_focus()


func _build_board_panel() -> Control:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var board := UiTheme.panel(Color(0.03, 0.04, 0.08, 0.92), Color(UiTheme.CYAN, 0.45))
	board.custom_minimum_size = Vector2(780, 0)
	center.add_child(board)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	board.add_child(col)
	var header := HBoxContainer.new()
	header.add_child(UiTheme.title("TABLEAU DES SCORES", 22))
	header.add_child(UiTheme.spacer(Vector2.ZERO, true))
	_scoreboard_title = UiTheme.label("", 16, UiTheme.MUTED, true)
	header.add_child(_scoreboard_title)
	col.add_child(header)
	col.add_child(UiTheme.neon_line(UiTheme.CYAN, 1))
	_scoreboard_rows = VBoxContainer.new()
	_scoreboard_rows.add_theme_constant_override("separation", 3)
	col.add_child(_scoreboard_rows)
	return center


const COLUMNS := [["#", 0.5], ["JOUEUR", 2.6], ["CLASSE", 1.3], ["ÉLIM.", 0.9], ["MORTS", 0.9], ["K/D", 0.8], ["SÉRIE", 0.8], ["PING", 0.8]]


func _fill_rows(box: VBoxContainer, rows: Array) -> void:
	for c in box.get_children():
		c.queue_free()
	box.add_child(_row(COLUMNS.map(func(c): return c[0]), true, null))
	for i in rows.size():
		box.add_child(_row([str(i + 1), rows[i].name, rows[i].cls, str(rows[i].kills), str(rows[i].deaths),
			"%.2f" % (float(rows[i].kills) / maxf(rows[i].deaths, 1)), str(rows[i].best_streak), rows[i].ping], false, rows[i]))


func _row(values: Array, header: bool, data) -> Control:
	var panel := PanelContainer.new()
	var bg := Color(0, 0, 0, 0)
	var border := Color(0, 0, 0, 0)
	if data and data.local:
		bg = Color(UiTheme.CYAN, 0.16)
		border = UiTheme.CYAN
	elif not header:
		bg = Color(1, 1, 1, 0.035)
	panel.add_theme_stylebox_override("panel", UiTheme.box(bg, border, 1 if border.a > 0 else 0, 4, 12, 4))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	for i in values.size():
		var color := UiTheme.MUTED if header else Color.WHITE
		if data and i == 2:
			color = data.class_color
		if data and i == 0 and int(values[0]) == 1:
			color = UiTheme.YELLOW
		var l := UiTheme.label(str(values[i]), 13 if header else 18, color, header or i == 1)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_stretch_ratio = COLUMNS[i][1]
		row.add_child(l)
	return panel


func _ordinal(rank: int) -> String:
	return "1er" if rank == 1 else "%de" % rank
