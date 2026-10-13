class_name JapaneseFont
extends RefCounted
## Accès à la police japonaise (Noto Sans JP, licence OFL) utilisée par toutes les
## enseignes et lanternes de la map.
##
## La police n'est chargée qu'une fois, au premier appel : `JapaneseFont.font()`.
## Le fichier livré est un sous-ensemble (seuls les caractères utilisés par le jeu),
## pour rester léger ; voir tools/subset_font.py.

const PATH := "res://assets/fonts/NotoSansJP-Bold.otf"

static var _font: Font


static func font() -> Font:
	if _font == null:
		_font = load(PATH)
	return _font
