extends CanvasLayer
## Interface de la partie (en plus du HUD du joueur) :
##   - chronomètre et meneur en haut au centre ;
##   - fil des éliminations en haut à droite ;
##   - bannière "ÉLIMINATION" quand le joueur local élimine quelqu'un ;
##   - tableau des scores (maintenir Tab) ;
##   - écran de fin de partie avec podium et classement final.
## Mise en page dans scenes/ui/match_ui.tscn ; une ligne du fil = kill_feed_entry.tscn,
## une ligne du tableau = scoreboard_row.tscn.

signal play_again
signal back_to_menu

const FeedEntryScene := preload("res://scenes/ui/kill_feed_entry.tscn")
const RowScene := preload("res://scenes/ui/scoreboard_row.tscn")
const MAX_FEED := 6
const FEED_TIME := 5.0
const CELLS := ["Rank", "PlayerName", "ClassName", "Kills", "Deaths", "KD", "Streak", "Ping"]
const PODIUM_COLORS := [Color(1.0, 0.84, 0.25), Color(0.78, 0.84, 0.92), Color(0.86, 0.55, 0.32)]

@onready var _timer_chip: Control = %TimerChip
@onready var _timer_label: Label = %Timer
@onready var _leader_label: Label = %Leader
@onready var _feed: VBoxContainer = %Feed
@onready var _banner: Label = %Banner
@onready var _scoreboard: Control = %Scoreboard
@onready var _scoreboard_title: Label = %Subtitle
@onready var _scoreboard_rows: VBoxContainer = %BoardRows
@onready var _end_screen: Control = %EndScreen

var _banner_tween: Tween


func _ready() -> void:
	%Again.pressed.connect(func() -> void: play_again.emit())
	%Menu.pressed.connect(func() -> void: back_to_menu.emit())
	for b: Button in [%Again, %Menu]:
		UiTheme.add_hover_feedback(b)


## Affiche le temps restant (secondes) et le meneur.
func set_time(seconds: float, leader_name: String, leader_kills: int) -> void:
	var s := maxi(int(ceil(seconds)), 0)
	_timer_label.text = "%d:%02d" % [s / 60, s % 60]
	_timer_label.add_theme_color_override("font_color", UiTheme.RED if s <= 15 else Color.WHITE)
	_leader_label.text = "MENEUR : %s (%d)" % [leader_name, leader_kills] if leader_kills > 0 else "MATCH À MORT"


func hide_timer() -> void:
	_timer_chip.visible = false
	_leader_label.text = "ENTRAÎNEMENT · ÉCHAP POUR QUITTER"


## Ajoute une ligne "tueur [arme] victime" au fil des éliminations.
func add_kill(killer: String, victim: String, weapon: String, killer_local: bool, victim_local: bool) -> void:
	var entry: PanelContainer = FeedEntryScene.instantiate()
	_feed.add_child(entry)
	if _feed.get_child_count() > MAX_FEED:
		_feed.get_child(0).queue_free()
	var border := UiTheme.CYAN if killer_local else (UiTheme.RED if victim_local else Color(1, 1, 1, 0.12))
	var style: StyleBoxFlat = entry.get_theme_stylebox("panel").duplicate()
	style.border_color = border
	if killer_local:
		style.bg_color = Color(UiTheme.CYAN, 0.14)
	entry.add_theme_stylebox_override("panel", style)

	var killer_label: Label = entry.get_node("%Killer")
	killer_label.text = killer
	killer_label.add_theme_color_override("font_color", UiTheme.CYAN if killer_local else Color.WHITE)
	var victim_label: Label = entry.get_node("%Victim")
	victim_label.text = victim
	victim_label.add_theme_color_override("font_color", UiTheme.RED if victim_local else Color.WHITE)
	# Icône de l'arme si on la connaît, sinon le nom (ex. "Arène").
	var icon := UiIcons.weapon_by_name(weapon)
	var icon_rect: TextureRect = entry.get_node("%WeaponIcon")
	icon_rect.texture = icon if icon else UiIcons.SKULL
	icon_rect.custom_minimum_size = Vector2(44, 22) if icon else Vector2(22, 22)
	icon_rect.modulate = Color(UiTheme.CYAN, 0.9) if killer_local else Color(1, 1, 1, 0.8)
	var weapon_text: Label = entry.get_node("%WeaponText")
	weapon_text.text = "[%s]" % weapon
	weapon_text.visible = icon == null
	# Arrive en glissant depuis la droite, puis s'efface.
	entry.modulate.a = 0.0
	var tween := entry.create_tween()
	tween.tween_property(entry, "modulate:a", 1.0, 0.15)
	tween.tween_interval(FEED_TIME)
	tween.tween_property(entry, "modulate:a", 0.0, 0.6)
	tween.tween_callback(entry.queue_free)


func show_banner(text: String, color := UiTheme.MAGENTA) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.modulate.a = 1.0
	_banner.scale = Vector2.ONE * 1.3
	if _banner_tween:
		_banner_tween.kill()
	_banner_tween = _banner.create_tween()
	_banner_tween.tween_property(_banner, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_interval(1.0)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.4)


## Tableau des scores pendant la partie.
func show_scoreboard(rows: Array, visible_now: bool, subtitle: String) -> void:
	_scoreboard.visible = visible_now
	if visible_now:
		_scoreboard_title.text = subtitle
		_fill_rows(_scoreboard_rows, rows)


## Écran de fin : podium, classement final, place du joueur, boutons.
func show_end_screen(rows: Array, local_rank: int, subtitle: String) -> void:
	_scoreboard.visible = false
	_end_screen.visible = true
	var won := local_rank == 1
	var headline: Label = %Headline
	headline.text = "VICTOIRE" if won else "PARTIE TERMINÉE"
	headline.add_theme_color_override("font_color", UiTheme.YELLOW if won else UiTheme.CYAN)
	(%Place as Label).text = "Tu termines %s sur %d · Vainqueur : %s" % [_ordinal(local_rank), rows.size(), rows[0].name]
	(%EndSubtitle as Label).text = subtitle
	_fill_podium(rows)
	var end_rows: VBoxContainer = %EndRows
	_fill_rows(end_rows, rows)

	# Entrée animée : le titre puis les lignes, une à une.
	_end_screen.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_end_screen, "modulate:a", 1.0, 0.3)
	headline.pivot_offset = headline.size / 2.0
	headline.scale = Vector2.ONE * 1.2
	tween.parallel().tween_property(headline, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	for row: Control in end_rows.get_children():
		row.modulate.a = 0.0
		tween.tween_property(row, "modulate:a", 1.0, 0.08)
	%Again.grab_focus()


func _fill_podium(rows: Array) -> void:
	var podium: HBoxContainer = %Podium
	for c in podium.get_children():
		podium.remove_child(c)
		c.queue_free()
	# Ordre d'affichage : 2e, 1er, 3e (le premier au centre, plus haut).
	for rank in [2, 1, 3]:
		if rank > rows.size():
			continue
		_podium_card(rows[rank - 1], rank)


## Carte du podium, ajoutée directement dans %Podium.
func _podium_card(data, rank: int) -> void:
	var color: Color = PODIUM_COLORS[rank - 1]
	var card := PanelContainer.new()
	card.theme_type_variation = &"HudChip"
	%Podium.add_child(card)
	var style: StyleBoxFlat = card.get_theme_stylebox("panel").duplicate()
	style.border_color = color
	style.shadow_color = Color(color, 0.25)
	style.bg_color = Color(0.03, 0.04, 0.08, 0.92).lerp(UiTheme.CYAN if data.local else color, 0.12)
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", style)
	card.custom_minimum_size = Vector2(200, 130 if rank == 1 else 104)
	card.size_flags_vertical = Control.SIZE_SHRINK_END
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	card.add_child(col)
	var place := UiTheme.title(_ordinal(rank).to_upper(), 30 if rank == 1 else 22, color)
	place.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(place)
	var name_label := UiTheme.label(data.name, 20, UiTheme.CYAN if data.local else Color.WHITE, true)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(name_label)
	var kills := UiTheme.label("%d élim. · %s" % [data.kills, data.cls], 14, UiTheme.MUTED)
	kills.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(kills)


## Remplit un tableau (en-tête + une ligne par joueur). Les lignes existantes sont
## réutilisées : le tableau est rafraîchi à chaque image tant que Tab est maintenu.
func _fill_rows(box: VBoxContainer, rows: Array) -> void:
	while box.get_child_count() > rows.size() + 1:
		var extra := box.get_child(box.get_child_count() - 1)
		box.remove_child(extra)
		extra.queue_free()
	while box.get_child_count() < rows.size() + 1:
		box.add_child(RowScene.instantiate())
	_apply_row(box.get_child(0), ["#", "JOUEUR", "CLASSE", "ÉLIM.", "MORTS", "K/D", "SÉRIE", "PING"], null)
	for i in rows.size():
		_apply_row(box.get_child(i + 1), [str(i + 1), rows[i].name, rows[i].cls, str(rows[i].kills), str(rows[i].deaths),
			"%.2f" % (float(rows[i].kills) / maxf(rows[i].deaths, 1)), str(rows[i].best_streak), rows[i].ping], rows[i])


## Met à jour une ligne du tableau (data = null pour l'en-tête).
func _apply_row(row: PanelContainer, values: Array, data) -> void:
	var header: bool = data == null
	var local: bool = data != null and data.local
	var bg := Color(0, 0, 0, 0)
	var border := Color(0, 0, 0, 0)
	if local:
		bg = Color(UiTheme.CYAN, 0.16)
		border = UiTheme.CYAN
	elif not header:
		bg = Color(1, 1, 1, 0.035)
	var style := UiTheme.box(bg, border, 1 if border.a > 0 else 0, 3, 12, 4)
	if local:
		style.border_width_left = 3
	row.add_theme_stylebox_override("panel", style)
	for i in CELLS.size():
		var l: Label = row.get_node("%" + CELLS[i])
		l.text = str(values[i])
		var color := UiTheme.MUTED if header else Color.WHITE
		if not header and i == 2:
			color = data.class_color
		if not header and i == 0 and int(values[0]) <= 3:
			color = PODIUM_COLORS[int(values[0]) - 1]
		l.add_theme_color_override("font_color", color)
		l.add_theme_font_size_override("font_size", 13 if header else 18)
		if header or i == 1:
			l.add_theme_font_override("font", UiTheme.FONT_BOLD)
		else:
			l.remove_theme_font_override("font")


func _ordinal(rank: int) -> String:
	return "1er" if rank == 1 else "%de" % rank
