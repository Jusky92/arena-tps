class_name HumanDesigns
extends RefCounted
## Chara design des personnages humains cyberpunk (corps Quaternius, CC0).
##
## Chaque classe = un corps (homme / femme), une coupe de cheveux teinte, les
## couleurs de sa combinaison et de l'équipement accroché aux os (plastron,
## épaulières, visière lumineuse...).
##
## Les positions d'équipement sont des décalages depuis l'articulation de l'os,
## dans le repère du personnage en T-pose (avant = -Z, droite = +X, haut = +Y).

const BODIES := {
	"male": {
		"scene": "res://assets/characters/quaternius/base/Superhero_Male_FullBody.gltf",
		"albedo": "res://assets/characters/quaternius/textures/df680cbc1967a61e85998bfafb8f7bc0a36dd604bb3266486c4b06b1a184bb45.png",
		"normal": "res://assets/characters/quaternius/textures/9b25cf9200216eb754b79cf4c63b5380c419780788322f3c57cdd2b3e02679a6.png",
		"orm": "res://assets/characters/quaternius/textures/c70dabf48574cda55644d556beae1ee7cf1bdcf68a50d259d20f2f2358f27991.png",
		"mask": "res://assets/characters/quaternius/textures/suit_mask_male.png",
		"width": 1.0,
	},
	"female": {
		"scene": "res://assets/characters/quaternius/base/Superhero_Female_FullBody.gltf",
		"albedo": "res://assets/characters/quaternius/textures/d366843ee7d9e9f37ec87a0e1c98c7f2e45573c08eeb80a51a6d9344e68cf288.png",
		"normal": "res://assets/characters/quaternius/textures/cf922460b43ccd31e983e34db05514c9d451dd2f9cdd01a843978e797719f859.png",
		"orm": "res://assets/characters/quaternius/textures/d2beabf2bd0313e32c68dcdbb80dca371a6e994fabf96efa97128bf9f14fa57b.png",
		"mask": "res://assets/characters/quaternius/textures/suit_mask_female.png",
		"width": 0.8,
	},
}

const HAIR_DIR := "res://assets/characters/quaternius/hair/%s.gltf"

const DESIGNS := {
	"tank": {
		"body": "male", "hair": ["Hair_Buzzed", "Hair_Beard"], "hair_color": Color(0.22, 0.16, 0.1),
		"primary": Color(0.13, 0.16, 0.12), "secondary": Color(0.3, 0.42, 0.24),
		"dark": Color(0.05, 0.05, 0.05), "neon": Color(0.35, 1.0, 0.45),
	},
	"assassin": {
		"body": "female", "hair": ["Hair_Buns"], "hair_color": Color(0.62, 0.22, 0.95),
		"primary": Color(0.07, 0.065, 0.09), "secondary": Color(0.36, 0.14, 0.52),
		"dark": Color(0.03, 0.03, 0.04), "neon": Color(0.85, 0.35, 1.0),
	},
	"tireur": {
		"body": "male", "hair": ["Hair_SimpleParted"], "hair_color": Color(0.85, 0.88, 0.95),
		"primary": Color(0.72, 0.74, 0.78), "secondary": Color(0.16, 0.36, 0.72),
		"dark": Color(0.08, 0.09, 0.11), "neon": Color(0.25, 0.85, 1.0),
	},
}

const SUIT_SHADER := preload("res://shaders/cyber_suit.gdshader")

static var _suit_cache := {}


static func has_design(design_id: String) -> bool:
	return DESIGNS.has(design_id)


static func body_of(design_id: String) -> Dictionary:
	return BODIES[DESIGNS[design_id].body]


## Matériau de combinaison (partagé entre tous les personnages d'une même classe).
static func suit_material(design_id: String) -> ShaderMaterial:
	if _suit_cache.has(design_id):
		return _suit_cache[design_id]
	var d: Dictionary = DESIGNS[design_id]
	var body: Dictionary = BODIES[d.body]
	var material := ShaderMaterial.new()
	material.shader = SUIT_SHADER
	material.set_shader_parameter("skin_albedo", load(body.albedo))
	material.set_shader_parameter("skin_normal", load(body.normal))
	material.set_shader_parameter("skin_orm", load(body.orm))
	material.set_shader_parameter("suit_mask", load(body.mask))
	material.set_shader_parameter("primary_color", d.primary)
	material.set_shader_parameter("secondary_color", d.secondary)
	material.set_shader_parameter("dark_color", d.dark)
	material.set_shader_parameter("neon_color", d.neon)
	_suit_cache[design_id] = material
	return material


## Équipement : appelle rig.attach(os, décalage, taille, arrondi, matériau, rotation, taper, arrondi vertical).
static func build_gear(rig: HumanRig, design_id: String) -> void:
	var m := CharacterDesigns.materials(design_id)
	var w: float = body_of(design_id).width

	# Commun : ceinture, plastron, sac, protège-avant-bras, genouillères, holster.
	rig.attach("pelvis", Vector3(0, 0.07, -0.005), Vector3(0.36 * w, 0.07, 0.26 * w), 0.35, m.trim)
	rig.attach("pelvis", Vector3(0, 0.07, -0.135 * w), Vector3(0.07, 0.045, 0.02), 0.3, m.glow)
	rig.attach("spine_03", Vector3(0, -0.02, -0.105 * w), Vector3(0.3 * w, 0.22, 0.07), 0.32, m.armor, Vector3(-6, 0, 0), Vector2(0.85, 1.0))
	rig.attach("spine_03", Vector3(0, 0.03, -0.142 * w), Vector3(0.12 * w, 0.02, 0.012), 0.3, m.glow)
	rig.attach("spine_03", Vector3(0, -0.05, 0.14 * w), Vector3(0.26 * w, 0.3, 0.1), 0.35, m.armor2)
	for side in [-1.0, 1.0]:
		var s := "r" if side > 0 else "l"
		rig.attach("lowerarm_" + s, Vector3(side * 0.13, 0.005, 0), Vector3(0.17, 0.075 * w + 0.01, 0.08 * w + 0.01), 0.4, m.armor2)
		rig.attach("lowerarm_" + s, Vector3(side * 0.13, 0.05 * w, 0), Vector3(0.12, 0.012, 0.025), 0.3, m.glow)
		rig.attach("calf_" + s, Vector3(0, -0.02, -0.065 * w), Vector3(0.1 * w, 0.12, 0.05), 0.45, m.armor)
		rig.attach("upperarm_" + s, Vector3(side * 0.06, 0.06 * w, 0), Vector3(0.15 * w, 0.07, 0.16 * w), 0.45, m.armor, Vector3(0, 0, side * -10.0))
	rig.attach("thigh_r", Vector3(0.09 * w, -0.17, 0), Vector3(0.06, 0.16, 0.1), 0.35, m.armor2)
	# Bottes : tige, coque et semelle (les pieds du modèle sont nus).
	for s in ["l", "r"]:
		rig.attach("foot_" + s, Vector3(0, 0.02, 0.005), Vector3(0.105 * w + 0.015, 0.16, 0.13), 0.45, m.armor2)
		rig.attach("foot_" + s, Vector3(0, -0.035, -0.06), Vector3(0.1 * w + 0.02, 0.1, 0.26), 0.4, m.armor2, Vector3.ZERO, Vector2(1.0, 0.9))
		rig.attach("foot_" + s, Vector3(0, -0.079, -0.06), Vector3(0.105 * w + 0.022, 0.025, 0.27), 0.25, m.trim)

	match design_id:
		"tank":
			# Respirateur, grosses épaulières, plastron épais, bonbonnes dans le dos.
			rig.attach("Head", Vector3(0, 0.035, -0.105), Vector3(0.12, 0.075, 0.06), 0.45, m.armor2)
			for side in [-1.0, 1.0]:
				rig.attach("Head", Vector3(side * 0.055, 0.02, -0.12), Vector3(0.045, 0.045, 0.035), 1.0, m.trim, Vector3(90, 0, 0), Vector2.ONE, 0.3)
				var s := "r" if side > 0 else "l"
				rig.attach("upperarm_" + s, Vector3(side * 0.07, 0.08, 0), Vector3(0.22, 0.11, 0.24), 0.45, m.armor, Vector3(0, 0, side * -12.0))
				rig.attach("upperarm_" + s, Vector3(side * 0.12, 0.08, 0), Vector3(0.02, 0.02, 0.2), 0.3, m.glow, Vector3(0, 0, side * -12.0))
				rig.attach("spine_03", Vector3(side * 0.08, -0.03, 0.22), Vector3(0.09, 0.3, 0.09), 1.0, m.trim, Vector3.ZERO, Vector2.ONE, 0.15)
			rig.attach("Head", Vector3(0, 0.085, -0.095), Vector3(0.15, 0.025, 0.03), 0.4, m.glow)
			rig.attach("spine_03", Vector3(0, -0.13, -0.12), Vector3(0.28, 0.1, 0.06), 0.3, m.armor2)
		"assassin":
			# Visière en V, écharpe, lames dans le dos.
			for side in [-1.0, 1.0]:
				rig.attach("Head", Vector3(side * 0.035, 0.085, -0.088), Vector3(0.07, 0.022, 0.025), 0.35, m.glow, Vector3(0, side * -18.0, side * 10.0))
				rig.attach("spine_03", Vector3(side * 0.06, 0.0, 0.2), Vector3(0.02, 0.55, 0.06), 0.2, m.trim, Vector3(0, 0, side * 22.0))
			rig.attach("neck_01", Vector3(0, 0.02, -0.005), Vector3(0.15, 0.07, 0.14), 0.6, m.armor2)
			rig.attach("Head", Vector3(0, 0.03, -0.075), Vector3(0.1, 0.06, 0.06), 0.55, m.armor2)
		"tireur":
			# Monocle de visée, antenne, pans de manteau.
			rig.attach("Head", Vector3(0.035, 0.085, -0.09), Vector3(0.05, 0.05, 0.06), 0.95, m.trim, Vector3(90, 0, 0), Vector2.ONE, 0.25)
			rig.attach("Head", Vector3(0.035, 0.085, -0.122), Vector3(0.04, 0.012, 0.04), 0.95, m.glow, Vector3(90, 0, 0), Vector2.ONE, 0.3)
			rig.attach("Head", Vector3(-0.08, 0.17, 0.03), Vector3(0.01, 0.2, 0.01), 0.9, m.trim, Vector3.ZERO, Vector2.ONE, 0.9)
			rig.attach("Head", Vector3(-0.08, 0.27, 0.03), Vector3(0.022, 0.022, 0.022), 1.0, m.glow)
			for side in [-1.0, 1.0]:
				rig.attach("pelvis", Vector3(side * 0.09, -0.15, 0.1), Vector3(0.15, 0.36, 0.02), 0.3, m.armor2, Vector3(12, 0, 0))
			rig.attach("spine_03", Vector3(0, 0.0, -0.13), Vector3(0.04, 0.38, 0.02), 0.3, m.trim, Vector3(0, 0, 35))
