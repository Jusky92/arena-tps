class_name ChatPanel
extends PanelContainer
## Chat du menu principal : le groupe et les conversations avec les amis (service
## Real-time, à travers l'autoload Backend). Un onglet par conversation ouverte
## (bouton « Écrire » d'un ami), plus « GROUPE » quand le joueur en a un. Les
## messages non lus sont comptés sur les onglets.

signal close_requested

## Conversations ouvertes (user_id des amis) et onglet affiché, gardés d'un écran à
## l'autre (choix du spécialiste, partie).
static var open_friends: Array = []
static var current := ""
## Conversations dont l'historique est chargé, par compte : "user_id|ami".
static var _loaded := {}

var _tabs: HFlowContainer
var _scroll: ScrollContainer
var _lines: VBoxContainer
var _field: LineEdit
var _send: Button
var _hint: Label


func _ready() -> void:
	add_theme_stylebox_override("panel", UiTheme.box(Color(0.03, 0.04, 0.07, 0.96), Color(UiTheme.CYAN, 0.35), 1, 6, 14, 12))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)

	var header := HBoxContainer.new()
	header.add_child(UiTheme.title("CHAT", 18))
	header.add_child(UiTheme.spacer(Vector2.ZERO, true))
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.tooltip_text = "Fermer le chat"
	close.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(close)
	col.add_child(header)

	_tabs = HFlowContainer.new()
	_tabs.add_theme_constant_override("h_separation", 6)
	_tabs.add_theme_constant_override("v_separation", 6)
	col.add_child(_tabs)

	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", UiTheme.box(Color(1, 1, 1, 0.03), Color(0, 0, 0, 0), 0, 4, 10, 8))
	col.add_child(frame)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(_scroll)
	_lines = VBoxContainer.new()
	_lines.add_theme_constant_override("separation", 4)
	_lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lines.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lines.alignment = BoxContainer.ALIGNMENT_END
	_scroll.add_child(_lines)

	_hint = UiTheme.label("", 14, UiTheme.RED)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.visible = false
	col.add_child(_hint)

	var input := HBoxContainer.new()
	input.add_theme_constant_override("separation", 6)
	_field = LineEdit.new()
	_field.max_length = Backend.CHAT_MAX_LENGTH
	_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field.text_submitted.connect(func(_t: String) -> void: _submit())
	input.add_child(_field)
	_send = Button.new()
	_send.text = "Envoyer"
	_send.pressed.connect(_submit)
	input.add_child(_send)
	col.add_child(input)

	Backend.chat_changed.connect(_on_chat_changed)
	Backend.party_changed.connect(_refresh)
	Backend.friends_changed.connect(_refresh)
	visibility_changed.connect(_on_visibility_changed)
	_refresh()


func _exit_tree() -> void:
	Backend.chat_open = ""


## Affiche la conversation avec un ami (ouvre son onglet) ou celle du groupe.
func show_channel(channel: String) -> void:
	if channel != Backend.PARTY_CHANNEL and not channel in open_friends:
		open_friends.append(channel)
	current = channel
	_refresh()
	_field.grab_focus()


func _on_visibility_changed() -> void:
	Backend.chat_open = current if is_visible_in_tree() else ""
	if is_visible_in_tree():
		Backend.mark_chat_read(current)


func _on_chat_changed(channel: String) -> void:
	if channel == current:
		if is_visible_in_tree():
			Backend.mark_chat_read(channel)
		_fill_lines()
	_fill_tabs()


## Onglets valides (plus d'ami, plus de groupe : l'onglet disparaît), puis affichage.
func _refresh() -> void:
	if not is_instance_valid(_tabs):
		return
	var friend_ids: Array = Backend.friends.map(func(f): return f.user_id)
	open_friends = open_friends.filter(func(id): return id in friend_ids)
	var channels := _channels()
	if not current in channels:
		current = channels[0] if not channels.is_empty() else ""
	Backend.chat_open = current if is_visible_in_tree() else ""
	if is_visible_in_tree():
		Backend.mark_chat_read(current)     # la conversation affichée est lue
	_fill_tabs()
	_fill_lines()
	if not current.is_empty() and current != Backend.PARTY_CHANNEL:
		_load_history(current)


func _channels() -> Array:
	var list := []
	if not Backend.party.is_empty():
		list.append(Backend.PARTY_CHANNEL)
	return list + open_friends


func _fill_tabs() -> void:
	for c in _tabs.get_children():
		c.queue_free()
	for channel in _channels():
		var unread: int = Backend.unread.get(channel, 0)
		var title := "GROUPE" if channel == Backend.PARTY_CHANNEL else Backend.name_of(channel)
		var tab := Button.new()
		tab.text = title + ("  ·  %d" % unread if unread > 0 else "")
		tab.toggle_mode = true
		tab.button_pressed = channel == current
		tab.add_theme_font_size_override("font_size", 14)
		var color := UiTheme.CYAN if channel == current else (UiTheme.MAGENTA if unread > 0 else UiTheme.TEXT)
		for state in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color"]:
			tab.add_theme_color_override(state, color)
		tab.pressed.connect(func() -> void:
			current = channel
			_refresh())
		_tabs.add_child(tab)
		if channel != Backend.PARTY_CHANNEL:
			var close := Button.new()
			close.text = "✕"
			close.flat = true
			close.tooltip_text = "Fermer cette conversation"
			close.add_theme_font_size_override("font_size", 12)
			close.pressed.connect(func() -> void:
				open_friends.erase(channel)
				_refresh())
			_tabs.add_child(close)


func _fill_lines() -> void:
	for c in _lines.get_children():
		c.queue_free()
	_hint.visible = false
	var can_write := not current.is_empty()
	_field.editable = can_write
	_send.disabled = not can_write
	if current.is_empty():
		_field.placeholder_text = ""
		var empty := UiTheme.label("Crée un groupe, ou ouvre une conversation avec le bouton « Écrire » d'un ami (liste d'amis).", 15, UiTheme.MUTED)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_lines.add_child(empty)
		return
	var is_party := current == Backend.PARTY_CHANNEL
	_field.placeholder_text = "Message au groupe…" if is_party else "Message à %s…" % Backend.name_of(current)
	var messages: Array = Backend.chats.get(current, [])
	if messages.is_empty():
		var note := "Aucun message dans le groupe." if is_party else "Aucun message avec %s (gardés 90 jours)." % Backend.name_of(current)
		_lines.add_child(UiTheme.label(note, 15, UiTheme.MUTED))
	for m in messages:
		var mine: bool = m.from_user_id == Backend.user_id()
		_lines.add_child(MatchChat.message_line(Backend.name_of(m.from_user_id), UiTheme.CYAN if mine else UiTheme.YELLOW,
			m.body, 16, UiTheme.TEXT, Backend.chat_time(m.at)))
	_scroll_to_end()


func _load_history(friend_id: String) -> void:
	var key := Backend.user_id() + "|" + friend_id
	if _loaded.has(key):
		return
	_loaded[key] = true
	var r: Dictionary = await Backend.load_chat(friend_id)
	if not r.ok:
		_loaded.erase(key)
		if is_instance_valid(_hint) and current == friend_id:
			_show_error(r.message)


func _submit() -> void:
	var text := _field.text
	if current.is_empty() or text.strip_edges().is_empty():
		return
	var r: Dictionary = await Backend.send_chat(current, text)
	if not is_instance_valid(_field):
		return
	if r.ok:
		_field.text = ""
		_hint.visible = false
	else:
		_show_error(r.message)


func _show_error(message: String) -> void:
	_hint.text = message
	_hint.visible = true


func _scroll_to_end() -> void:
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
