class_name CharacterRig
extends Node3D
## Corps 3D animé d'un personnage (joueur, futur joueur distant, mannequin).
##
## Le squelette est une hiérarchie de "pivots" (hanches, buste, tête, bras, jambes)
## sur lesquels on accroche des pièces d'armure (voir CharacterDesigns).
##
## L'animation est PROCÉDURALE : elle est calculée à chaque image à partir de l'état
## du personnage (vitesse, au sol, accroupi, angle de visée...). Il suffit d'appeler
## set_state() ; le rig s'occupe du reste. En multijoueur, le serveur n'aura qu'à
## transmettre cet état pour que les autres joueurs soient animés pareil.
##
## Repère : le personnage regarde vers -Z, les pieds sont à y = 0.

# --- Proportions (communes à toutes les classes, pour garder la même hitbox) ---
const HIP_HEIGHT := 1.0
const HIP_JOINT := Vector3(0.11, -0.04, 0.0)
const THIGH := 0.43
const SHIN := 0.43
const ANKLE := 0.1
const UPPER_ARM := 0.31
const FOREARM := 0.29
const CROUCH_HIP_HEIGHT := 0.64

const FLASH_MATERIAL := preload("res://data/materials/flash.tres")

# --- Pivots du squelette ---
var hips: Node3D
var spine: Node3D
var chest: Node3D
var head: Node3D
var arm_pivot: Node3D       # porte les bras et l'arme : suit exactement la visée
var gun_mount: Node3D       # emplacement de l'arme (main droite)
var thighs: Array[Node3D] = []
var shins: Array[Node3D] = []
var feet: Array[Node3D] = []
var upper_arms: Array[Node3D] = []
var forearms: Array[Node3D] = []
var hands: Array[Node3D] = []
var tails: Array[Node3D] = []   # pièces souples (écharpe, pans de manteau) qui flottent

## Largeur des épaules (dépend de la carrure de la classe).
var shoulder_half_width := 0.22
## Distance entre la poignée et la main gauche sur l'arme.
var foregrip := 0.3
var design_id := ""
var _weapon_grips := {}     # nœud d'arme -> distance de la main gauche

# --- État d'entrée (rempli par set_state) ---
var move_velocity := Vector3.ZERO   # vitesse dans le repère du personnage
var on_floor := true
var crouch_target := 0.0
var aim_pitch := 0.0
var sprinting := false
var aiming := false

# --- État interne de l'animation ---
var _parts: Array[MeshInstance3D] = []
var _phase := 0.0
var _crouch := 0.0
var _air := 0.0
var _move := 0.0
var _run := 0.0
var _sprint_pose := 0.0
var _land_offset := 0.0
var _land_speed := 0.0
var _was_on_floor := true
var _last_vertical_speed := 0.0
var _kick := 0.0
var _time := 0.0
var _dead := false
var _gun_rest := Vector3(0.1, -0.12, -0.28)
var _tail_angles: Array[float] = []


# =========================================================================== construction

## Construit le squelette, l'apparence (design) et le modèle d'arme.
## weapon_node : nœud de l'arme (avec son script et son Muzzle), rattaché à la main droite.
func build(id: String, weapon_kind: int, weapon_node: Node3D = null) -> void:
	design_id = id
	_weapon_grips.clear()
	for child in get_children():
		child.queue_free()
	_parts.clear()
	thighs.clear(); shins.clear(); feet.clear()
	upper_arms.clear(); forearms.clear(); hands.clear(); tails.clear(); _tail_angles.clear()

	var bulk := CharacterDesigns.bulk(design_id)
	shoulder_half_width = 0.2 * bulk + 0.02

	hips = _bone(self, "Hips", Vector3(0, HIP_HEIGHT, 0))
	spine = _bone(hips, "Spine", Vector3(0, 0.08, 0))
	chest = _bone(spine, "Chest", Vector3(0, 0.22, 0))
	head = _bone(chest, "Head", Vector3(0, 0.26, 0))
	arm_pivot = _bone(chest, "ArmPivot", Vector3(0, 0.2, 0))
	gun_mount = _bone(arm_pivot, "GunMount", _gun_rest)

	for side in [-1.0, 1.0]:
		var thigh := _bone(hips, "Thigh", Vector3(HIP_JOINT.x * side * bulk, HIP_JOINT.y, 0))
		var shin := _bone(thigh, "Shin", Vector3(0, -THIGH, 0))
		var foot := _bone(shin, "Foot", Vector3(0, -SHIN, 0))
		thighs.append(thigh)
		shins.append(shin)
		feet.append(foot)
		upper_arms.append(_bone(arm_pivot, "UpperArm", Vector3.ZERO))
		forearms.append(_bone(arm_pivot, "Forearm", Vector3.ZERO))
		hands.append(_bone(arm_pivot, "Hand", Vector3.ZERO))

	CharacterDesigns.build(self, design_id)
	var weapon_info := CharacterDesigns.build_weapon(self, weapon_kind, design_id, weapon_node)
	foregrip = weapon_info.foregrip
	_merge_parts()
	if weapon_node:
		_weapon_grips[weapon_node] = foregrip
		weapon_node.reparent(gun_mount, false)
		weapon_node.transform = Transform3D.IDENTITY
	_update_pose(0.0)


func _bone(parent: Node3D, bone_name: String, offset: Vector3) -> Node3D:
	var bone := Node3D.new()
	bone.name = bone_name
	parent.add_child(bone)
	bone.position = offset
	return bone


## Accroche une pièce (forme PartMesh) à un pivot du squelette.
func add_part(bone: Node3D, size: Vector3, roundness: float, offset: Vector3, material: Material,
		rotation_deg := Vector3.ZERO, taper := Vector2.ONE, vertical := -1.0) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var r := PartMesh.smooth(roundness, vertical, PartMesh.SMOOTH_GEAR)
	part.mesh = PartMesh.shape(size, r.x, r.y, taper)
	part.material_override = material
	bone.add_child(part)
	part.position = offset
	part.rotation_degrees = rotation_deg
	_parts.append(part)
	return part


## Optimisation : les pièces accrochées au même pivot avec la même matière sont
## fusionnées en un seul maillage (environ 65 pièces -> une trentaine d'appels de rendu).
func _merge_parts(from_index := 0) -> void:
	var groups := {}
	var kept: Array[MeshInstance3D] = []
	for i in _parts.size():
		var part := _parts[i]
		if i < from_index:
			kept.append(part)
			continue
		var key := "%d|%d" % [part.get_parent().get_instance_id(), part.material_override.get_instance_id()]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(part)
	var merged: Array[MeshInstance3D] = []
	for key in groups:
		var group: Array = groups[key]
		if group.size() == 1:
			merged.append(group[0])
			continue
		var tool := SurfaceTool.new()
		for part in group:
			tool.append_from(part.mesh, 0, part.transform)
		var first: MeshInstance3D = group[0]
		var combined := MeshInstance3D.new()
		combined.mesh = tool.commit()
		combined.material_override = first.material_override
		first.get_parent().add_child(combined)
		for part in group:
			part.free()
		merged.append(combined)
	kept.append_array(merged)
	_parts = kept


## Ajoute une arme de plus (classes : principale + secondaire). Son modèle est
## construit dans `weapon_node`, accroché à la main ; show_weapon() choisit celle en main.
func add_weapon(weapon_kind: int, weapon_node: Node3D) -> void:
	var first_new := _parts.size()
	var weapon_info := CharacterDesigns.build_weapon(self, weapon_kind, design_id, weapon_node)
	_weapon_grips[weapon_node] = weapon_info.foregrip
	_merge_parts(first_new)
	weapon_node.reparent(gun_mount, false)
	weapon_node.transform = Transform3D.IDENTITY


## Affiche l'arme en main et cache les autres ; la main gauche se place sur elle.
func show_weapon(weapon_node: Node3D) -> void:
	for node in _weapon_grips:
		if is_instance_valid(node):
			node.visible = node == weapon_node
	foregrip = _weapon_grips.get(weapon_node, foregrip)


## Ajoute un pivot souple (écharpe, pan de manteau) qui réagit au mouvement.
func add_tail(bone: Node3D, offset: Vector3) -> Node3D:
	var tail := _bone(bone, "Tail", offset)
	tails.append(tail)
	_tail_angles.append(0.0)
	return tail


# =========================================================================== état et effets

## À appeler à chaque image par le propriétaire (joueur, réseau, mannequin).
func set_state(velocity_local: Vector3, is_on_floor: bool, crouch_amount: float, pitch: float,
		is_sprinting := false, is_aiming := false) -> void:
	move_velocity = velocity_local
	on_floor = is_on_floor
	crouch_target = crouch_amount
	aim_pitch = pitch
	sprinting = is_sprinting
	aiming = is_aiming


## Recul de l'arme (appelé à chaque tir).
func kick(recoil_deg: float) -> void:
	_kick = minf(_kick + 0.02 + recoil_deg * 0.012, 0.14)


## Flash blanc quand le personnage est touché.
func flash() -> void:
	for part in _parts:
		part.material_overlay = FLASH_MATERIAL
	get_tree().create_timer(0.07).timeout.connect(func() -> void:
		for part in _parts:
			if is_instance_valid(part):
				part.material_overlay = null)


## Chute en arrière à la mort.
func play_death() -> void:
	_dead = true
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "rotation:x", 1.45, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "position:y", 0.15, 0.45)


## Remet le personnage debout (réapparition).
func reset() -> void:
	_dead = false
	rotation = Vector3.ZERO
	position = Vector3.ZERO
	_crouch = 0.0
	_air = 0.0
	_land_offset = 0.0
	_land_speed = 0.0


# =========================================================================== animation

func _process(delta: float) -> void:
	if not _dead:
		_update_pose(delta)


func _update_pose(delta: float) -> void:
	_time += delta
	var flat_speed := Vector2(move_velocity.x, move_velocity.z).length()

	# Valeurs lissées : on ne passe jamais d'une pose à l'autre d'un coup.
	_crouch = move_toward(_crouch, crouch_target, delta * 6.0)
	_air = move_toward(_air, 0.0 if on_floor else 1.0, delta * (10.0 if on_floor else 5.0))
	_move = lerpf(_move, clampf(flat_speed / 4.0, 0.0, 1.0), minf(delta * 10.0, 1.0))
	_run = lerpf(_run, clampf((flat_speed - 5.5) / 3.0, 0.0, 1.0), minf(delta * 6.0, 1.0))
	_sprint_pose = lerpf(_sprint_pose, 1.0 if sprinting and not aiming else 0.0, minf(delta * 8.0, 1.0))
	var c := smoothstep(0.0, 1.0, _crouch)
	var ground := 1.0 - _air

	# Atterrissage : petit tassement amorti (ressort).
	if on_floor and not _was_on_floor and _last_vertical_speed < -2.5:
		_land_speed -= clampf(-_last_vertical_speed * 0.12, 0.0, 1.4)
	_was_on_floor = on_floor
	_last_vertical_speed = move_velocity.y
	_land_speed += (-_land_offset * 180.0 - _land_speed * 18.0) * delta
	_land_offset = clampf(_land_offset + _land_speed * delta, -0.25, 0.05)

	# Cycle de marche : la phase avance avec la distance parcourue.
	var stride := lerpf(1.5, 2.7, _run) * lerpf(1.0, 0.65, c)
	if flat_speed > 0.05:
		_phase = fmod(_phase + flat_speed / stride * TAU * delta, TAU)
	var amplitude := _move * ground * lerpf(0.5, 0.82, _run) * lerpf(1.0, 0.55, c)
	var direction := Vector3(move_velocity.x, 0, move_velocity.z).normalized() if flat_speed > 0.05 else Vector3.FORWARD
	var swing_axis := Vector3(-direction.z, 0, direction.x)

	# Hanches : hauteur (accroupi, balancement des pas, atterrissage).
	var bob := absf(sin(_phase)) * 0.045 * _move * ground
	var hip_y := lerpf(HIP_HEIGHT, CROUCH_HIP_HEIGHT, c) - bob + _land_offset
	hips.position.y = hip_y
	hips.rotation = Vector3(0, sin(_phase) * 0.12 * amplitude, 0)

	# Jambes : on calcule la flexion qui garde les pieds au sol (IK simple),
	# puis on ajoute le balancement de la marche et la pose en l'air.
	var reach := hip_y + HIP_JOINT.y - ANKLE
	var bend := acos(clampf(reach / (THIGH + SHIN), -1.0, 1.0))
	for i in 2:
		var phase := _phase + (PI if i == 1 else 0.0)
		var swing := sin(phase) * amplitude
		var lift := (maxf(0.0, cos(phase)) * 1.3 + 0.15) * amplitude
		var air_thigh := (1.0 if i == 0 else -0.3) * _air
		var air_knee := (1.6 if i == 0 else 0.6) * _air
		var thigh_bend := bend + air_thigh
		var knee := 2.0 * bend + lift + air_knee
		thighs[i].basis = Basis(swing_axis, swing) * Basis(Vector3.RIGHT, thigh_bend)
		shins[i].rotation = Vector3(-knee, 0, 0)
		feet[i].rotation = Vector3(knee - thigh_bend - swing * -direction.z * 0.6, 0, 0)

	# Buste : penché en avant en courant / accroupi, suit la visée, contre-rotation des épaules.
	var lean := -(0.06 * _move + 0.2 * _run + 0.22 * c) * (1.0 - _sprint_pose * 0.2)
	var breathe := sin(_time * 1.9) * 0.015 * (1.0 - _move)
	spine.rotation = Vector3(lean + aim_pitch * 0.45, -sin(_phase) * 0.14 * amplitude, 0)
	chest.rotation = Vector3(aim_pitch * 0.35 + breathe, 0, 0)
	head.rotation = Vector3(aim_pitch * 0.2 - lean, 0, 0)

	# Bras et arme : compensent le buste pour pointer exactement vers la visée.
	# En sprint, l'arme est baissée et tournée sur le côté.
	var gun_pitch := aim_pitch * 0.2 - lean - breathe - 0.75 * _sprint_pose
	arm_pivot.rotation = Vector3(gun_pitch, -(hips.rotation.y + spine.rotation.y) + 0.5 * _sprint_pose, 0)
	_kick = move_toward(_kick, 0.0, delta * 0.9)
	var sway := Vector3(sin(_phase) * 0.012, absf(cos(_phase)) * 0.015, 0) * _move
	gun_mount.position = _gun_rest + Vector3(0, -0.04 * _air, _kick) + sway
	gun_mount.rotation = Vector3(_kick * 2.2, 0, 0)
	_solve_arms()

	# Pièces souples : flottent selon la vitesse et la gravité.
	var forward_speed := -move_velocity.z
	for i in tails.size():
		var target := clampf(forward_speed * 0.07 + absf(move_velocity.x) * 0.03, -0.3, 1.0) \
			+ _air * 0.4 + sin(_time * 3.0 + i) * 0.05 * (0.3 + _move)
		_tail_angles[i] = lerpf(_tail_angles[i], target, minf(delta * 6.0, 1.0))
		tails[i].rotation = Vector3(_tail_angles[i], 0, 0)


## Bras : cinématique inverse à deux os (épaule -> coude -> main) pour que les mains
## tiennent l'arme quelle que soit sa position.
func _solve_arms() -> void:
	var grip_right := gun_mount.transform * Vector3(0, 0, 0.02)
	var grip_left := gun_mount.transform * Vector3(0, -0.01, -foregrip)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var shoulder := Vector3(side * shoulder_half_width, 0, 0)
		var target := grip_left if i == 0 else grip_right
		var pole := Vector3(side * 0.8, -1.0, 0.3)  # les coudes pointent vers le bas et l'extérieur
		var elbow := _elbow_position(shoulder, target, pole)
		_orient_segment(upper_arms[i], shoulder, elbow)
		_orient_segment(forearms[i], elbow, target)
		hands[i].transform = Transform3D(gun_mount.transform.basis, target)


func _elbow_position(shoulder: Vector3, target: Vector3, pole: Vector3) -> Vector3:
	var to_target := target - shoulder
	var distance := clampf(to_target.length(), 0.05, UPPER_ARM + FOREARM - 0.001)
	var dir := to_target.normalized()
	var cos_a := (UPPER_ARM * UPPER_ARM + distance * distance - FOREARM * FOREARM) / (2.0 * UPPER_ARM * distance)
	var angle := acos(clampf(cos_a, -1.0, 1.0))
	var bend_dir := (pole - dir * pole.dot(dir)).normalized()
	return shoulder + dir * cos(angle) * UPPER_ARM + bend_dir * sin(angle) * UPPER_ARM


## Place un segment (modélisé le long de -Y) entre deux points.
func _orient_segment(segment: Node3D, from: Vector3, to: Vector3) -> void:
	var down := (to - from).normalized()
	var y := -down
	var hint := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := y.cross(hint).normalized()
	var z := x.cross(y).normalized()
	segment.transform = Transform3D(Basis(x, y, z), from)
