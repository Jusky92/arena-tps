class_name LoadoutEditor
extends HBoxContainer
## Onglet CLASSES de l'accueil : le joueur crée jusqu'à 10 classes (équipements).
## Une classe = un nom, une arme principale, une arme secondaire et 2 grenades.
##
## À gauche la liste des classes (★ = classe équipée pour la prochaine partie), à
## droite la classe en cours d'édition. Chaque changement est enregistré tout de
## suite : copie locale (GameState) puis compte du joueur (Backend.save_loadouts).

var _list_box: VBoxContainer
var _name_field: LineEdit
var _primary_grid: GridContainer
var _secondary_grid: GridContainer
var _status: Label
var _equip_button: Button
var _delete_button: Button
var _editing := 0


func _ready() -> void:
	add_theme_constant_override("separation", 22)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editing = GameState.selected_loadout
	_build()
	_refresh()


# =========================================================================== construction

func _build() -> void:
	# Colonne de gauche : les classes.
	var left := UiTheme.panel()
	left.custom_minimum_size = Vector2(230, 0)
	add_child(left)
	var lcol := VBoxContainer.new()
	lcol.add_theme_constant_override("separation", 8)
	left.add_child(lcol)
	lcol.add_child(UiTheme.title("MES CLASSES", 22))
	var hint := UiTheme.label("Jusqu'à %d classes. ★ = classe équipée." % WeaponCatalog.MAX_LOADOUTS, 14, UiTheme.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lcol.add_child(hint)
	lcol.add_child(UiTheme.neon_line(UiTheme.CYAN, 1))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lcol.add_child(scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_list_box)

	# Partie droite : la classe éditée.
	var right := UiTheme.panel()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(right)
	var rscroll := ScrollContainer.new()
	rscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(rscroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)
	rscroll.add_child(col)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	name_row.add_child(UiTheme.label("NOM", 14, UiTheme.MUTED, true))
	_name_field = LineEdit.new()
	_name_field.max_length = WeaponCatalog.NAME_MAX_LENGTH
	_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_field.placeholder_text = "Nom de la classe"
	_name_field.text_submitted.connect(func(_t: String) -> void: _rename())
	_name_field.focus_exited.connect(_rename)
	name_row.add_child(_name_field)
	col.add_child(name_row)

	col.add_child(UiTheme.label("ARME PRINCIPALE", 15, UiTheme.CYAN, true))
	_primary_grid = _weapon_grid()
	col.add_child(_primary_grid)
	col.add_child(UiTheme.label("ARME SECONDAIRE", 15, UiTheme.CYAN, true))
	_secondary_grid = _weapon_grid()
	col.add_child(_secondary_grid)

	col.add_child(UiTheme.label("ÉQUIPEMENT", 15, UiTheme.CYAN, true))
	var gear := HBoxContainer.new()
	gear.add_theme_constant_override("separation", 10)
	var nade := TextureRect.new()
	nade.texture = UiIcons.GRENADE
	nade.custom_minimum_size = Vector2(28, 28)
	nade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	nade.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	nade.modulate = WeaponCatalog.GRENADE.tracer_color
	gear.add_child(nade)
	var g := WeaponCatalog.GRENADE
	gear.add_child(UiTheme.label("2 grenades  ·  %d dégâts au centre, rayon %d m  ·  touche G" % [g.splash_damage, int(g.splash_radius)], 16, UiTheme.TEXT))
	col.add_child(gear)

	col.add_child(UiTheme.spacer(Vector2(0, 6)))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	_equip_button = UiTheme.button("ÉQUIPER POUR JOUER", true, UiTheme.CYAN, 46)
	_equip_button.pressed.connect(func() -> void:
		GameState.select_loadout(_editing)
		Sfx.ui("ui_click")
		_refresh())
	buttons.add_child(_equip_button)
	_delete_button = UiTheme.button("SUPPRIMER", false, UiTheme.RED, 46)
	_delete_button.pressed.connect(_delete)
	buttons.add_child(_delete_button)
	col.add_child(buttons)
	_status = UiTheme.label("", 14, UiTheme.MUTED)
	col.add_child(_status)


func _weapon_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	return grid


## Carte d'arme : icône, nom et caractéristiques principales.
func _weapon_card(w: WeaponData, selected: bool) -> Button:
	var b := UiTheme.button("", selected, UiTheme.CYAN, 84)
	b.custom_minimum_size.x = 150
	b.clip_text = true
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.icon = UiIcons.weapon(w)
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", 60)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = "%s\n%s" % [w.display_name.to_upper(), _summary(w)]
	b.add_theme_font_size_override("font_size", 14)
	b.tooltip_text = _details(w)
	return b


static func _summary(w: WeaponData) -> String:
	match w.kind:
		WeaponData.Kind.MELEE:
			return "%d dégâts · corps à corps" % w.damage
		WeaponData.Kind.FLAME:
			return "%d x %d/s · brûlure · %d m" % [w.damage, int(w.fire_rate), int(w.max_range)]
		WeaponData.Kind.PROJECTILE:
			if w.slow_time > 0.0:
				return "ralentit · tache à l'écran"
			return "%d dégâts · zone %d m" % [w.damage, int(w.splash_radius)]
	var pellets := " x%d" % w.pellets if w.pellets > 1 else ""
	return "%d%s dégâts · %s/s · %d m" % [w.damage, pellets, str(snappedf(w.fire_rate, 0.1)), int(w.max_range)]


static func _details(w: WeaponData) -> String:
	var mag := "illimité" if w.unlimited() else "%d (rechargement %s s)" % [w.mag_size, str(snappedf(w.reload_time, 0.1))]
	return "%s\nChargeur : %s\nBonus tête : x%s" % [w.display_name, mag, str(w.headshot_multiplier)]


# =========================================================================== état

func _refresh() -> void:
	var loadouts: Array = GameState.loadouts
	_editing = clampi(_editing, 0, loadouts.size() - 1)
	var current: Dictionary = loadouts[_editing]

	for c in _list_box.get_children():
		c.queue_free()
	for i in loadouts.size():
		var l: Dictionary = loadouts[i]
		var b := UiTheme.button("%s%s" % ["★ " if i == GameState.selected_loadout else "", l.name], i == _editing, UiTheme.CYAN, 42)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func() -> void:
			_editing = i
			_refresh())
		_list_box.add_child(b)
	if loadouts.size() < WeaponCatalog.MAX_LOADOUTS:
		var add := UiTheme.button("+  NOUVELLE CLASSE", false, UiTheme.MAGENTA, 42)
		add.pressed.connect(_create)
		_list_box.add_child(add)

	_name_field.text = current.name
	_fill_grid(_primary_grid, WeaponCatalog.primaries(), current.primary, "primary")
	_fill_grid(_secondary_grid, WeaponCatalog.secondaries(), current.secondary, "secondary")
	_equip_button.disabled = _editing == GameState.selected_loadout
	_equip_button.text = "CLASSE ÉQUIPÉE" if _equip_button.disabled else "ÉQUIPER POUR JOUER"
	_delete_button.disabled = loadouts.size() <= 1


func _fill_grid(grid: GridContainer, weapons: Array[WeaponData], selected_id: String, key: String) -> void:
	for c in grid.get_children():
		c.queue_free()
	for w in weapons:
		var card := _weapon_card(w, w.id == selected_id)
		card.pressed.connect(func() -> void:
			_change(key, w.id)
			Sfx.ui("ui_click"))
		grid.add_child(card)


# =========================================================================== modifications

func _change(key: String, value: String) -> void:
	var list: Array = GameState.loadouts.duplicate(true)
	list[_editing][key] = value
	_save(list)


func _rename() -> void:
	var text := _name_field.text.strip_edges()
	if text.is_empty() or text == GameState.loadouts[_editing].name:
		_name_field.text = GameState.loadouts[_editing].name
		return
	_change("name", text)


func _create() -> void:
	var list: Array = GameState.loadouts.duplicate(true)
	if list.size() >= WeaponCatalog.MAX_LOADOUTS:
		return
	var base: Dictionary = WeaponCatalog.DEFAULT_LOADOUTS[list.size() % WeaponCatalog.DEFAULT_LOADOUTS.size()]
	list.append({"name": "Classe %d" % (list.size() + 1), "primary": base.primary, "secondary": base.secondary})
	_editing = list.size() - 1
	Sfx.ui("ui_open")
	_save(list)


func _delete() -> void:
	var list: Array = GameState.loadouts.duplicate(true)
	if list.size() <= 1:
		return
	list.remove_at(_editing)
	var selected := GameState.selected_loadout
	if selected > _editing or selected >= list.size():
		selected = maxi(selected - 1, 0)
	_editing = clampi(_editing, 0, list.size() - 1)
	Sfx.ui("ui_close")
	_save(list, selected)


## Enregistre : copie locale tout de suite, puis le compte (le statut dit si ça a marché).
func _save(list: Array, selected := -1) -> void:
	GameState.set_loadouts(list, selected)
	_refresh()
	_status.text = "Enregistrement…"
	_status.add_theme_color_override("font_color", UiTheme.MUTED)
	var r: Dictionary = await Backend.save_loadouts(GameState.loadouts)
	if not is_instance_valid(_status):
		return
	if r.ok:
		_status.text = "Enregistré sur ton compte." if not Backend.is_simulated() else "Enregistré sur ce PC (hors ligne)."
		_status.add_theme_color_override("font_color", UiTheme.GREEN)
	else:
		_status.text = "Gardé sur ce PC, mais pas sur ton compte : %s" % r.get("message", "erreur")
		_status.add_theme_color_override("font_color", UiTheme.YELLOW)
