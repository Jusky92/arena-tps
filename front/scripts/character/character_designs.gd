class_name CharacterDesigns
extends RefCounted
## Chara design des personnages : chaque classe = une palette + une liste de pièces
## accrochées au squelette (CharacterRig). Toutes les dimensions sont en mètres.
##
## Pour retoucher un personnage : modifier les tailles / positions ci-dessous.
## Pour créer une nouvelle apparence : ajouter une palette + une fonction _xxx().

# Palettes : armure principale, armure secondaire, combinaison, métal, lumière.
const PALETTES := {
	# Samouraï : laque rouge sombre, laçage noir, ferrures dorées.
	"tank": {
		"armor": Color(0.46, 0.09, 0.08), "armor2": Color(0.14, 0.12, 0.13),
		"suit": Color(0.1, 0.09, 0.1), "trim": Color(0.78, 0.6, 0.22), "glow": Color(1.0, 0.45, 0.2),
	},
	# Shinobi : indigo profond, acier froid, néon violet.
	"assassin": {
		"armor": Color(0.1, 0.13, 0.24), "armor2": Color(0.34, 0.18, 0.5),
		"suit": Color(0.06, 0.07, 0.1), "trim": Color(0.66, 0.68, 0.76), "glow": Color(0.8, 0.35, 1.0),
	},
	# Archer : laque blanche et bleu nuit, ferrures dorées.
	"tireur": {
		"armor": Color(0.86, 0.86, 0.88), "armor2": Color(0.12, 0.2, 0.42),
		"suit": Color(0.12, 0.13, 0.18), "trim": Color(0.78, 0.64, 0.3), "glow": Color(0.3, 0.8, 1.0),
	},
	"dummy": {
		"armor": Color(0.9, 0.45, 0.1), "armor2": Color(0.24, 0.24, 0.26),
		"suit": Color(0.2, 0.2, 0.21), "trim": Color(0.95, 0.78, 0.1), "glow": Color(1.0, 0.25, 0.2),
	},
}

## Carrure : élargit le torse et les membres (la hauteur ne change pas).
const BULK := {"tank": 1.2, "assassin": 0.88, "tireur": 1.0, "dummy": 1.05}

static var _material_cache := {}


static func bulk(design_id: String) -> float:
	return BULK.get(design_id, 1.0)


static func materials(design_id: String) -> Dictionary:
	if _material_cache.has(design_id):
		return _material_cache[design_id]
	var p: Dictionary = PALETTES.get(design_id, PALETTES["dummy"])
	var m := {
		"armor": _pbr(p.armor, 0.3, 0.35),
		"armor2": _pbr(p.armor2, 0.45, 0.4),
		"suit": _pbr(p.suit, 0.0, 0.85),
		"trim": _pbr(p.trim, 0.85, 0.28),
		"gun": _pbr(Color(0.11, 0.11, 0.12), 0.7, 0.32),
	}
	var glow := StandardMaterial3D.new()
	glow.albedo_color = (p.glow as Color) * 0.5
	glow.emission_enabled = true
	glow.emission = p.glow
	glow.emission_energy_multiplier = 1.8
	m["glow"] = glow
	_material_cache[design_id] = m
	return m


static func _pbr(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


# =========================================================================== corps

static func build(rig: CharacterRig, design_id: String) -> void:
	var m := materials(design_id)
	var b := bulk(design_id)
	_base_body(rig, m, b)
	match design_id:
		"tank":
			_tank(rig, m, b)
		"assassin":
			_assassin(rig, m, b)
		"tireur":
			_tireur(rig, m, b)
		_:
			_dummy(rig, m, b)


## Corps commun : bassin, ventre, plastron, bras, jambes, bottes.
static func _base_body(rig: CharacterRig, m: Dictionary, b: float) -> void:
	# Bassin et ceinture.
	rig.add_part(rig.hips, Vector3(0.32 * b, 0.2, 0.22 * b), 0.45, Vector3(0, -0.05, 0), m.suit)
	rig.add_part(rig.hips, Vector3(0.36 * b, 0.07, 0.25 * b), 0.3, Vector3(0, 0.03, 0), m.trim)
	rig.add_part(rig.hips, Vector3(0.07, 0.05, 0.02), 0.3, Vector3(0, 0.03, -0.13 * b), m.glow)
	rig.add_part(rig.hips, Vector3(0.2 * b, 0.15, 0.05), 0.35, Vector3(0, -0.07, -0.115 * b), m.armor2, Vector3.ZERO, Vector2(0.75, 1.0))
	for s in [-1.0, 1.0]:
		rig.add_part(rig.hips, Vector3(0.05, 0.18, 0.17 * b), 0.35, Vector3(s * 0.19 * b, -0.07, 0), m.armor, Vector3(0, 0, s * 8.0))

	# Ventre.
	rig.add_part(rig.spine, Vector3(0.28 * b, 0.24, 0.19 * b), 0.5, Vector3(0, 0.1, 0), m.suit)
	rig.add_part(rig.spine, Vector3(0.2 * b, 0.16, 0.05), 0.35, Vector3(0, 0.08, -0.1 * b), m.armor2)

	# Plastron, col, lumière de poitrine, sac à dos, épaulières.
	rig.add_part(rig.chest, Vector3(0.42 * b, 0.3, 0.26 * b), 0.32, Vector3(0, 0.12, 0), m.armor, Vector3.ZERO, Vector2(0.82, 1.0))
	rig.add_part(rig.chest, Vector3(0.3 * b, 0.07, 0.2 * b), 0.35, Vector3(0, 0.28, 0), m.armor2)
	rig.add_part(rig.chest, Vector3(0.14, 0.022, 0.012), 0.3, Vector3(0, 0.16, -0.135 * b), m.glow)
	rig.add_part(rig.chest, Vector3(0.3 * b, 0.32, 0.13), 0.35, Vector3(0, 0.11, 0.18 * b), m.armor2)
	for s in [-1.0, 1.0]:
		rig.add_part(rig.chest, Vector3(0.16 * b, 0.11, 0.19 * b), 0.45,
			Vector3(s * (rig.shoulder_half_width + 0.01), 0.21, 0), m.armor, Vector3(0, 0, s * -14.0))

	# Cou.
	rig.add_part(rig.head, Vector3(0.1, 0.08, 0.1), 0.8, Vector3(0, 0.03, 0), m.suit)

	# Bras (segments orientés par la cinématique inverse, modélisés le long de -Y).
	for i in 2:
		rig.add_part(rig.upper_arms[i], Vector3(0.1 * b, 0.29, 0.1 * b), 0.6, Vector3(0, -0.15, 0), m.suit, Vector3.ZERO, Vector2(0.85, 1.0))
		rig.add_part(rig.upper_arms[i], Vector3(0.115 * b, 0.12, 0.115 * b), 0.45, Vector3(0, -0.06, 0), m.armor2)
		rig.add_part(rig.forearms[i], Vector3(0.1 * b, 0.26, 0.1 * b), 0.45, Vector3(0, -0.14, 0), m.armor2, Vector3.ZERO, Vector2(0.8, 1.05))
		rig.add_part(rig.hands[i], Vector3(0.075, 0.09, 0.1), 0.45, Vector3(0, -0.02, 0), m.trim)
		rig.add_part(rig.forearms[i], Vector3(0.095 * b, 0.095 * b, 0.095 * b), 1.0, Vector3.ZERO, m.suit)

	# Jambes.
	for i in 2:
		rig.add_part(rig.thighs[i], Vector3(0.14 * b, 0.41, 0.15 * b), 0.55, Vector3(0, -0.21, 0), m.suit, Vector3.ZERO, Vector2(0.78, 1.0))
		rig.add_part(rig.thighs[i], Vector3(0.12 * b, 0.22, 0.05), 0.35, Vector3(0, -0.16, -0.075 * b), m.armor)
		rig.add_part(rig.shins[i], Vector3(0.12 * b, 0.4, 0.13 * b), 0.45, Vector3(0, -0.22, 0), m.armor, Vector3.ZERO, Vector2(0.72, 1.0))
		rig.add_part(rig.shins[i], Vector3(0.1 * b, 0.09, 0.06), 0.5, Vector3(0, -0.01, -0.07 * b), m.armor2)
		rig.add_part(rig.shins[i], Vector3(0.12 * b, 0.12, 0.12 * b), 1.0, Vector3.ZERO, m.suit)
		rig.add_part(rig.thighs[i], Vector3(0.14 * b, 0.13, 0.14 * b), 1.0, Vector3.ZERO, m.suit)
		rig.add_part(rig.feet[i], Vector3(0.1 * b, 0.1, 0.1 * b), 1.0, Vector3(0, 0.01, 0), m.suit)
		rig.add_part(rig.feet[i], Vector3(0.12 * b, 0.1, 0.24), 0.32, Vector3(0, -0.05, -0.04), m.armor2)
		rig.add_part(rig.feet[i], Vector3(0.125 * b, 0.03, 0.25), 0.2, Vector3(0, -0.087, -0.04), m.trim)


## TANK : massif, casque à visière fendue, énormes épaulières, bonbonnes dans le dos.
static func _tank(rig: CharacterRig, m: Dictionary, b: float) -> void:
	var h := rig.head
	rig.add_part(h, Vector3(0.3, 0.27, 0.32), 0.5, Vector3(0, 0.15, 0), m.armor)
	rig.add_part(h, Vector3(0.26, 0.13, 0.08), 0.35, Vector3(0, 0.12, -0.14), m.armor2)
	rig.add_part(h, Vector3(0.2, 0.03, 0.02), 0.25, Vector3(0, 0.16, -0.183), m.glow)
	rig.add_part(h, Vector3(0.05, 0.05, 0.28), 0.4, Vector3(0, 0.29, 0.01), m.armor2)
	for s in [-1.0, 1.0]:
		rig.add_part(h, Vector3(0.03, 0.05, 0.02), 0.2, Vector3(s * 0.07, 0.08, -0.18), m.trim)

	for s in [-1.0, 1.0]:
		var x: float = s * (rig.shoulder_half_width + 0.05)
		rig.add_part(rig.chest, Vector3(0.24, 0.17, 0.28), 0.45, Vector3(x, 0.22, 0), m.armor, Vector3(0, 0, s * -12.0))
		rig.add_part(rig.chest, Vector3(0.2, 0.06, 0.24), 0.4, Vector3(x + s * 0.02, 0.31, 0), m.armor2, Vector3(0, 0, s * -12.0))
		rig.add_part(rig.chest, Vector3(0.03, 0.03, 0.2), 0.3, Vector3(x + s * 0.1, 0.18, 0), m.glow, Vector3(0, 0, s * -12.0))

	rig.add_part(rig.chest, Vector3(0.36 * b, 0.14, 0.05), 0.3, Vector3(0, 0.06, -0.15 * b), m.armor2)
	for s in [-1.0, 1.0]:
		rig.add_part(rig.chest, Vector3(0.1, 0.3, 0.1), 1.0, Vector3(s * 0.09, 0.13, 0.29), m.trim, Vector3.ZERO, Vector2.ONE, 0.15)
		rig.add_part(rig.chest, Vector3(0.106, 0.025, 0.106), 1.0, Vector3(s * 0.09, 0.2, 0.29), m.glow, Vector3.ZERO, Vector2.ONE, 0.3)


## ASSASSIN : fin et agile, casque effilé, visière en V, écharpe flottante, lames dans le dos.
static func _assassin(rig: CharacterRig, m: Dictionary, _b: float) -> void:
	var h := rig.head
	rig.add_part(h, Vector3(0.23, 0.26, 0.27), 0.7, Vector3(0, 0.15, 0.01), m.armor, Vector3.ZERO, Vector2(1.0, 0.82))
	rig.add_part(h, Vector3(0.16, 0.07, 0.08), 0.5, Vector3(0, 0.07, -0.1), m.armor2)
	for s in [-1.0, 1.0]:
		rig.add_part(h, Vector3(0.1, 0.028, 0.03), 0.3, Vector3(s * 0.045, 0.16, -0.122), m.glow, Vector3(0, s * -20.0, s * 12.0))
		rig.add_part(h, Vector3(0.02, 0.09, 0.14), 0.4, Vector3(s * 0.105, 0.22, 0.05), m.armor2, Vector3(-25, 0, s * -8.0))

	# Écharpe autour du cou + deux pans qui flottent dans le dos.
	rig.add_part(h, Vector3(0.2, 0.06, 0.2), 0.6, Vector3(0, 0.0, 0), m.armor2)
	var tail_a := rig.add_tail(rig.chest, Vector3(0.03, 0.27, 0.13))
	rig.add_part(tail_a, Vector3(0.1, 0.36, 0.02), 0.3, Vector3(0, -0.18, 0), m.armor2, Vector3(0, 0, 4))
	var tail_b := rig.add_tail(rig.chest, Vector3(-0.04, 0.27, 0.13))
	rig.add_part(tail_b, Vector3(0.08, 0.26, 0.02), 0.3, Vector3(0, -0.13, 0), m.armor2, Vector3(0, 0, -6))

	# Lames croisées dans le dos.
	for s in [-1.0, 1.0]:
		rig.add_part(rig.chest, Vector3(0.025, 0.55, 0.07), 0.2, Vector3(s * 0.08, 0.08, 0.2), m.trim, Vector3(0, 0, s * 22.0))
		rig.add_part(rig.chest, Vector3(0.012, 0.5, 0.012), 0.3, Vector3(s * 0.08, 0.08, 0.235), m.glow, Vector3(0, 0, s * 22.0))


## TIREUR : œil-lunette, antenne, pans de manteau, cartouchière.
static func _tireur(rig: CharacterRig, m: Dictionary, _b: float) -> void:
	var h := rig.head
	rig.add_part(h, Vector3(0.26, 0.27, 0.29), 0.5, Vector3(0, 0.15, 0), m.armor)
	rig.add_part(h, Vector3(0.2, 0.11, 0.07), 0.4, Vector3(0, 0.11, -0.12), m.armor2)
	rig.add_part(h, Vector3(0.075, 0.09, 0.075), 0.95, Vector3(0.07, 0.18, -0.14), m.trim, Vector3(90, 0, 0), Vector2.ONE, 0.25)
	rig.add_part(h, Vector3(0.055, 0.02, 0.055), 0.95, Vector3(0.07, 0.18, -0.188), m.glow, Vector3(90, 0, 0), Vector2.ONE, 0.3)
	rig.add_part(h, Vector3(0.03, 0.012, 0.03), 0.95, Vector3(-0.05, 0.18, -0.152), m.glow, Vector3(90, 0, 0))
	rig.add_part(h, Vector3(0.012, 0.24, 0.012), 0.9, Vector3(-0.11, 0.35, 0.07), m.trim, Vector3.ZERO, Vector2.ONE, 0.9)
	rig.add_part(h, Vector3(0.028, 0.028, 0.028), 1.0, Vector3(-0.11, 0.47, 0.07), m.glow)

	rig.add_part(rig.chest, Vector3(0.36, 0.1, 0.28), 0.5, Vector3(0, 0.29, 0.03), m.armor2)
	rig.add_part(rig.chest, Vector3(0.05, 0.42, 0.03), 0.3, Vector3(0, 0.12, -0.14), m.trim, Vector3(0, 0, 35))
	for s in [-1.0, 1.0]:
		var tail := rig.add_tail(rig.hips, Vector3(s * 0.09, -0.02, 0.12))
		rig.add_part(tail, Vector3(0.15, 0.44, 0.025), 0.3, Vector3(0, -0.22, 0), m.armor2)


## MANNEQUIN : robot d'entraînement orange avec un gros œil rouge.
static func _dummy(rig: CharacterRig, m: Dictionary, b: float) -> void:
	var h := rig.head
	rig.add_part(h, Vector3(0.27, 0.25, 0.27), 0.4, Vector3(0, 0.15, 0), m.armor)
	rig.add_part(h, Vector3(0.11, 0.11, 0.03), 1.0, Vector3(0, 0.16, -0.13), m.glow)
	rig.add_part(rig.chest, Vector3(0.43 * b, 0.05, 0.27 * b), 0.3, Vector3(0, 0.2, 0), m.trim)
	rig.add_part(rig.chest, Vector3(0.43 * b, 0.05, 0.27 * b), 0.3, Vector3(0, 0.06, 0), m.trim)


# =========================================================================== armes

enum { SHOTGUN, SMG, SNIPER }

## Modélise l'arme dans `weapon_node` (ou sur la main si null) et place son Muzzle.
## Renvoie {"foregrip": distance de la main gauche}.
static func build_weapon(rig, kind: int, design_id: String, weapon_node: Node3D) -> Dictionary:
	var m := materials(design_id)
	var g: Node3D = weapon_node if weapon_node else rig.gun_mount
	var muzzle := Vector3.ZERO
	var foregrip := 0.3
	match kind:
		SHOTGUN:
			rig.add_part(g, Vector3(0.075, 0.11, 0.34), 0.25, Vector3(0, 0.03, -0.12), m.gun)
			rig.add_part(g, Vector3(0.045, 0.5, 0.045), 1.0, Vector3(0, 0.06, -0.5), m.gun, Vector3(90, 0, 0), Vector2.ONE, 0.12)
			rig.add_part(g, Vector3(0.04, 0.4, 0.04), 1.0, Vector3(0, 0.015, -0.45), m.gun, Vector3(90, 0, 0), Vector2.ONE, 0.12)
			rig.add_part(g, Vector3(0.065, 0.065, 0.16), 0.5, Vector3(0, 0.015, -0.4), m.armor)
			rig.add_part(g, Vector3(0.06, 0.1, 0.26), 0.35, Vector3(0, 0.0, 0.17), m.armor)
			rig.add_part(g, Vector3(0.04, 0.11, 0.06), 0.35, Vector3(0, -0.06, 0.01), m.gun, Vector3(20, 0, 0))
			rig.add_part(g, Vector3(0.012, 0.012, 0.2), 0.3, Vector3(0.04, 0.05, -0.1), m.glow)
			muzzle = Vector3(0, 0.06, -0.76)
			foregrip = 0.4
		SMG:
			rig.add_part(g, Vector3(0.065, 0.11, 0.34), 0.3, Vector3(0, 0.03, -0.08), m.gun)
			rig.add_part(g, Vector3(0.032, 0.16, 0.032), 1.0, Vector3(0, 0.05, -0.32), m.gun, Vector3(90, 0, 0), Vector2.ONE, 0.15)
			rig.add_part(g, Vector3(0.045, 0.14, 0.045), 1.0, Vector3(0, 0.05, -0.45), m.armor2, Vector3(90, 0, 0), Vector2.ONE, 0.2)
			rig.add_part(g, Vector3(0.035, 0.2, 0.055), 0.3, Vector3(0, -0.1, -0.14), m.armor, Vector3(-12, 0, 0))
			rig.add_part(g, Vector3(0.04, 0.11, 0.055), 0.35, Vector3(0, -0.06, 0.02), m.gun, Vector3(18, 0, 0))
			rig.add_part(g, Vector3(0.03, 0.07, 0.2), 0.3, Vector3(0, 0.01, 0.17), m.gun)
			rig.add_part(g, Vector3(0.045, 0.05, 0.07), 0.4, Vector3(0, 0.11, -0.05), m.armor)
			rig.add_part(g, Vector3(0.03, 0.03, 0.006), 0.8, Vector3(0, 0.115, -0.087), m.glow)
			muzzle = Vector3(0, 0.05, -0.53)
			foregrip = 0.24
		_:
			rig.add_part(g, Vector3(0.07, 0.1, 0.48), 0.25, Vector3(0, 0.03, -0.1), m.gun)
			rig.add_part(g, Vector3(0.032, 0.62, 0.032), 1.0, Vector3(0, 0.05, -0.63), m.gun, Vector3(90, 0, 0), Vector2.ONE, 0.12)
			rig.add_part(g, Vector3(0.05, 0.08, 0.05), 0.5, Vector3(0, 0.05, -0.96), m.gun, Vector3(90, 0, 0))
			rig.add_part(g, Vector3(0.055, 0.3, 0.055), 1.0, Vector3(0, 0.13, -0.1), m.armor2, Vector3(90, 0, 0), Vector2.ONE, 0.15)
			rig.add_part(g, Vector3(0.05, 0.012, 0.05), 1.0, Vector3(0, 0.13, -0.252), m.glow, Vector3(90, 0, 0))
			for z in [-0.02, -0.18]:
				rig.add_part(g, Vector3(0.025, 0.06, 0.025), 0.4, Vector3(0, 0.09, z), m.gun)
			rig.add_part(g, Vector3(0.065, 0.13, 0.3), 0.3, Vector3(0, -0.01, 0.22), m.armor, Vector3.ZERO, Vector2(0.8, 1.0))
			rig.add_part(g, Vector3(0.04, 0.11, 0.06), 0.35, Vector3(0, -0.06, 0.03), m.gun, Vector3(20, 0, 0))
			rig.add_part(g, Vector3(0.04, 0.1, 0.07), 0.3, Vector3(0, -0.06, -0.12), m.gun)
			muzzle = Vector3(0, 0.05, -1.0)
			foregrip = 0.42
	if weapon_node and weapon_node.has_node("Muzzle"):
		(weapon_node.get_node("Muzzle") as Node3D).position = muzzle
	return {"foregrip": foregrip}
