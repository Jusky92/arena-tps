class_name UiTheme
extends RefCounted
## Charte graphique de l'interface (style cyberpunk) : couleurs, polices, styles des
## boutons / champs / panneaux, et petites fonctions pour fabriquer les éléments.
## Les styles eux-mêmes sont dans ui/theme/neon_theme.tres (thème global du projet) ;
## les variations (TitleLabel, PrimaryButton, HudPanel…) s'utilisent via theme_type_variation.

# --- Couleurs ---
const BG := Color(0.027, 0.035, 0.06)
const PANEL := Color(0.06, 0.08, 0.13, 0.88)
const PANEL_LIGHT := Color(0.09, 0.12, 0.19, 0.92)
const CYAN := Color(0.18, 0.89, 0.92)
const MAGENTA := Color(0.95, 0.27, 0.78)
const YELLOW := Color(1.0, 0.84, 0.25)
const GREEN := Color(0.32, 0.95, 0.55)
const RED := Color(1.0, 0.33, 0.36)
const TEXT := Color(0.9, 0.93, 0.97)
const MUTED := Color(0.55, 0.6, 0.7)

const FONT_TITLE := preload("res://assets/fonts/Orbitron.ttf")
const FONT_TEXT := preload("res://assets/fonts/Rajdhani-Medium.ttf")
const FONT_BOLD := preload("res://assets/fonts/Rajdhani-Bold.ttf")
const BACKGROUND_SHADER := preload("res://shaders/menu_background.gdshader")
## Tous les styles (boutons, champs, panneaux, barres, HUD) sont dans ce fichier,
## modifiable dans l'éditeur Godot. Il est aussi le thème global du projet.
const THEME := preload("res://ui/theme/neon_theme.tres")

static var _theme: Theme
static var _title_font: Font


static func get_theme() -> Theme:
	if _theme == null:
		_theme = THEME
	return _theme


## Police des titres (Orbitron en gras), prise dans le thème.
static func title_font() -> Font:
	if _title_font == null:
		_title_font = THEME.get_font("font", &"TitleLabel")
	return _title_font


## Style de boîte (fond, bordure, coins, marges). Par défaut, coins biseautés
## (haut gauche et bas droite) comme dans le thème ; bevel = false pour des coins ronds.
static func box(bg: Color, border: Color, border_width := 1, radius := 4, margin_x := 12, margin_y := 8, bevel := true) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_width)
	if bevel:
		s.corner_radius_top_left = radius * 2
		s.corner_radius_bottom_right = radius * 2
		s.corner_detail = 1
	else:
		s.set_corner_radius_all(radius)
	s.content_margin_left = margin_x
	s.content_margin_right = margin_x
	s.content_margin_top = margin_y
	s.content_margin_bottom = margin_y
	s.anti_aliasing = true
	return s


static func label(text: String, size := 18, color := TEXT, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", FONT_BOLD)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func title(text: String, size := 32, color := TEXT) -> Label:
	var l := label(text, size, color)
	l.theme_type_variation = &"TitleLabel"
	return l


## Bouton principal (rempli, couleur d'accent) ou secondaire (contour).
## Le principal cyan vient du thème (variation PrimaryButton) ; les autres couleurs
## d'accent reprennent la même forme biseautée.
static func button(text: String, primary := false, accent := CYAN, min_height := 44) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_height)
	b.focus_mode = Control.FOCUS_ALL
	if primary:
		b.theme_type_variation = &"PrimaryButton"
		if accent != CYAN:
			var normal := box(Color(accent, 0.85), accent, 1, 5, 18, 8)
			normal.shadow_color = Color(accent, 0.2)
			normal.shadow_size = 6
			var hover := box(accent.lightened(0.15), Color.WHITE, 1, 5, 18, 8)
			hover.shadow_color = Color(accent, 0.45)
			hover.shadow_size = 12
			b.add_theme_stylebox_override("normal", normal)
			b.add_theme_stylebox_override("hover", hover)
			b.add_theme_stylebox_override("pressed", box(accent.darkened(0.2), accent, 1, 5, 18, 8))
	add_hover_feedback(b)
	return b


## Petit retour au survol : léger son et grossissement (le pivot suit la taille).
static func add_hover_feedback(b: Button) -> void:
	b.resized.connect(func() -> void: b.pivot_offset = b.size / 2.0)
	b.mouse_entered.connect(func() -> void:
		if b.disabled:
			return
		Sfx.ui("ui_click", -16.0)
		b.create_tween().tween_property(b, "scale", Vector2.ONE * 1.02, 0.08))
	b.mouse_exited.connect(func() -> void:
		b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.1))


static func panel(bg := PANEL, border := Color(CYAN, 0.16)) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(bg, border, 1, 6, 18, 16))
	return p


## Fond animé (grille néon en perspective, halos) à placer en premier enfant d'un écran.
static func background() -> ColorRect:
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = BACKGROUND_SHADER
	rect.material = material
	return rect


## Petit point coloré (statut en ligne, etc.).
static func dot(color: Color, size := 10) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(size, size)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_theme_stylebox_override("panel", box(color, Color(0, 0, 0, 0), 0, size / 2, 0, 0, false))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func spacer(min_size := Vector2.ZERO, expand_h := false, expand_v := false) -> Control:
	var c := Control.new()
	c.custom_minimum_size = min_size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand_h:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if expand_v:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


## Ligne horizontale lumineuse.
static func neon_line(color := CYAN, height := 2) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(color, 0.7)
	r.custom_minimum_size = Vector2(0, height)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
