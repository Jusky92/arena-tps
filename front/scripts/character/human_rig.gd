class_name HumanRig
extends Node3D
## Personnage humain cyberpunk : corps Quaternius (CC0) animé par la bibliothèque
## d'animations Universal Animation Library (CC0), habillé d'une combinaison et
## d'équipement générés par code.
##
## Même interface que CharacterRig (build, set_state, kick, flash, play_death, reset) :
## le joueur, les mannequins et l'écran de choix peuvent utiliser l'un ou l'autre.
##
## Animation :
##   - jambes, hanches, respiration : clips importés (repos, marche, jogging, sprint,
##     accroupi, saut, mort) mélangés par un AnimationTree selon la vitesse ;
##   - bas du corps tourné vers le déplacement, buste vers la visée, mains sur
##     l'arme : AimIKModifier, appliqué après l'animation.

const ANIMATIONS := preload("res://assets/characters/animations/locomotion.res")
const FLASH_MATERIAL := preload("res://data/materials/flash.tres")

# Vitesses de référence des clips (m/s) pour le mélange de la locomotion.
const WALK_SPEED := 1.8
const JOG_SPEED := 5.0
const SPRINT_SPEED := 8.0
const CROUCH_WALK_SPEED := 1.8

var design_id := ""
var gun_mount: Node3D
var foregrip := 0.3
var skeleton: Skeleton3D

# État d'entrée (rempli par set_state).
var move_velocity := Vector3.ZERO
var on_floor := true
var crouch_target := 0.0
var aim_pitch := 0.0
var sprinting := false
var aiming := false

var _model: Node3D
var _body_root: Node3D
var _tree: AnimationTree
var _ik: AimIKModifier
var _parts: Array[MeshInstance3D] = []
var _flash_targets: Array[GeometryInstance3D] = []
var _attachments := {}
var _weapon_grips := {}            # nœud d'arme -> distance de la main gauche
var _crouch := 0.0
var _air := 0.0
var _speed := 0.0
var _yaw := 0.0
var _backward := 0.0
var _sprint_pose := 0.0
var _kick := 0.0
var _time := 0.0
var _dead := false


# =========================================================================== construction

func build(id: String, weapon_kind: int, weapon_node: Node3D = null) -> void:
	design_id = id
	var design: Dictionary = HumanDesigns.DESIGNS[id]
	var body: Dictionary = HumanDesigns.body_of(id)

	# Corps importé, tourné de 180° (le modèle regarde vers +Z, le jeu vers -Z).
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	_model.rotation.y = PI
	_body_root = load(body.scene).instantiate()
	_model.add_child(_body_root)
	skeleton = _body_root.find_child("Skeleton3D", true, false)

	# Combinaison : on remplace le matériau du corps (pas des yeux / sourcils).
	for child in skeleton.get_children():
		if child is MeshInstance3D:
			_flash_targets.append(child)
			if str(child.name).to_lower().begins_with("superhero"):
				child.material_override = HumanDesigns.suit_material(id)

	# Cheveux : maillages "riggés" sur le même squelette, teints aux couleurs de la classe.
	for hair_name in design.hair:
		_add_hair(HumanDesigns.HAIR_DIR % hair_name, design.hair_color)

	HumanDesigns.build_gear(self, id)

	# Arme : accrochée à un nœud placé chaque image devant la poitrine par l'IK.
	gun_mount = Node3D.new()
	gun_mount.name = "GunMount"
	add_child(gun_mount)
	var weapon_info := CharacterDesigns.build_weapon(self, weapon_kind, id, weapon_node)
	foregrip = weapon_info.foregrip
	if weapon_node:
		_weapon_grips[weapon_node] = foregrip
		weapon_node.reparent(gun_mount, false)
		weapon_node.transform = Transform3D.IDENTITY
	_merge_parts()

	_build_animation_tree()

	_ik = AimIKModifier.new()
	_ik.rig = self
	_ik.gun_mount = gun_mount
	_ik.foregrip = foregrip
	skeleton.add_child(_ik)


func _add_hair(path: String, color: Color) -> void:
	var hair_scene: Node = load(path).instantiate()
	for mesh in hair_scene.find_children("*", "MeshInstance3D", true, false):
		var instance := mesh as MeshInstance3D
		instance.owner = null
		instance.reparent(skeleton, false)
		instance.skeleton = NodePath("..")
		var material := instance.get_active_material(0)
		if material is StandardMaterial3D:
			var tinted: StandardMaterial3D = material.duplicate()
			tinted.albedo_color = color
			instance.material_override = tinted
		_flash_targets.append(instance)
	hair_scene.queue_free()


## Accroche une pièce d'équipement à un os (décalage en T-pose, repère du personnage).
func attach(bone_name: String, offset: Vector3, size: Vector3, roundness: float, material: Material,
		rotation_deg := Vector3.ZERO, taper := Vector2.ONE, vertical := -1.0) -> MeshInstance3D:
	var attachment: BoneAttachment3D = _attachments.get(bone_name)
	if attachment == null:
		attachment = BoneAttachment3D.new()
		attachment.bone_name = bone_name
		skeleton.add_child(attachment)
		_attachments[bone_name] = attachment
	var bone := skeleton.find_bone(bone_name)
	var flip := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)   # repère personnage -> modèle
	var rest := skeleton.get_bone_global_rest(bone)
	var wanted := flip * Transform3D(Basis.from_euler(rotation_deg * (PI / 180.0)), (flip.affine_inverse() * rest.origin) + offset)
	var part := MeshInstance3D.new()
	var r := PartMesh.smooth(roundness, vertical, PartMesh.SMOOTH_GEAR)
	part.mesh = PartMesh.shape(size, r.x, r.y, taper)
	part.material_override = material
	attachment.add_child(part)
	part.transform = rest.affine_inverse() * wanted
	_parts.append(part)
	return part


## Utilisé par CharacterDesigns.build_weapon pour modéliser l'arme.
func add_part(bone: Node3D, size: Vector3, roundness: float, offset: Vector3, material: Material,
		rotation_deg := Vector3.ZERO, taper := Vector2.ONE, vertical := -1.0) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var r := PartMesh.smooth(roundness, vertical, PartMesh.SMOOTH_WEAPON)
	part.mesh = PartMesh.shape(size, r.x, r.y, taper)
	part.material_override = material
	bone.add_child(part)
	part.position = offset
	part.rotation_degrees = rotation_deg
	_parts.append(part)
	return part


## Fusionne les pièces d'un même parent et d'un même matériau (moins d'appels de rendu).
## Seules les pièces à partir de `from_index` sont traitées (arme ajoutée après coup).
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
	for part in merged:
		_flash_targets.append(part)
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


## Arbre d'animation : locomotion (repos -> marche -> jogging -> sprint), accroupi,
## saut, et mort. Les paramètres sont réglés à chaque image dans _update().
func _build_animation_tree() -> void:
	_tree = AnimationTree.new()
	_tree.name = "AnimationTree"
	add_child(_tree)
	_tree.add_animation_library("", ANIMATIONS)
	_tree.root_node = _tree.get_path_to(_body_root)

	var blend := AnimationNodeBlendTree.new()

	var move := AnimationNodeBlendSpace1D.new()
	move.add_blend_point(_clip("Idle"), 0.0, -1, "idle")
	move.add_blend_point(_clip("Walk"), WALK_SPEED, -1, "walk")
	move.add_blend_point(_clip("Jog_Fwd"), JOG_SPEED, -1, "jog")
	move.add_blend_point(_clip("Sprint"), SPRINT_SPEED, -1, "sprint")
	move.min_space = 0.0
	move.max_space = SPRINT_SPEED
	blend.add_node("move", move, Vector2(0, 0))

	var crouch := AnimationNodeBlendSpace1D.new()
	crouch.add_blend_point(_clip("Crouch_Idle"), 0.0, -1, "idle")
	crouch.add_blend_point(_clip("Crouch_Fwd"), CROUCH_WALK_SPEED, -1, "walk")
	crouch.min_space = 0.0
	crouch.max_space = CROUCH_WALK_SPEED
	blend.add_node("crouch", crouch, Vector2(0, 200))

	blend.add_node("ground", AnimationNodeBlend2.new(), Vector2(250, 100))
	blend.connect_node("ground", 0, "move")
	blend.connect_node("ground", 1, "crouch")

	var direction := AnimationNodeTimeScale.new()   # -1 = marche arrière
	blend.add_node("direction", direction, Vector2(450, 100))
	blend.connect_node("direction", 0, "ground")

	blend.add_node("air_clip", _clip("Jump"), Vector2(450, 300))
	blend.add_node("air", AnimationNodeBlend2.new(), Vector2(650, 150))
	blend.connect_node("air", 0, "direction")
	blend.connect_node("air", 1, "air_clip")

	var death := _clip("Death01")
	blend.add_node("death_clip", death, Vector2(650, 350))
	var life := AnimationNodeTransition.new()
	life.add_input("alive")
	life.add_input("dead")
	life.xfade_time = 0.15
	blend.add_node("life", life, Vector2(850, 200))
	blend.connect_node("life", 0, "air")
	blend.connect_node("life", 1, "death_clip")
	blend.connect_node("output", 0, "life")

	_tree.tree_root = blend
	_tree.active = true
	_tree.set("parameters/direction/scale", 1.0)
	_tree.set("parameters/life/transition_request", "alive")


func _clip(clip_name: String) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip_name
	return node


# =========================================================================== état et effets

func set_state(velocity_local: Vector3, is_on_floor: bool, crouch_amount: float, pitch: float,
		is_sprinting := false, is_aiming := false) -> void:
	move_velocity = velocity_local
	on_floor = is_on_floor
	crouch_target = crouch_amount
	aim_pitch = pitch
	sprinting = is_sprinting
	aiming = is_aiming


func kick(recoil_deg: float) -> void:
	_kick = minf(_kick + 0.02 + recoil_deg * 0.012, 0.14)


func flash() -> void:
	for target in _flash_targets:
		if is_instance_valid(target):
			target.material_overlay = FLASH_MATERIAL
	get_tree().create_timer(0.07).timeout.connect(func() -> void:
		for target in _flash_targets:
			if is_instance_valid(target):
				target.material_overlay = null)


func play_death() -> void:
	_dead = true
	_ik.arms_enabled = false
	gun_mount.visible = false
	_tree.set("parameters/life/transition_request", "dead")
	_tree.set("parameters/direction/scale", 1.0)


func reset() -> void:
	_dead = false
	_ik.arms_enabled = true
	gun_mount.visible = true
	_crouch = 0.0
	_air = 0.0
	_tree.set("parameters/life/transition_request", "alive")


# =========================================================================== animation

func _process(delta: float) -> void:
	if _tree == null:
		return
	_time += delta
	var flat := Vector2(move_velocity.x, move_velocity.z)
	var speed := flat.length()

	_crouch = move_toward(_crouch, crouch_target, delta * 6.0)
	_air = move_toward(_air, 0.0 if on_floor else 1.0, delta * (10.0 if on_floor else 4.0))
	_speed = lerpf(_speed, speed, minf(delta * 10.0, 1.0))
	_sprint_pose = lerpf(_sprint_pose, 1.0 if sprinting and not aiming else 0.0, minf(delta * 8.0, 1.0))

	# Direction de déplacement par rapport au regard : 0 = devant, PI/2 = à droite.
	var target_yaw := 0.0
	var backward := 0.0
	if speed > 0.4:
		var angle := atan2(move_velocity.x, -move_velocity.z)
		if absf(angle) > deg_to_rad(110.0):
			backward = 1.0
			angle = wrapf(angle + PI, -PI, PI)
		target_yaw = clampf(angle, -deg_to_rad(75.0), deg_to_rad(75.0))
	_yaw = lerp_angle(_yaw, -target_yaw, minf(delta * 8.0, 1.0))
	_backward = move_toward(_backward, backward, delta * 8.0)

	_tree.set("parameters/move/blend_position", _speed)
	_tree.set("parameters/crouch/blend_position", minf(_speed, CROUCH_WALK_SPEED))
	_tree.set("parameters/ground/blend_amount", smoothstep(0.0, 1.0, _crouch))
	_tree.set("parameters/air/blend_amount", smoothstep(0.0, 1.0, _air))
	if not _dead:
		_tree.set("parameters/direction/scale", -1.0 if _backward > 0.5 else 1.0)

	# Paramètres de l'IK : visée, rotation du bas du corps, position de l'arme.
	_kick = move_toward(_kick, 0.0, delta * 0.9)
	var bob := sin(_time * 9.0) * 0.008 * clampf(_speed / JOG_SPEED, 0.0, 1.0)
	var lowered := Basis(Vector3.RIGHT, -0.7 * _sprint_pose) * Basis(Vector3.UP, 0.5 * _sprint_pose)
	_ik.aim_pitch = aim_pitch
	_ik.lower_body_yaw = _yaw
	_ik.gun_extra = Transform3D(Basis(Vector3.RIGHT, _kick * 2.2) * lowered, Vector3(0, bob - 0.05 * _air, _kick))
