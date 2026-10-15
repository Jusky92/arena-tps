class_name DamageIndicator
extends Control
## Indicateur de provenance des dégâts (style Call of Duty) : un arc rouge autour du
## centre de l'écran, tourné vers le tireur. L'arc suit la rotation du joueur tant
## qu'il est affiché (on peut se retourner vers le tireur), puis s'efface.
## Le HUD appelle add() à chaque coup reçu et donne le joueur suivi dans `player`.

@export var color := Color(1.0, 0.18, 0.22)
@export var radius := 120.0            ## distance de l'arc au centre de l'écran (px)
@export var arc_degrees := 42.0        ## largeur de l'arc
@export var thickness := 7.0
@export var duration := 1.6            ## secondes d'affichage d'un coup
@export var merge_degrees := 25.0      ## deux coups plus proches que ça ne font qu'un arc

## Joueur dont on prend la position et l'orientation (CharacterBody3D).
var player: Node3D

var _hits: Array = []                  # [{source: Vector3, time: float}]


## Coup reçu depuis `source` (position du tireur). Vector3.INF = provenance inconnue.
func add(source: Vector3) -> void:
	if source == Vector3.INF or player == null or not is_instance_valid(player):
		return
	var angle := _angle_to(source)
	for hit in _hits:
		if absf(angle_difference(_angle_to(hit.source), angle)) < deg_to_rad(merge_degrees):
			hit.source = source
			hit.time = duration
			return
	_hits.append({"source": source, "time": duration})


func clear() -> void:
	_hits.clear()
	queue_redraw()


func _process(delta: float) -> void:
	if _hits.is_empty():
		return
	for hit in _hits:
		hit.time -= delta
	_hits = _hits.filter(func(h): return h.time > 0.0)
	queue_redraw()


## Angle de la source vu du joueur : 0 = devant, positif = à droite.
func _angle_to(source: Vector3) -> float:
	var local := player.global_basis.inverse() * (source - player.global_position)
	return atan2(local.x, -local.z)


func _draw() -> void:
	if player == null or not is_instance_valid(player):
		return
	var center := size / 2.0
	var half := deg_to_rad(arc_degrees) / 2.0
	for hit in _hits:
		var alpha := clampf(hit.time / (duration * 0.5), 0.0, 1.0)
		# À l'écran, 0 rad pointe vers la droite : "devant" (haut de l'écran) = -PI/2.
		var a := _angle_to(hit.source) - PI / 2.0
		var c := Color(color, 0.85 * alpha)
		draw_arc(center, radius, a - half, a + half, 24, Color(0, 0, 0, 0.35 * alpha), thickness + 4.0, true)
		draw_arc(center, radius, a - half, a + half, 24, c, thickness, true)
		# Petite flèche au milieu de l'arc, tournée vers l'extérieur.
		var dir := Vector2(cos(a), sin(a))
		var side := Vector2(-dir.y, dir.x)
		var tip := center + dir * (radius + thickness + 12.0)
		var base := center + dir * (radius + thickness * 0.5 + 1.0)
		draw_colored_polygon(PackedVector2Array([tip, base + side * 9.0, base - side * 9.0]), c)
