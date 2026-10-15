@tool
class_name Crosshair
extends Control
## Réticule dessiné : quatre traits autour d'un point. L'écart entre les traits suit
## la dispersion réelle de l'arme (visée, accroupi, déplacement) et s'ouvre à chaque tir.
## Marque de touche en X : blanche quand on touche, jaune à la tête, rouge et plus
## grande quand on élimine.
## Le HUD appelle set_spread() à chaque image, kick() à chaque tir et hit() à chaque touche.

@export var color := Color(1, 1, 1, 0.95)
@export var outline_color := Color(0, 0.02, 0.05, 0.6)
@export var line_length := 9.0
@export var thickness := 2.0
@export var min_gap := 4.0
@export var max_gap := 60.0
@export var hit_color := Color(1, 1, 1)
@export var kill_color := Color(1, 0.25, 0.3)
@export var headshot_color := Color(1, 0.84, 0.25)

var _gap := 8.0
var _target_gap := 8.0
var _kick := 0.0           # ouverture supplémentaire après un tir (px), retombe vite
var _hit := 0.0            # 1 -> 0 : opacité de la marque de touche
var _hit_killed := false
var _hit_head := false


## Écart voulu (en pixels) entre le centre et les traits.
func set_spread(gap_px: float) -> void:
	_target_gap = clampf(gap_px, min_gap, max_gap)


func kick(amount := 6.0) -> void:
	_kick = minf(_kick + amount, 24.0)


func hit(killed: bool, headshot := false) -> void:
	# Une élimination (ou un tir à la tête) encore affichée n'est pas effacée par une simple touche.
	_hit_killed = killed or (_hit_killed and _hit > 0.0)
	_hit_head = headshot or (_hit_head and _hit > 0.0)
	_hit = 1.0


func _process(delta: float) -> void:
	_gap = lerpf(_gap, _target_gap, 1.0 - exp(-delta * 18.0))
	_kick = move_toward(_kick, 0.0, delta * 60.0)
	if _hit > 0.0:
		_hit = maxf(_hit - delta * (2.2 if _hit_killed else 4.0), 0.0)
		if _hit == 0.0:
			_hit_killed = false
			_hit_head = false
	queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	var gap := _gap + _kick
	# Point central.
	draw_rect(Rect2(c - Vector2.ONE * 2.0, Vector2.ONE * 4.0), outline_color)
	draw_rect(Rect2(c - Vector2.ONE, Vector2.ONE * 2.0), color)
	# Quatre traits (contour sombre dessous pour rester lisible sur fond clair).
	for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var a := c + dir * gap
		var b := c + dir * (gap + line_length)
		draw_line(a - dir, b + dir, outline_color, thickness + 2.0)
		draw_line(a, b, color, thickness)
	# Marque de touche.
	if _hit > 0.0:
		var hc := kill_color if _hit_killed else (headshot_color if _hit_head else hit_color)
		hc.a *= _hit
		var big := _hit_killed or _hit_head
		var r_in := gap * 0.6 + 3.0
		var r_out := r_in + (12.0 if big else 8.0) * (1.0 + (1.0 - _hit) * 0.4)
		for dir: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var d := dir.normalized()
			draw_line(c + d * r_in, c + d * r_out, Color(outline_color, outline_color.a * _hit), thickness + 3.0)
			draw_line(c + d * r_in, c + d * r_out, hc, thickness + (1.0 if big else 0.0))
