class_name Effects
extends RefCounted
## Petits effets visuels réutilisables (traits de tir, impacts, éclairs).
## Fonctions "static" : on les appelle directement, ex. Effects.tracer(...).


## Trait lumineux entre deux points, visible une fraction de seconde.
static func tracer(parent: Node, from: Vector3, to: Vector3, color: Color, lifetime := 0.06) -> void:
	if headless():
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_add_vertex(from)
	mesh.surface_add_vertex(to)
	mesh.surface_end()

	var line := MeshInstance3D.new()
	line.mesh = mesh
	line.material_override = _unshaded(color)
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spawn(parent, line, lifetime)


## Petite boule qui grossit puis disparaît à l'endroit touché.
static func impact(parent: Node, position: Vector3, color: Color, size := 0.07) -> void:
	if headless():
		return
	var sphere := SphereMesh.new()
	sphere.radius = size
	sphere.height = size * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	sphere.material = _unshaded(color)

	var node := MeshInstance3D.new()
	node.mesh = sphere
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spawn(parent, node, 0.25)
	node.global_position = position
	var tween := node.create_tween()
	tween.tween_property(node, "scale", Vector3.ONE * 2.5, 0.25)


## Éclair de lumière au bout du canon.
static func muzzle_flash(parent: Node3D, color: Color) -> void:
	if headless():
		return
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 3.0
	light.omni_range = 4.0
	parent.add_child(light)
	parent.get_tree().create_timer(0.05).timeout.connect(light.queue_free)


## true sur le serveur dédié (aucun affichage) : les effets ne servent à rien.
static func headless() -> bool:
	return DisplayServer.get_name() == "headless"


static func _unshaded(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material


static func _spawn(parent: Node, node: Node, lifetime: float) -> void:
	parent.add_child(node)
	parent.get_tree().create_timer(lifetime).timeout.connect(node.queue_free)


# ---------------------------------------------------------------- Nouvelles armes

## Apparence d'un projectile en vol (roquette, boule du lance-caca, grenade).
## Le nœud regarde vers -Z = sens du déplacement.
static func projectile_visual(data: WeaponData) -> Node3D:
	var root := Node3D.new()
	var glow := _unshaded(data.tracer_color)
	match data.model:
		WeaponData.Model.ROCKET:
			var body := MeshInstance3D.new()
			body.mesh = PartMesh.shape(Vector3(0.12, 0.12, 0.5), 0.8)
			body.material_override = _pbr(Color(0.12, 0.12, 0.14))
			root.add_child(body)
			var nose := MeshInstance3D.new()
			nose.mesh = PartMesh.shape(Vector3(0.1, 0.1, 0.16), 1.0)
			nose.material_override = glow
			nose.position.z = -0.27
			root.add_child(nose)
			var trail := MeshInstance3D.new()
			trail.mesh = PartMesh.shape(Vector3(0.09, 0.09, 0.7), 1.0, -1.0, Vector2(0.2, 1.0))
			trail.material_override = _unshaded(Color(1.0, 0.6, 0.2, 1.0))
			trail.position.z = 0.55
			root.add_child(trail)
			var light := OmniLight3D.new()
			light.light_color = data.tracer_color
			light.light_energy = 2.0
			light.omni_range = 4.0
			root.add_child(light)
		WeaponData.Model.POOP:
			# Boule cartoon marron, avec deux petites lignes « odeur » vertes.
			var ball := MeshInstance3D.new()
			ball.mesh = PartMesh.shape(Vector3(0.22, 0.2, 0.22), 1.0, -1.0, Vector2(1.0, 0.65))
			ball.material_override = _pbr(Color(0.42, 0.25, 0.1), 0.1, 0.35)
			root.add_child(ball)
			for x in [-0.06, 0.06]:
				var line := MeshInstance3D.new()
				line.mesh = PartMesh.shape(Vector3(0.02, 0.14, 0.02), 1.0)
				line.material_override = _unshaded(Color(0.55, 0.95, 0.35))
				line.position = Vector3(x, 0.2, 0.05)
				line.rotation_degrees.z = x * 200.0
				root.add_child(line)
		_:
			var nade := MeshInstance3D.new()
			nade.mesh = PartMesh.shape(Vector3(0.14, 0.17, 0.14), 0.9)
			nade.material_override = _pbr(Color(0.15, 0.17, 0.16))
			root.add_child(nade)
			var ring := MeshInstance3D.new()
			ring.mesh = PartMesh.shape(Vector3(0.15, 0.03, 0.15), 1.0)
			ring.material_override = glow
			root.add_child(ring)
			var blink := OmniLight3D.new()
			blink.light_color = data.tracer_color
			blink.light_energy = 1.5
			blink.omni_range = 2.5
			root.add_child(blink)
	return root


## Explosion : boule lumineuse qui gonfle, anneau au sol et éclair de lumière.
## `cartoon` = éclaboussure marron du lance-caca (pas de feu).
static func explosion(parent: Node, position: Vector3, radius: float, color: Color, cartoon := false) -> void:
	if headless() or parent == null:
		return
	var root := Node3D.new()
	_spawn(parent, root, 0.6)
	root.global_position = position
	var ball := MeshInstance3D.new()
	ball.mesh = PartMesh.shape(Vector3.ONE * 0.6, 1.0)
	var material := _unshaded(color)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ball.material_override = material
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ball)
	var size := radius * (0.9 if cartoon else 1.6)
	var tween := ball.create_tween().set_parallel()
	tween.tween_property(ball, "scale", Vector3.ONE * size, 0.28).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.5)
	if cartoon:
		# Gouttes cartoon projetées autour (rondes, pas de détails).
		for i in 7:
			var drop := MeshInstance3D.new()
			drop.mesh = PartMesh.shape(Vector3.ONE * 0.12, 1.0)
			drop.material_override = _pbr(Color(0.42, 0.25, 0.1), 0.1, 0.35)
			root.add_child(drop)
			var dir := Vector3(randf_range(-1, 1), randf_range(0.3, 1.0), randf_range(-1, 1)).normalized()
			drop.create_tween().tween_property(drop, "position", dir * radius * 0.8, 0.35).set_ease(Tween.EASE_OUT)
		return
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 8.0
	light.omni_range = radius * 3.0
	root.add_child(light)
	light.create_tween().tween_property(light, "light_energy", 0.0, 0.45)


## Jet de flammes : quelques boules orange et magenta lancées dans le cône.
static func flame_puff(parent: Node, from: Vector3, direction: Vector3, length: float) -> void:
	if headless() or parent == null:
		return
	for i in 3:
		var puff := MeshInstance3D.new()
		puff.mesh = PartMesh.shape(Vector3.ONE * 0.25, 1.0)
		var color := Color(1.0, 0.55, 0.15) if randf() < 0.65 else Color(1.0, 0.3, 0.75)
		var material := _unshaded(color)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		puff.material_override = material
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_spawn(parent, puff, 0.32)
		puff.global_position = from
		var spread := Vector3(randf_range(-0.12, 0.12), randf_range(-0.08, 0.12), randf_range(-0.12, 0.12))
		var target := from + (direction + spread).normalized() * length * randf_range(0.7, 1.0)
		var tween := puff.create_tween().set_parallel()
		tween.tween_property(puff, "global_position", target, 0.3)
		tween.tween_property(puff, "scale", Vector3.ONE * 4.0, 0.3)
		tween.tween_property(material, "albedo_color:a", 0.0, 0.3)


## Rayon laser épais et lumineux (pistolet laser).
static func laser_beam(parent: Node, from: Vector3, to: Vector3, color: Color) -> void:
	if headless() or parent == null or from.is_equal_approx(to):
		return
	var beam := MeshInstance3D.new()
	var length := from.distance_to(to)
	beam.mesh = PartMesh.shape(Vector3(0.05, 0.05, length), 1.0)
	var material := _unshaded(color)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam.material_override = material
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spawn(parent, beam, 0.14)
	beam.global_position = (from + to) / 2.0
	beam.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	var tween := beam.create_tween().set_parallel()
	tween.tween_property(beam, "scale", Vector3(0.2, 0.2, 1.0), 0.14)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.14)


## Arc lumineux du katana devant le joueur.
static func slash(parent: Node, center: Vector3, forward: Vector3, reach: float, color: Color) -> void:
	if headless() or parent == null:
		return
	var arc := MeshInstance3D.new()
	arc.mesh = PartMesh.shape(Vector3(reach * 1.6, 0.05, reach * 0.9), 1.0, 0.3, Vector2(1.0, 0.4))
	var material := _unshaded(color)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	arc.material_override = material
	arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spawn(parent, arc, 0.18)
	arc.global_position = center + forward * reach * 0.45
	arc.look_at(arc.global_position + forward, Vector3.UP)
	arc.rotate_object_local(Vector3.FORWARD, deg_to_rad(randf_range(-25.0, 25.0)))
	var tween := arc.create_tween().set_parallel()
	tween.tween_property(arc, "scale", Vector3(1.2, 1.0, 1.2), 0.18)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.18)


static func _pbr(color: Color, metallic := 0.6, roughness := 0.35) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


## Halo de la Surcharge néon : lumière rose et coque translucide qui pulse.
static func overload_aura() -> Node3D:
	var root := Node3D.new()
	root.name = "OverloadAura"
	var light := OmniLight3D.new()
	light.light_color = Color(0.95, 0.27, 0.78)
	light.light_energy = 2.5
	light.omni_range = 4.0
	light.position.y = 1.0
	root.add_child(light)
	var shell := MeshInstance3D.new()
	shell.mesh = PartMesh.shape(Vector3(1.3, 2.1, 1.3), 1.0)
	var material := _unshaded(Color(0.95, 0.27, 0.78, 0.18))
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	shell.material_override = material
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell.position.y = 1.0
	root.add_child(shell)
	var tween := shell.create_tween().set_loops()
	tween.tween_property(shell, "scale", Vector3.ONE * 1.12, 0.45)
	tween.tween_property(shell, "scale", Vector3.ONE, 0.45)
	return root


## Onde de choc : grand anneau qui s'élargit au sol, en plus de l'explosion.
static func shockwave(parent: Node, position: Vector3, radius: float) -> void:
	if headless() or parent == null:
		return
	var ring := MeshInstance3D.new()
	ring.mesh = PartMesh.shape(Vector3(1.0, 0.1, 1.0), 1.0)
	var material := _unshaded(Color(1.0, 0.55, 0.2, 0.8))
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = material
	_spawn(parent, ring, 0.6)
	ring.global_position = position + Vector3(0, 0.15, 0)
	var tween := ring.create_tween().set_parallel()
	tween.tween_property(ring, "scale", Vector3(radius * 2.2, 1.0, radius * 2.2), 0.5).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.55)
