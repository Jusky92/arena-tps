extends Control
## Écran de démarrage : connexion, inscription, vérification de l'e-mail (code à
## 6 chiffres) et mot de passe oublié (code puis nouveau mot de passe), auprès du
## service Auth via le BFF (voir scripts/backend/).
##
## L'adresse du back se règle ici. « Jouer hors ligne » passe au back simulé :
## aucune connexion, on joue en LAN par adresse IP.

const MAIN_MENU := "res://scenes/main_menu.tscn"

var _card_content: VBoxContainer
var _error_label: Label
var _busy := false
var _email_for_code := ""
var _code_fields: Array[LineEdit] = []
var _submit: Callable = func() -> void: pass
var _host_field: LineEdit


func _ready() -> void:
	theme = UiTheme.get_theme()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(UiTheme.background())

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48 if side in ["left", "right"] else 36)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	margin.add_child(row)

	row.add_child(_build_showcase())
	row.add_child(UiTheme.spacer(Vector2.ZERO, true))
	row.add_child(_build_card())
	_show_login()


# --------------------------------------------------------------------------- vitrine

func _build_showcase() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var logo := HBoxContainer.new()
	logo.add_theme_constant_override("separation", 14)
	logo.add_child(UiTheme.title("ARENA", 64, Color.WHITE))
	var kana := UiTheme.label("ネオ江戸", 26, UiTheme.CYAN)
	kana.add_theme_font_override("font", JapaneseFont.font())
	logo.add_child(kana)
	var tps := UiTheme.title("TPS", 64, UiTheme.CYAN)
	tps.add_theme_constant_override("outline_size", 0)
	logo.add_child(tps)
	box.add_child(logo)
	box.add_child(UiTheme.label("MULTIJOUEUR  ·  CHACUN POUR SOI  ·  8 JOUEURS", 18, UiTheme.MAGENTA, true))
	box.add_child(UiTheme.spacer(Vector2(0, 6)))
	box.add_child(UiTheme.label("Projet Architecture SI · M2 · CFA INSTA", 16, UiTheme.MUTED))

	var preview := CharacterPreview.new()
	preview.pose_names = ["Repos", "Visée", "Course"]
	preview.show_pose_label = false
	box.add_child(preview)
	var designs := ["assassin", "tank", "tireur"]
	var weapons := [WeaponData.Model.SMG, WeaponData.Model.SHOTGUN, WeaponData.Model.SNIPER]
	var pick := randi() % designs.size()
	preview.setup(designs[pick], weapons[pick], Vector2i(460, 420), 4.0, 1.0)
	return box


# --------------------------------------------------------------------------- carte

func _build_card() -> Control:
	var card := UiTheme.panel(Color(0.04, 0.055, 0.09, 0.92), Color(UiTheme.CYAN, 0.35))
	card.custom_minimum_size = Vector2(430, 0)
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_card_content = VBoxContainer.new()
	_card_content.add_theme_constant_override("separation", 10)
	card.add_child(_card_content)
	return card


func _clear_card() -> void:
	for child in _card_content.get_children():
		child.queue_free()
	_code_fields.clear()
	_error_label = UiTheme.label("", 16, UiTheme.RED)
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_label.visible = false


func _tabs(active: String) -> Control:
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	for tab in [["CONNEXION", "login"], ["INSCRIPTION", "register"]]:
		var b := Button.new()
		b.text = tab[0]
		b.toggle_mode = true
		b.button_pressed = tab[1] == active
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 40)
		b.add_theme_font_override("font", UiTheme.title_font())
		b.add_theme_font_size_override("font_size", 14)
		if tab[1] == active:
			b.add_theme_stylebox_override("normal", UiTheme.box(Color(UiTheme.CYAN, 0.15), UiTheme.CYAN, 1, 4, 10, 8))
			b.add_theme_color_override("font_color", UiTheme.CYAN)
		b.pressed.connect(_show_login if tab[1] == "login" else _show_register)
		tabs.add_child(b)
	return tabs


func _field(placeholder: String, secret := false) -> LineEdit:
	var f := LineEdit.new()
	f.placeholder_text = placeholder
	f.secret = secret
	f.custom_minimum_size = Vector2(0, 46)
	f.text_submitted.connect(func(_t: String) -> void: _submit.call())
	return f


func _field_label(text: String) -> Label:
	return UiTheme.label(text.to_upper(), 13, UiTheme.MUTED, true)


func _link(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.add_theme_color_override("font_color", UiTheme.CYAN)
	b.add_theme_color_override("font_hover_color", UiTheme.MAGENTA)
	b.add_theme_font_size_override("font_size", 16)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(action)
	return b


func _footer() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	if Backend.is_simulated():
		row.add_child(UiTheme.dot(UiTheme.YELLOW, 8))
		row.add_child(UiTheme.label("Hors ligne (back simulé) · version %s" % Backend.BUILD_VERSION, 14, UiTheme.MUTED))
	else:
		row.add_child(UiTheme.dot(UiTheme.CYAN, 8))
		row.add_child(UiTheme.label("Back : %s · version %s" % [Backend.host, Backend.BUILD_VERSION], 14, UiTheme.MUTED))
	return row


## Adresse du back (vrai back), ou rappel du mode hors ligne, avec le lien pour changer.
func _back_section() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	if Backend.is_simulated():
		box.add_child(UiTheme.label("Mode hors ligne : n'importe quel identifiant est accepté.", 15, UiTheme.YELLOW))
		box.add_child(_link("Se connecter au vrai back", func() -> void:
			Backend.use("bff")
			_show_login()))
		_host_field = null
	else:
		box.add_child(_field_label("Adresse du back"))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_host_field = _field("localhost ou 192.168.1.20")
		_host_field.text = Backend.host
		_host_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(_host_field)
		box.add_child(row)
		box.add_child(_link("Jouer hors ligne (back simulé, LAN uniquement)", func() -> void:
			Backend.use("simulated")
			_show_login()))
	return box


## Applique l'adresse du back saisie, si elle a changé.
func _apply_host() -> void:
	if _host_field and is_instance_valid(_host_field):
		var typed := _host_field.text.strip_edges()
		if not typed.is_empty() and typed != Backend.host:
			Backend.use("bff", typed)


# --------------------------------------------------------------------------- vues

func _show_login() -> void:
	_clear_card()
	_card_content.add_child(_tabs("login"))
	_card_content.add_child(UiTheme.spacer(Vector2(0, 4)))
	_card_content.add_child(UiTheme.title("CONTENT DE TE REVOIR", 20))
	_card_content.add_child(UiTheme.label("Connecte-toi pour rejoindre l'arène.", 17, UiTheme.MUTED))
	_card_content.add_child(_field_label("E-mail ou pseudo"))
	var ident := _field("julien@exemple.fr ou Julien")
	_card_content.add_child(ident)
	_card_content.add_child(_field_label("Mot de passe"))
	var password := _field("••••••••", true)
	_card_content.add_child(password)
	_card_content.add_child(_link("Mot de passe oublié ?", _show_reset))
	_card_content.add_child(_error_label)
	var go := UiTheme.button("SE CONNECTER", true)
	_card_content.add_child(go)
	_card_content.add_child(UiTheme.neon_line(UiTheme.CYAN, 1))
	_card_content.add_child(_back_section())
	_card_content.add_child(_footer())
	_submit = func() -> void:
		_apply_host()
		_run(go, "CONNEXION…", func() -> Dictionary: return await Backend.login(ident.text, password.text),
			func(_r: Dictionary) -> void: _enter_game(),
			func(r: Dictionary) -> bool:
				# Compte pas encore vérifié : on passe à la saisie du code. Connecté avec
				# son pseudo, le joueur devra aussi donner son e-mail (le code y est envoyé).
				if r.get("error") == "email_not_verified":
					var typed := ident.text.strip_edges()
					_show_verify(typed if typed.contains("@") else "")
					_show_error(r.message, UiTheme.YELLOW)
					return true
				return false)
	go.pressed.connect(func() -> void: _submit.call())
	ident.grab_focus.call_deferred()


func _show_register() -> void:
	_clear_card()
	_card_content.add_child(_tabs("register"))
	_card_content.add_child(UiTheme.spacer(Vector2(0, 4)))
	_card_content.add_child(UiTheme.title("CRÉER UN COMPTE", 20))
	_card_content.add_child(_field_label("Pseudo"))
	var pseudo := _field("3 à 20 caractères : lettres, chiffres, _")
	_card_content.add_child(pseudo)
	_card_content.add_child(_field_label("E-mail"))
	var email := _field("toi@exemple.fr")
	_card_content.add_child(email)
	_card_content.add_child(_field_label("Mot de passe"))
	var password := _field("8 caractères minimum", true)
	_card_content.add_child(password)
	_card_content.add_child(_error_label)
	var go := UiTheme.button("CRÉER MON COMPTE", true, UiTheme.MAGENTA)
	_card_content.add_child(go)
	_card_content.add_child(UiTheme.label("Un code de vérification à 6 chiffres te sera envoyé par e-mail.", 15, UiTheme.MUTED))
	_card_content.add_child(UiTheme.neon_line(UiTheme.MAGENTA, 1))
	_card_content.add_child(_back_section())
	_card_content.add_child(_footer())
	_submit = func() -> void:
		_apply_host()
		_run(go, "CRÉATION…", func() -> Dictionary: return await Backend.register(pseudo.text, email.text, password.text),
			func(_r: Dictionary) -> void: _show_verify(email.text))
	go.pressed.connect(func() -> void: _submit.call())
	pseudo.grab_focus.call_deferred()


## `email` vide : le joueur s'est connecté avec son pseudo, on lui demande l'e-mail du compte.
func _show_verify(email: String) -> void:
	_email_for_code = email
	_clear_card()
	_card_content.add_child(UiTheme.title("VÉRIFIE TON E-MAIL", 20))
	var text := "Saisis le code à 6 chiffres envoyé à\n%s (valable 15 minutes)." % email if not email.is_empty() \
		else "Saisis l'e-mail de ton compte et le code à 6 chiffres qui y a été envoyé (valable 15 minutes)."
	var info := UiTheme.label(text, 17, UiTheme.MUTED)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_content.add_child(info)
	var email_field: LineEdit = null
	if email.is_empty():
		_card_content.add_child(_field_label("E-mail du compte"))
		email_field = _field("toi@exemple.fr")
		email_field.text_changed.connect(func(t: String) -> void: _email_for_code = t.strip_edges())
		_card_content.add_child(email_field)
	var digits := HBoxContainer.new()
	digits.add_theme_constant_override("separation", 8)
	digits.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in 6:
		var f := LineEdit.new()
		f.max_length = 1
		f.alignment = HORIZONTAL_ALIGNMENT_CENTER
		f.custom_minimum_size = Vector2(52, 60)
		f.add_theme_constant_override("minimum_character_width", 1)
		f.add_theme_font_override("font", UiTheme.title_font())
		f.add_theme_font_size_override("font_size", 26)
		f.text_changed.connect(_on_digit_changed.bind(i))
		f.text_submitted.connect(func(_t: String) -> void: _submit.call())
		digits.add_child(f)
		_code_fields.append(f)
	_card_content.add_child(digits)
	if Backend.is_simulated():
		_card_content.add_child(UiTheme.label("Hors ligne : n'importe quels 6 chiffres conviennent.", 14, UiTheme.YELLOW))
	else:
		_card_content.add_child(UiTheme.label("En local, les e-mails arrivent dans Mailpit : http://localhost:8025", 14, UiTheme.MUTED))
	_card_content.add_child(_error_label)
	var go := UiTheme.button("VALIDER", true)
	_card_content.add_child(go)
	var links := HBoxContainer.new()
	links.add_child(_link("Renvoyer le code", func() -> void:
		var r: Dictionary = await Backend.resend_code(_email_for_code)
		_show_error(r.message, UiTheme.GREEN)))
	links.add_child(UiTheme.spacer(Vector2.ZERO, true))
	links.add_child(_link("Retour", _show_register))
	_card_content.add_child(links)
	_submit = func() -> void:
		var code := ""
		for f in _code_fields:
			code += f.text
		_run(go, "VÉRIFICATION…", func() -> Dictionary: return await Backend.verify_email(_email_for_code, code),
			func(_r: Dictionary) -> void: _enter_game())
	go.pressed.connect(func() -> void: _submit.call())
	(email_field if email_field else _code_fields[0]).grab_focus.call_deferred()


func _on_digit_changed(text: String, index: int) -> void:
	if text.length() == 1 and not text.is_valid_int():
		_code_fields[index].text = ""
		return
	if text.length() == 1 and index < 5:
		_code_fields[index + 1].grab_focus()
	elif text.length() == 1 and index == 5:
		_submit.call()


func _show_reset() -> void:
	_clear_card()
	_card_content.add_child(UiTheme.title("MOT DE PASSE OUBLIÉ", 20))
	var info := UiTheme.label("Indique ton e-mail : tu recevras un code pour choisir un nouveau mot de passe.", 17, UiTheme.MUTED)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_content.add_child(info)
	_card_content.add_child(_field_label("E-mail"))
	var email := _field("toi@exemple.fr")
	_card_content.add_child(email)
	_card_content.add_child(_error_label)
	var go := UiTheme.button("ENVOYER LE CODE", true)
	_card_content.add_child(go)
	_card_content.add_child(_link("← Retour à la connexion", _show_login))
	_submit = func() -> void:
		_run(go, "ENVOI…", func() -> Dictionary: return await Backend.request_password_reset(email.text),
			func(r: Dictionary) -> void:
				_show_reset_confirm(email.text.strip_edges())
				_show_error(r.message, UiTheme.GREEN))
	go.pressed.connect(func() -> void: _submit.call())
	email.grab_focus.call_deferred()


## Deuxième étape du mot de passe oublié : le code reçu et le nouveau mot de passe.
func _show_reset_confirm(email: String) -> void:
	_clear_card()
	_card_content.add_child(UiTheme.title("NOUVEAU MOT DE PASSE", 20))
	var info := UiTheme.label("Saisis le code à 6 chiffres envoyé à\n%s, puis ton nouveau mot de passe." % email, 17, UiTheme.MUTED)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_content.add_child(info)
	_card_content.add_child(_field_label("Code"))
	var code := _field("123456")
	code.max_length = 6
	_card_content.add_child(code)
	_card_content.add_child(_field_label("Nouveau mot de passe"))
	var password := _field("8 caractères minimum", true)
	_card_content.add_child(password)
	_card_content.add_child(_error_label)
	var go := UiTheme.button("CHANGER LE MOT DE PASSE", true)
	_card_content.add_child(go)
	_card_content.add_child(_link("← Retour à la connexion", _show_login))
	_submit = func() -> void:
		_run(go, "ENREGISTREMENT…",
			func() -> Dictionary: return await Backend.confirm_password_reset(email, code.text.strip_edges(), password.text),
			func(r: Dictionary) -> void:
				_show_login()
				_show_error(r.message, UiTheme.GREEN))
	go.pressed.connect(func() -> void: _submit.call())
	code.grab_focus.call_deferred()


# --------------------------------------------------------------------------- actions

## Lance une requête : bouton désactivé pendant l'attente, erreur affichée si besoin.
## `on_error` (facultatif) peut traiter une erreur lui-même : il renvoie alors true.
func _run(button: Button, busy_text: String, request: Callable, on_success: Callable, on_error := Callable()) -> void:
	if _busy:
		return
	_busy = true
	var label := button.text
	button.text = busy_text
	button.disabled = true
	_error_label.visible = false
	var result: Dictionary = await request.call()
	_busy = false
	if not is_instance_valid(button):
		return
	button.text = label
	button.disabled = false
	if result.get("ok", false):
		on_success.call(result)
	elif not (on_error.is_valid() and on_error.call(result)):
		_show_error(result.get("message", "Erreur inconnue."))


func _show_error(message: String, color := UiTheme.RED) -> void:
	_error_label.text = message
	_error_label.add_theme_color_override("font_color", color)
	_error_label.visible = true


func _enter_game() -> void:
	get_tree().change_scene_to_file(MAIN_MENU)
