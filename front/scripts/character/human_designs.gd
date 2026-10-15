class_name HumanDesigns
extends RefCounted
## Chara design des personnages (corps Quaternius, CC0), thème « néo-Edo » :
## armure de samouraï, tenue de shinobi, archer de kyūdō et démon oni, revisités
## en cyberpunk.
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
	# 侍 — samouraï : sous-combinaison noire, plaques de laque rouge, chignon et barbe.
	"tank": {
		"body": "male", "hair": ["Hair_Buzzed", "Hair_Beard"], "hair_color": Color(0.1, 0.08, 0.07),
		"primary": Color(0.12, 0.1, 0.11), "secondary": Color(0.46, 0.1, 0.09),
		"dark": Color(0.04, 0.04, 0.05), "neon": Color(1.0, 0.45, 0.2),
	},
	# 忍 — shinobi : tenue indigo près du corps, liserés violets.
	"assassin": {
		"body": "female", "hair": ["Hair_Buns"], "hair_color": Color(0.08, 0.07, 0.09),
		"primary": Color(0.07, 0.08, 0.14), "secondary": Color(0.2, 0.16, 0.42),
		"dark": Color(0.03, 0.03, 0.05), "neon": Color(0.8, 0.35, 1.0),
	},
	# 弓 — archer : haut blanc, hakama bleu nuit, liserés dorés.
	"tireur": {
		"body": "male", "hair": ["Hair_SimpleParted"], "hair_color": Color(0.09, 0.08, 0.08),
		"primary": Color(0.88, 0.88, 0.9), "secondary": Color(0.11, 0.18, 0.4),
		"dark": Color(0.07, 0.08, 0.12), "neon": Color(0.3, 0.8, 1.0),
	},
	# 鬼 — oni : démon en armure lourde, masque à cornes, néon vert acide.
	"oni": {
		"body": "male", "hair": ["Hair_Buzzed"], "hair_color": Color(0.06, 0.06, 0.05),
		"primary": Color(0.08, 0.09, 0.07), "secondary": Color(0.22, 0.42, 0.1),
		"dark": Color(0.04, 0.05, 0.04), "neon": Color(0.55, 1.0, 0.25),
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
##
## Thème néo-Edo. Vocabulaire des pièces japonaises utilisé dans les commentaires :
##   dō        cuirasse             sode     épaulière
##   kusazuri  jupe de plaques      kabuto   casque
##   menpō     masque de visage     maedate  ornement frontal du casque
##   obi       large ceinture       hakama   pantalon ample
##   tekkō     protège-main         kyahan   jambière
##   tabi      chausson fendu       hachimaki bandeau de front
static func build_gear(rig: HumanRig, design_id: String) -> void:
	var m := CharacterDesigns.materials(design_id)
	var w: float = body_of(design_id).width

	# --- Commun aux trois classes ---
	# Obi : large ceinture, avec son nœud dans le dos.
	rig.attach("pelvis", Vector3(0, 0.08, 0), Vector3(0.37 * w, 0.13, 0.27 * w), 0.4, m.armor2)
	rig.attach("pelvis", Vector3(0, 0.08, 0.14 * w), Vector3(0.12, 0.1, 0.1), 0.5, m.armor2)
	rig.attach("pelvis", Vector3(0, 0.07, -0.142 * w), Vector3(0.09, 0.022, 0.015), 0.3, m.glow)
	# Kusazuri : plaques suspendues à la ceinture, devant et derrière.
	rig.attach("pelvis", Vector3(0, -0.07, -0.12 * w), Vector3(0.2 * w, 0.22, 0.03), 0.2, m.armor, Vector3(-8, 0, 0))
	rig.attach("pelvis", Vector3(0, -0.07, 0.13 * w), Vector3(0.22 * w, 0.22, 0.03), 0.2, m.armor, Vector3(8, 0, 0))
	# Tekkō (protège-avant-bras), kyahan (jambières) et épaulières légères.
	for side in [-1.0, 1.0]:
		var s := "r" if side > 0 else "l"
		rig.attach("pelvis", Vector3(side * 0.17 * w, -0.06, 0), Vector3(0.03, 0.2, 0.19 * w), 0.2, m.armor, Vector3(0, 0, side * 6.0))
		rig.attach("lowerarm_" + s, Vector3(side * 0.14, 0.005, 0), Vector3(0.16, 0.08 * w + 0.012, 0.085 * w + 0.012), 0.35, m.armor2)
		rig.attach("lowerarm_" + s, Vector3(side * 0.2, 0.0, 0), Vector3(0.04, 0.085 * w, 0.09 * w), 0.3, m.trim)
		rig.attach("lowerarm_" + s, Vector3(side * 0.14, 0.055 * w, 0), Vector3(0.1, 0.012, 0.022), 0.3, m.glow)
		rig.attach("calf_" + s, Vector3(0, -0.04, -0.055 * w), Vector3(0.105 * w, 0.2, 0.06), 0.3, m.armor2)
		rig.attach("upperarm_" + s, Vector3(side * 0.05, 0.07 * w, 0), Vector3(0.16 * w, 0.06, 0.18 * w), 0.3, m.armor, Vector3(0, 0, side * -10.0))
	# Tabi : chaussons à semelle épaisse (les pieds du modèle sont nus).
	for s in ["l", "r"]:
		rig.attach("foot_" + s, Vector3(0, 0.02, 0.005), Vector3(0.105 * w + 0.012, 0.15, 0.12), 0.45, m.armor2)
		rig.attach("foot_" + s, Vector3(0, -0.035, -0.06), Vector3(0.1 * w + 0.018, 0.1, 0.25), 0.35, m.armor2, Vector3.ZERO, Vector2(1.0, 0.9))
		rig.attach("foot_" + s, Vector3(0, -0.079, -0.06), Vector3(0.105 * w + 0.022, 0.03, 0.26), 0.2, m.trim)

	match design_id:
		"tank":
			# 侍 SAMOURAÏ : cuirasse à lamelles, grandes épaulières, kabuto et menpō.
			# Dō : trois registres de lamelles laquées, alternées.
			for i in 3:
				rig.attach("spine_03", Vector3(0, 0.04 - i * 0.09, -0.108 * w), Vector3(0.32 * w, 0.085, 0.07), 0.25,
					m.armor if i % 2 == 0 else m.armor2, Vector3(-5, 0, 0), Vector2(0.9, 1.0))
			rig.attach("spine_03", Vector3(0, -0.05, 0.13 * w), Vector3(0.3 * w, 0.34, 0.08), 0.3, m.armor)
			rig.attach("spine_03", Vector3(0, 0.05, -0.152 * w), Vector3(0.1 * w, 0.025, 0.012), 0.3, m.glow)
			for side in [-1.0, 1.0]:
				var s := "r" if side > 0 else "l"
				# Sode : épaulière en deux plaques superposées.
				for i in 2:
					rig.attach("upperarm_" + s, Vector3(side * (0.06 + i * 0.04), 0.07 - i * 0.07, 0),
						Vector3(0.1, 0.08, 0.26 - i * 0.02), 0.2, m.armor, Vector3(0, 0, side * -14.0))
				rig.attach("upperarm_" + s, Vector3(side * 0.13, 0.08, 0), Vector3(0.02, 0.02, 0.22), 0.3, m.glow, Vector3(0, 0, side * -14.0))
				# Sashimono : petite bannière dorsale sur sa hampe.
				rig.attach("spine_03", Vector3(side * 0.13, 0.02, 0.21), Vector3(0.02, 0.46, 0.02), 0.3, m.trim, Vector3(10, 0, side * 10.0))
				rig.attach("spine_03", Vector3(side * 0.15, 0.2, 0.22), Vector3(0.1, 0.17, 0.012), 0.1, m.armor, Vector3(10, 0, side * 10.0))
			# Kabuto : bombe, nuquière en plaques, maedate en croissant doré.
			rig.attach("Head", Vector3(0, 0.105, 0.0), Vector3(0.225, 0.19, 0.245), 0.85, m.armor, Vector3.ZERO, Vector2(1.0, 0.85))
			rig.attach("Head", Vector3(0, 0.035, 0.0), Vector3(0.235, 0.035, 0.25), 0.6, m.trim)
			rig.attach("Head", Vector3(0, 0.215, 0.0), Vector3(0.07, 0.05, 0.07), 0.9, m.trim)
			rig.attach("Head", Vector3(0, 0.055, 0.075), Vector3(0.26, 0.05, 0.14), 0.3, m.armor, Vector3(28, 0, 0))
			rig.attach("Head", Vector3(0, 0.015, 0.1), Vector3(0.24, 0.05, 0.12), 0.3, m.armor, Vector3(34, 0, 0))
			rig.attach("Head", Vector3(0, 0.185, -0.055), Vector3(0.16, 0.1, 0.02), 0.9, m.trim, Vector3(-12, 0, 0), Vector2(0.25, 1.0))
			# Menpō : masque de visage et respirateur lumineux.
			rig.attach("Head", Vector3(0, 0.0, -0.085), Vector3(0.17, 0.12, 0.08), 0.55, m.armor2, Vector3(6, 0, 0))
			rig.attach("Head", Vector3(0, -0.015, -0.12), Vector3(0.1, 0.035, 0.03), 0.4, m.glow)
		"assassin":
			# 忍 SHINOBI : capuche et masque, katana dans le dos, étui à shuriken.
			rig.attach("spine_03", Vector3(0, -0.02, -0.1 * w), Vector3(0.26 * w, 0.26, 0.05), 0.3, m.armor, Vector3(-6, 0, 0), Vector2(0.85, 1.0))
			rig.attach("spine_03", Vector3(0, 0.04, -0.13 * w), Vector3(0.1 * w, 0.02, 0.012), 0.3, m.glow)
			# Capuche et masque : seule la bande des yeux reste découverte.
			rig.attach("Head", Vector3(0, 0.085, 0.02), Vector3(0.23, 0.14, 0.25), 0.8, m.armor, Vector3.ZERO, Vector2(1.0, 0.9))
			rig.attach("Head", Vector3(0, -0.03, -0.055), Vector3(0.17, 0.12, 0.13), 0.65, m.armor2)
			rig.attach("neck_01", Vector3(0, 0.02, 0), Vector3(0.16, 0.09, 0.15), 0.6, m.armor)
			for side in [-1.0, 1.0]:
				rig.attach("Head", Vector3(side * 0.04, 0.045, -0.09), Vector3(0.07, 0.016, 0.02), 0.3, m.glow, Vector3(0, side * -14.0, side * 8.0))
			# Écharpe flottant derrière la nuque.
			rig.attach("neck_01", Vector3(0, -0.02, 0.1), Vector3(0.1, 0.42, 0.03), 0.25, m.armor2, Vector3(16, 0, 10))
			# Katana en bandoulière : fourreau, garde et poignée.
			rig.attach("spine_03", Vector3(0.02, 0.0, 0.17), Vector3(0.035, 0.78, 0.035), 0.35, m.armor2, Vector3(0, 0, 28))
			rig.attach("spine_03", Vector3(-0.17, 0.32, 0.17), Vector3(0.028, 0.2, 0.028), 0.4, m.trim, Vector3(0, 0, 28))
			rig.attach("spine_03", Vector3(-0.1, 0.19, 0.17), Vector3(0.09, 0.02, 0.09), 0.9, m.trim, Vector3(0, 0, 28))
			# Étui à shuriken sur la cuisse.
			rig.attach("thigh_r", Vector3(0.1 * w, -0.14, 0), Vector3(0.05, 0.14, 0.11), 0.3, m.armor2)
			rig.attach("thigh_r", Vector3(0.125 * w, -0.14, 0), Vector3(0.012, 0.09, 0.09), 0.2, m.glow)
		"oni":
			# 鬼 ONI : grosse cuirasse bombée, épaulières massives, masque à crocs et
			# cornes, kanabō (massue cloutée) dans le dos.
			rig.attach("spine_03", Vector3(0, -0.01, -0.115 * w), Vector3(0.36 * w, 0.34, 0.11), 0.75, m.armor, Vector3(-5, 0, 0), Vector2(0.88, 1.0))
			rig.attach("spine_03", Vector3(0, -0.04, 0.13 * w), Vector3(0.32 * w, 0.32, 0.1), 0.75, m.armor)
			rig.attach("spine_03", Vector3(0, 0.07, -0.172 * w), Vector3(0.14 * w, 0.025, 0.012), 0.6, m.glow)
			for side in [-1.0, 1.0]:
				var s := "r" if side > 0 else "l"
				# Épaulières massives et gantelets lourds.
				rig.attach("upperarm_" + s, Vector3(side * 0.07, 0.08, 0), Vector3(0.21, 0.13, 0.27), 0.8, m.armor, Vector3(0, 0, side * -14.0))
				rig.attach("upperarm_" + s, Vector3(side * 0.13, 0.1, 0), Vector3(0.025, 0.025, 0.22), 0.8, m.glow, Vector3(0, 0, side * -14.0))
				rig.attach("lowerarm_" + s, Vector3(side * 0.13, 0.0, 0), Vector3(0.18, 0.12 * w + 0.01, 0.12 * w + 0.01), 0.75, m.armor)
				# Cornes : coniques, légèrement écartées vers l'arrière.
				rig.attach("Head", Vector3(side * 0.08, 0.2, -0.01), Vector3(0.05, 0.2, 0.05), 0.9, m.trim, Vector3(-12, 0, side * -24.0), Vector2(1.0, 0.12))
				# Yeux lumineux et crocs du masque.
				rig.attach("Head", Vector3(side * 0.045, 0.045, -0.135), Vector3(0.05, 0.02, 0.02), 0.9, m.glow, Vector3(0, 0, side * 10.0))
				rig.attach("Head", Vector3(side * 0.035, -0.05, -0.135), Vector3(0.022, 0.05, 0.022), 0.8, m.trim, Vector3.ZERO, Vector2(0.25, 1.0))
			# Casque arrondi et masque d'oni.
			rig.attach("Head", Vector3(0, 0.11, 0.0), Vector3(0.235, 0.15, 0.255), 0.9, m.armor, Vector3.ZERO, Vector2(1.0, 0.85))
			rig.attach("Head", Vector3(0, 0.01, -0.09), Vector3(0.2, 0.18, 0.1), 0.75, m.armor2, Vector3(4, 0, 0))
			# Kanabō dans le dos : massue cloutée, clous lumineux.
			rig.attach("spine_03", Vector3(0.1, 0.0, 0.2), Vector3(0.08, 0.7, 0.08), 0.8, m.armor2, Vector3(0, 0, 24), Vector2(0.6, 1.25))
			for i in 3:
				rig.attach("spine_03", Vector3(0.1 - 0.06 * i, 0.12 + 0.11 * i, 0.25), Vector3(0.03, 0.03, 0.03), 1.0, m.glow, Vector3(0, 0, 24))
		"tireur":
			# 弓 ARCHER : plastron en diagonale, hakama, carquois et viseur.
			rig.attach("spine_03", Vector3(0, -0.02, -0.1 * w), Vector3(0.28 * w, 0.24, 0.05), 0.3, m.armor, Vector3(-6, 0, 0), Vector2(0.85, 1.0))
			rig.attach("spine_03", Vector3(0, 0.04, -0.132 * w), Vector3(0.11 * w, 0.02, 0.012), 0.3, m.glow)
			# Muneate : protection de poitrine en diagonale, typique du tir à l'arc.
			rig.attach("spine_03", Vector3(-0.02, 0.0, -0.115 * w), Vector3(0.1, 0.34, 0.02), 0.25, m.armor2, Vector3(0, 0, 28))
			# Hakama : pans amples qui tombent de la ceinture.
			for side in [-1.0, 1.0]:
				rig.attach("thigh_" + ("r" if side > 0 else "l"), Vector3(side * 0.012, -0.12, 0),
					Vector3(0.185 * w, 0.44, 0.19 * w), 0.45, m.armor2, Vector3(0, 0, side * 3.0), Vector2(1.22, 1.0))
			# Carquois incliné dans le dos, et ses flèches qui dépassent.
			rig.attach("spine_03", Vector3(-0.09, 0.02, 0.18), Vector3(0.08, 0.42, 0.08), 0.6, m.armor2, Vector3(12, 0, -18))
			for i in 3:
				rig.attach("spine_03", Vector3(-0.13 + i * 0.03, 0.3, 0.2), Vector3(0.012, 0.22, 0.012), 0.5, m.trim, Vector3(12, 0, -18))
			# Hachimaki : bandeau de front avec son disque rouge et son pan flottant.
			rig.attach("Head", Vector3(0, 0.135, -0.01), Vector3(0.23, 0.04, 0.24), 0.7, m.armor2)
			rig.attach("Head", Vector3(0, 0.135, -0.122), Vector3(0.05, 0.038, 0.02), 0.9, m.armor)
			rig.attach("Head", Vector3(-0.095, 0.11, 0.12), Vector3(0.03, 0.24, 0.02), 0.3, m.armor2, Vector3(20, 0, 14))
			# Viseur sur l'œil droit, relié à une petite antenne.
			rig.attach("Head", Vector3(0.04, 0.045, -0.085), Vector3(0.06, 0.055, 0.05), 0.9, m.trim, Vector3(90, 0, 0), Vector2.ONE, 0.25)
			rig.attach("Head", Vector3(0.04, 0.045, -0.112), Vector3(0.045, 0.014, 0.035), 0.9, m.glow, Vector3(90, 0, 0), Vector2.ONE, 0.3)
			rig.attach("Head", Vector3(-0.085, 0.16, 0.02), Vector3(0.01, 0.18, 0.01), 0.9, m.trim, Vector3.ZERO, Vector2.ONE, 0.9)
			rig.attach("Head", Vector3(-0.085, 0.25, 0.02), Vector3(0.02, 0.02, 0.02), 1.0, m.glow)
