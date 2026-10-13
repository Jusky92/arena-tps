class_name AimIKModifier
extends SkeletonModifier3D
## Retouche le squelette APRÈS l'animation importée (marche, course, accroupi...) :
##  1. tourne le bas du corps vers la direction de déplacement (pas chassés, marche
##     arrière) tout en gardant le buste face à la visée ;
##  2. incline le buste et la tête selon l'angle de visée (haut / bas) ;
##  3. place l'arme devant la poitrine et pose les deux mains dessus (cinématique
##     inverse à deux os : épaule -> coude -> main).
##
## Les calculs se font dans le repère du personnage (avant = -Z, droite = +X), puis
## sont convertis dans le repère du squelette (le modèle importé regarde vers +Z).

## Repère du personnage (la racine HumanRig) et nœud où est accrochée l'arme.
var rig: Node3D
var gun_mount: Node3D

# Paramètres mis à jour à chaque image par HumanRig.
var aim_pitch := 0.0
var lower_body_yaw := 0.0
var gun_offset := Vector3(0.13, -0.2, -0.3)   # position de la poignée, depuis le milieu des épaules
var gun_extra := Transform3D.IDENTITY         # recul, balancement, arme baissée en sprint
var foregrip := 0.3
var arms_enabled := true

var _bones := {}


func _setup_bones(skeleton: Skeleton3D) -> void:
	for bone_name in ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "Head",
			"upperarm_l", "lowerarm_l", "hand_l", "middle_01_l",
			"upperarm_r", "lowerarm_r", "hand_r", "middle_01_r"]:
		_bones[bone_name] = skeleton.find_bone(bone_name)


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or rig == null:
		return
	if _bones.is_empty():
		_setup_bones(skeleton)

	# 1. Bas du corps tourné vers le déplacement, buste ramené face à la visée.
	if absf(lower_body_yaw) > 0.001:
		_rotate_bone(skeleton, "pelvis", Basis(Vector3.UP, lower_body_yaw))
		_rotate_bone(skeleton, "spine_01", Basis(Vector3.UP, -lower_body_yaw))

	# 2. Visée verticale répartie sur la colonne et la tête.
	for share in [["spine_01", 0.25], ["spine_02", 0.25], ["spine_03", 0.3], ["Head", 0.2]]:
		_rotate_bone(skeleton, share[0], Basis(Vector3.RIGHT, aim_pitch * share[1]))

	# 3. Arme : devant la poitrine, orientée vers la visée.
	var left_shoulder := _bone_pos(skeleton, "upperarm_l")
	var right_shoulder := _bone_pos(skeleton, "upperarm_r")
	var pivot := (left_shoulder + right_shoulder) * 0.5
	var aim_basis := Basis(Vector3.RIGHT, aim_pitch)
	var gun := Transform3D(aim_basis, pivot + aim_basis * gun_offset) * gun_extra
	if gun_mount:
		gun_mount.transform = gun

	if not arms_enabled:
		return
	var grip_right := gun * Vector3(0, -0.01, 0.03)
	var grip_left := gun * Vector3(0, -0.015, -foregrip)
	_solve_arm(skeleton, "upperarm_r", "lowerarm_r", "hand_r", "middle_01_r", grip_right, Vector3(1.0, -1.0, 0.4), gun.basis * Vector3(0, -0.4, -1))
	_solve_arm(skeleton, "upperarm_l", "lowerarm_l", "hand_l", "middle_01_l", grip_left, Vector3(-0.6, -1.0, 0.2), gun.basis * Vector3(0.3, 0.2, -1))


# --------------------------------------------------------------------------- outils

## Passage repère squelette <-> repère personnage.
func _skel_to_rig() -> Transform3D:
	return rig.global_transform.affine_inverse() * get_skeleton().global_transform


func _bone_global_rig(skeleton: Skeleton3D, bone_name: String) -> Transform3D:
	return _skel_to_rig() * skeleton.get_bone_global_pose(_bones[bone_name])


func _set_bone_global_rig(skeleton: Skeleton3D, bone_name: String, pose: Transform3D) -> void:
	skeleton.set_bone_global_pose(_bones[bone_name], _skel_to_rig().affine_inverse() * pose)


func _bone_pos(skeleton: Skeleton3D, bone_name: String) -> Vector3:
	return _bone_global_rig(skeleton, bone_name).origin


## Applique une rotation (exprimée dans le repère du personnage) autour de l'articulation.
func _rotate_bone(skeleton: Skeleton3D, bone_name: String, rotation: Basis) -> void:
	var pose := _bone_global_rig(skeleton, bone_name)
	pose.basis = rotation * pose.basis
	_set_bone_global_rig(skeleton, bone_name, pose)


## Tourne un os pour que la direction os -> enfant pointe vers `target`.
func _aim_bone(skeleton: Skeleton3D, bone_name: String, child_name: String, target: Vector3) -> void:
	var pose := _bone_global_rig(skeleton, bone_name)
	var child := _bone_pos(skeleton, child_name)
	var from_dir := (child - pose.origin).normalized()
	var to_dir := (target - pose.origin).normalized()
	if from_dir.is_zero_approx() or to_dir.is_zero_approx():
		return
	var axis := from_dir.cross(to_dir)
	if axis.length_squared() < 1e-10:
		return
	var angle := from_dir.angle_to(to_dir)
	pose.basis = Basis(axis.normalized(), angle) * pose.basis
	_set_bone_global_rig(skeleton, bone_name, pose)


func _solve_arm(skeleton: Skeleton3D, upper: String, lower: String, hand: String, finger: String,
		target: Vector3, pole: Vector3, finger_dir: Vector3) -> void:
	var shoulder := _bone_pos(skeleton, upper)
	var elbow_now := _bone_pos(skeleton, lower)
	var wrist_now := _bone_pos(skeleton, hand)
	var upper_len := shoulder.distance_to(elbow_now)
	var lower_len := elbow_now.distance_to(wrist_now)

	var to_target := target - shoulder
	var distance := clampf(to_target.length(), 0.05, upper_len + lower_len - 0.001)
	var dir := to_target.normalized()
	var cos_a := (upper_len * upper_len + distance * distance - lower_len * lower_len) / (2.0 * upper_len * distance)
	var angle := acos(clampf(cos_a, -1.0, 1.0))
	var bend := (pole - dir * pole.dot(dir)).normalized()
	var elbow := shoulder + dir * cos(angle) * upper_len + bend * sin(angle) * upper_len
	var wrist := shoulder + dir * distance

	_aim_bone(skeleton, upper, lower, elbow)
	_aim_bone(skeleton, lower, hand, wrist)
	_aim_bone(skeleton, hand, finger, wrist + finger_dir.normalized() * 0.1)
