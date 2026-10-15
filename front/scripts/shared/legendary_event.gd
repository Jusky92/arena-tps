class_name LegendaryEvent
extends RefCounted
## Arme légendaire « Canon du Shōgun » : une seule fois par match à mort, à un moment
## tiré au hasard après le milieu de la partie, elle apparaît sur un socle de la map.
## Pendant CINEMATIC_TIME secondes, la partie est figée (Engine.time_scale = 0, le
## chronomètre aussi) et tous les joueurs regardent la cinématique (LegendaryCinematic).
##
## Qui décide : le serveur dédié en ligne (server_game.gd), la partie elle-même hors
## ligne (game.gd). Règles communes ici (fonctions static).

const WEAPON_ID := "shogun_cannon"
const CINEMATIC_TIME := 6.0
## Apparition entre 50 % et 80 % de la durée du match.
const EARLIEST := 0.5
const LATEST := 0.8
## L'endroit choisi est à plus de 15 m de tout joueur vivant (sinon le plus éloigné).
const MIN_DISTANCE := 15.0
const GOLD := Color(1.0, 0.78, 0.28)


## Moment de l'apparition (secondes de jeu depuis le début du match).
static func trigger_time(duration: float) -> float:
	return duration * randf_range(EARLIEST, LATEST)


## Endroit où l'arme apparaît : au hasard parmi `positions` (les emplacements des
## mannequins d'entraînement de la map : au sol, dégagés, sans autre bonus), loin des
## joueurs vivants.
static func pick_point(positions: Array, players: Array) -> Vector3:
	var far := []
	var best := Vector3.ZERO
	var best_distance := -1.0
	for pos in positions:
		var nearest := INF
		for p in players:
			if is_instance_valid(p) and p.alive:
				nearest = minf(nearest, (pos as Vector3).distance_to(p.global_position))
		if nearest >= MIN_DISTANCE:
			far.append(pos)
		if nearest > best_distance:
			best_distance = nearest
			best = pos
	return far.pick_random() if not far.is_empty() else best


## Modèle 3D du canon (le même que dans les mains du porteur), pour le socle et la
## cinématique. `parent` reçoit les pièces ; l'avant du canon est vers -z.
static func build_cannon(parent: Node3D) -> void:
	CharacterDesigns.build_weapon(_PartBuilder.new(), WeaponData.Model.SHOGUN, "dummy", parent)


## Fournit add_part() comme un personnage, pour construire une arme sans personnage.
class _PartBuilder:
	extends RefCounted
	var gun_mount: Node3D = null

	func add_part(bone: Node3D, size: Vector3, roundness: float, offset: Vector3, material: Material,
			rotation_deg := Vector3.ZERO, taper := Vector2.ONE, vertical := -1.0) -> MeshInstance3D:
		var part := MeshInstance3D.new()
		var r := PartMesh.smooth(roundness, vertical, PartMesh.SMOOTH_WEAPON)
		part.mesh = PartMesh.shape(size, r.x, r.y, taper)
		part.material_override = material
		bone.add_child(part)
		part.position = offset
		part.rotation_degrees = rotation_deg
		return part
