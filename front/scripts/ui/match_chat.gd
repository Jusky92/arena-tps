class_name MatchChat
extends VBoxContainer
## Chat du salon et de la partie en ligne. Les messages passent par le serveur de
## jeu (Net.send_chat, Net.chat_received) et ne sont jamais enregistrés : ils
## disparaissent avec la connexion.
##
##   salon   (overlay = false) : historique et champ de saisie toujours affichés.
##   partie  (overlay = true)  : les messages s'effacent après LINE_TIME s. La partie
##           appelle open() sur la touche du chat (Inputs « chat ») ; Entrée envoie,
##           Échap ferme. `typing_changed` lui dit de couper les commandes du joueur.

signal typing_changed(typing: bool)

## Partie : durée d'affichage d'un message, puis fondu.
const LINE_TIME := 8.0
const FADE_TIME := 1.0
const OVERLAY_HEIGHT := 190.0

var overlay := false

var _scroll: ScrollContainer
var _lines: VBoxContainer
var _field: LineEdit
var _frame: PanelContainer
var _typing := false


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_frame = PanelContainer.new()
	_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_frame)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_frame.add_child(_scroll)
	_lines = VBoxContainer.new()
	_lines.add_theme_constant_override("separation", 2)
	_lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lines.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lines.alignment = BoxContainer.ALIGNMENT_END      # peu de messages : en bas, près du champ
	_scroll.add_child(_lines)

	_field = LineEdit.new()
	_field.max_length = Net.CHAT_MAX_LENGTH
	_field.placeholder_text = "Écrire à tous les joueurs du serveur…"
	_field.text_submitted.connect(_on_submitted)
	add_child(_field)

	if overlay:
		custom_minimum_size.y = OVERLAY_HEIGHT
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		_field.placeholder_text = "Message à tous  ·  Entrée envoie, Échap ferme"
		_field.visible = false
	else:
		_field.placeholder_text = "Écrire à tous les joueurs du salon…"
	_set_frame()

	for line in Net.chat_log:
		_add_line(line, false)
	Net.chat_received.connect(_add_line.bind(true))


func _exit_tree() -> void:
	for connection in Net.get_signal_connection_list("chat_received"):
		if connection.callable.get_object() == self:
			Net.chat_received.disconnect(connection.callable)


## Partie : ouvre le champ de saisie.
func open() -> void:
	if _typing or not overlay:
		return
	_typing = true
	_field.visible = true
	_field.text = ""
	_field.grab_focus()
	_set_frame()
	_scroll_to_end()
	typing_changed.emit(true)


## Partie : referme le champ (sans envoyer).
func close() -> void:
	if not _typing:
		return
	_typing = false
	_field.release_focus()
	_field.visible = false
	_set_frame()
	typing_changed.emit(false)


func is_typing() -> bool:
	return _typing


## Échap pendant la saisie : ferme le chat (partie) ou quitte le champ (salon),
## avant que la partie n'ouvre son menu pause ou que le salon ne se ferme.
func _input(event: InputEvent) -> void:
	if not _field.has_focus():
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		if overlay:
			close()
		else:
			_field.release_focus()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not overlay:
		return
	var now := Time.get_ticks_msec()
	for line in _lines.get_children():
		var at := int(line.get_meta("at", -1))
		var age := (now - at) / 1000.0
		line.modulate.a = 1.0 if _typing else (0.0 if at < 0 else clampf((LINE_TIME - age) / FADE_TIME, 0.0, 1.0))


func _on_submitted(text: String) -> void:
	if not text.strip_edges().is_empty():
		Net.send_chat(text)
	_field.text = ""
	if overlay:
		close()


## Fond seulement pendant la saisie en partie, pour ne pas cacher le jeu.
func _set_frame() -> void:
	var visible_bg := not overlay or _typing
	_frame.add_theme_stylebox_override("panel", UiTheme.box(
		Color(0.02, 0.03, 0.05, 0.75 if overlay else 0.5) if visible_bg else Color(0, 0, 0, 0),
		Color(UiTheme.CYAN, 0.25) if visible_bg else Color(0, 0, 0, 0), 1, 4, 10, 6))


func _add_line(line: Dictionary, fresh: bool) -> void:
	var mine: bool = line.peer_id == Net.my_id()
	var label := message_line(line.name, UiTheme.CYAN if mine else UiTheme.YELLOW, line.text, 16)
	# Les anciens messages (avant d'arriver sur cette scène) ne s'affichent pas en partie.
	label.set_meta("at", Time.get_ticks_msec() if fresh else -1)
	_lines.add_child(label)
	while _lines.get_child_count() > Net.CHAT_KEEP:
		_lines.get_child(0).free()
	_scroll_to_end()


func _scroll_to_end() -> void:
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


## Une ligne de chat « Pseudo : texte » : le pseudo en couleur, le texte tel quel
## (pas de BBCode : un joueur ne doit pas pouvoir mettre en forme son message).
## `prefix` (l'heure, dans le menu) est écrit avant, en gris.
static func message_line(author: String, color: Color, text: String, size := 16, text_color := UiTheme.TEXT, prefix := "") -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = false
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("normal_font_size", size)
	label.add_theme_font_override("bold_font", UiTheme.FONT_BOLD)
	label.add_theme_font_size_override("bold_font_size", size)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	if not prefix.is_empty():
		label.push_color(UiTheme.MUTED)
		label.add_text(prefix + "  ")
		label.pop()
	label.push_bold()
	label.push_color(color)
	label.add_text(author)
	label.pop()
	label.pop()
	label.push_color(text_color)
	label.add_text(" : " + text)
	label.pop()
	return label
