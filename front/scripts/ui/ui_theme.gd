class_name UiTheme
extends RefCounted
## Charte graphique de l'interface (style cyberpunk) : couleurs, polices, styles des
## boutons / champs / panneaux, et petites fonctions pour fabriquer les éléments.
## Tous les écrans appliquent UiTheme.get_theme() sur leur nœud racine.

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

static var _theme: Theme
static var _title_font: FontVariation


static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = FONT_TEXT
	t.default_font_size = 18

	t.set_color("font_color", "Label", TEXT)

	# Boutons.
	t.set_stylebox("normal", "Button", box(Color(0.08, 0.11, 0.18, 0.92), Color(CYAN, 0.3), 1, 4, 14, 8))
	t.set_stylebox("hover", "Button", box(Color(0.1, 0.17, 0.25, 0.95), CYAN, 1, 4, 14, 8))
	t.set_stylebox("pressed", "Button", box(Color(CYAN, 0.35), CYAN, 1, 4, 14, 8))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), Color(CYAN, 0.7), 1, 4, 14, 8))
	t.set_stylebox("disabled", "Button", box(Color(0.06, 0.07, 0.1, 0.8), Color(1, 1, 1, 0.06), 1, 4, 14, 8))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", CYAN)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", MUTED)
	t.set_font("font", "Button", FONT_BOLD)
	t.set_font_size("font_size", "Button", 19)

	# Champs de saisie.
	t.set_stylebox("normal", "LineEdit", box(Color(0.03, 0.045, 0.075, 0.95), Color(CYAN, 0.22), 1, 4, 12, 9))
	t.set_stylebox("focus", "LineEdit", box(Color(0.03, 0.045, 0.075, 0.95), CYAN, 1, 4, 12, 9))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(MUTED, 0.7))
	t.set_color("caret_color", "LineEdit", CYAN)
	t.set_color("selection_color", "LineEdit", Color(CYAN, 0.3))
	t.set_font_size("font_size", "LineEdit", 19)

	# Panneaux.
	t.set_stylebox("panel", "PanelContainer", box(PANEL, Color(CYAN, 0.16), 1, 6, 18, 16))

	# Barres de progression.
	t.set_stylebox("background", "ProgressBar", box(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 0, 3, 0, 0))
	t.set_stylebox("fill", "ProgressBar", box(CYAN, Color(0, 0, 0, 0), 0, 3, 0, 0))

	# Défilement : barre fine.
	var grabber := box(Color(CYAN, 0.35), Color(0, 0, 0, 0), 0, 3, 0, 0)
	for type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type, box(Color(1, 1, 1, 0.03), Color(0, 0, 0, 0), 0, 3, 3, 3))
		t.set_stylebox("grabber", type, grabber)
		t.set_stylebox("grabber_highlight", type, box(Color(CYAN, 0.6), Color(0, 0, 0, 0), 0, 3, 0, 0))
		t.set_stylebox("grabber_pressed", type, box(CYAN, Color(0, 0, 0, 0), 0, 3, 0, 0))

	# Curseurs (réglages du son, sensibilité).
	var track := box(Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), 0, 3, 0, 3)
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", box(Color(CYAN, 0.85), Color(0, 0, 0, 0), 0, 3, 0, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(CYAN, Color(0, 0, 0, 0), 0, 3, 0, 3))
	t.set_icon("grabber", "HSlider", _round_icon(Color.WHITE, CYAN, 20))
	t.set_icon("grabber_highlight", "HSlider", _round_icon(Color.WHITE, Color.WHITE, 22))
	t.set_icon("grabber_disabled", "HSlider", _round_icon(MUTED, MUTED, 20))

	# Info-bulles.
	t.set_stylebox("panel", "TooltipPanel", box(Color(0.05, 0.06, 0.1, 0.97), Color(CYAN, 0.4), 1, 4, 10, 6))
	_theme = t
	return t


## Petit disque (poignée des curseurs) : centre `inner`, bord `ring`.
static func _round_icon(inner: Color, ring: Color, size: int) -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 0.7, 0.86, 0.94])
	g.colors = PackedColorArray([inner, inner, ring, ring, Color(ring, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = size
	tex.height = size
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	return tex


## Police des titres (Orbitron en gras).
static func title_font() -> FontVariation:
	if _title_font:
		return _title_font
	_title_font = FontVariation.new()
	_title_font.base_font = FONT_TITLE
	_title_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 800}
	return _title_font


## Style de boîte (fond, bordure, coins, marges).
static func box(bg: Color, border: Color, border_width := 1, radius := 4, margin_x := 12, margin_y := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_width)
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
	l.add_theme_font_override("font", title_font())
	return l


## Bouton principal (rempli, couleur d'accent) ou secondaire (contour).
static func button(text: String, primary := false, accent := CYAN, min_height := 44) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_height)
	b.focus_mode = Control.FOCUS_ALL
	if primary:
		b.add_theme_stylebox_override("normal", box(Color(accent, 0.85), accent, 1, 4, 16, 8))
		b.add_theme_stylebox_override("hover", box(accent.lightened(0.15), Color.WHITE, 1, 4, 16, 8))
		b.add_theme_stylebox_override("pressed", box(accent.darkened(0.2), accent, 1, 4, 16, 8))
		b.add_theme_color_override("font_color", Color(0.02, 0.03, 0.06))
		b.add_theme_color_override("font_hover_color", Color(0.02, 0.03, 0.06))
		b.add_theme_color_override("font_pressed_color", Color(0.02, 0.03, 0.06))
		b.add_theme_font_override("font", title_font())
		b.add_theme_font_size_override("font_size", 16)
	return b


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
	p.add_theme_stylebox_override("panel", box(color, Color(0, 0, 0, 0), 0, size / 2, 0, 0))
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
