class_name PickupDirector
extends Node3D
## Bonus de la map : où ils sont, s'ils sont disponibles, quand ils reviennent.
##
## Une seule version fait foi (authoritative = true) : le serveur dédié en ligne,
## la partie locale hors ligne. Elle détecte les ramassages (joueur vivant à moins
## de Pickups.PICK_RADIUS du socle), lance le compte à rebours de réapparition et
## émet `picked` ; c'est la partie qui applique l'effet. Les clients en ligne ont
## une version d'affichage, mise à jour par le serveur (Net.push_pickup).
##
## Les socles sont posés sur la surface trouvée par un rayon vers le bas (même
## calcul partout : le serveur et les clients ont les mêmes positions).

signal picked(pad_id: int, kind: int, player: Node)
signal state_changed(pad_id: int, available: bool)

var authoritative := true
## Fonction qui renvoie la liste des personnages pouvant ramasser (Array).
var players_provider: Callable = Callable()

var _pads := {}          # id -> {kind, pos, available, respawn}
var _visuals := {}       # id -> PickupPad (pas sur le serveur dédié)
var _snapped := false


## points : [[Pickups.Kind, Vector3(x, hauteur de départ du rayon, z)], …]
func setup(points: Array, is_authoritative: bool) -> void:
	authoritative = is_authoritative
	for i in points.size():
		_pads[i] = {"kind": points[i][0], "pos": points[i][1], "available": true, "respawn": 0.0}


func _physics_process(delta: float) -> void:
	if not _snapped:
		_snap_and_show()
		return
	if not authoritative:
		return
	for id in _pads:
		var pad: Dictionary = _pads[id]
		if not pad.available:
			pad.respawn -= delta
			if pad.respawn <= 0.0:
				set_available(id, true)
			continue
		if not players_provider.is_valid():
			continue
		for p in players_provider.call():
			if is_instance_valid(p) and p.alive and _close(p.global_position, pad.pos):
				set_available(id, false)
				pad.respawn = Pickups.respawn_of(pad.kind)
				picked.emit(id, pad.kind, p)
				break


func set_available(id: int, value: bool) -> void:
	if not _pads.has(id):
		return
	_pads[id].available = value
	if _visuals.has(id):
		_visuals[id].set_available(value)
	state_changed.emit(id, value)


## État de tous les socles (envoyé à un joueur qui rejoint la partie en cours).
func snapshot() -> Dictionary:
	var out := {}
	for id in _pads:
		out[id] = _pads[id].available
	return out


func apply_snapshot(states: Dictionary) -> void:
	for id in states:
		set_available(int(id), bool(states[id]))


## Positions des socles (bots : points de patrouille).
func positions() -> Array:
	return _pads.values().map(func(p): return p.pos)


## Positions des bonus disponibles en ce moment (les bots vont les chercher).
func available_positions() -> Array:
	return _pads.values().filter(func(p): return p.available).map(func(p): return p.pos)


func _close(a: Vector3, b: Vector3) -> bool:
	return Vector2(a.x - b.x, a.z - b.z).length() <= Pickups.PICK_RADIUS and absf(a.y - b.y) < 2.0


## Pose chaque socle sur la surface sous lui, puis crée son visuel (sauf serveur).
func _snap_and_show() -> void:
	_snapped = true
	var space := get_world_3d().direct_space_state
	for id in _pads:
		var pad: Dictionary = _pads[id]
		var from: Vector3 = pad.pos
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 30.0))
		pad.pos = hit.position if not hit.is_empty() else Vector3(from.x, 0.0, from.z)
		if Effects.headless():
			continue
		var visual := PickupPad.new()
		visual.kind = pad.kind
		add_child(visual)
		visual.global_position = pad.pos
		visual.set_available(pad.available)
		_visuals[id] = visual
