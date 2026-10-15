class_name PartMesh
extends RefCounted
## Fabrique les pièces 3D des personnages et des armes (plaques d'armure, membres,
## casques...) à partir d'une seule forme mathématique : la "superellipsoïde".
##
## Selon son arrondi, elle va du cube (0.1) au cube arrondi (0.3-0.5), jusqu'à la
## sphère (1.0). On peut aussi l'affiner en haut ou en bas (taper) : idéal pour des
## membres, des casques ou des plaques d'armure sans logiciel de modélisation.
##
## Les maillages sont mis en cache : une forme identique n'est calculée qu'une fois.

const RINGS := 20
const SEGMENTS := 28

## Arrondis minimaux du style « lisse » : l'équipement des personnages n'a plus
## d'angles vifs, les armes gardent une silhouette un peu plus nette.
const SMOOTH_GEAR := 0.55
const SMOOTH_WEAPON := 0.4


## Arrondi relevé au minimum `floor` (vertical = -1 garde « même valeur que roundness »).
static func smooth(roundness: float, vertical: float, floor_value: float) -> Vector2:
	return Vector2(maxf(roundness, floor_value), vertical if vertical < 0.0 else maxf(vertical, floor_value))

static var _cache := {}


## size      : dimensions totales (x, y, z) en mètres
## roundness : arrondi horizontal (0.1 = angles vifs, 1 = rond)
## vertical  : arrondi vertical (-1 = même valeur que roundness)
## taper     : échelle (x, z) en bas et en haut de la pièce (1, 1 = droite)
static func shape(size: Vector3, roundness := 0.35, vertical := -1.0, taper := Vector2.ONE) -> ArrayMesh:
	var e2 := roundness
	var e1 := roundness if vertical < 0.0 else vertical
	var key := "%s|%.3f|%.3f|%s" % [size, e1, e2, taper]
	if _cache.has(key):
		return _cache[key]

	var positions := PackedVector3Array()
	for i in RINGS + 1:
		var u := -PI / 2.0 + PI * float(i) / RINGS
		var cu := _signed_pow(cos(u), e1)
		var su := _signed_pow(sin(u), e1)
		var k := lerpf(taper.x, taper.y, (su + 1.0) * 0.5)
		for j in SEGMENTS:
			var v := TAU * float(j) / SEGMENTS
			var cv := _signed_pow(cos(v), e2)
			var sv := _signed_pow(sin(v), e2)
			positions.append(Vector3(cu * cv * size.x * 0.5 * k, su * size.y * 0.5, cu * sv * size.z * 0.5 * k))

	var indices := PackedInt32Array()
	var normals := PackedVector3Array()
	normals.resize(positions.size())
	for i in RINGS:
		for j in SEGMENTS:
			var a := i * SEGMENTS + j
			var b := i * SEGMENTS + (j + 1) % SEGMENTS
			var c := (i + 1) * SEGMENTS + j
			var d := (i + 1) * SEGMENTS + (j + 1) % SEGMENTS
			_add_triangle(positions, indices, normals, a, c, b)
			_add_triangle(positions, indices, normals, b, c, d)
	for n in normals.size():
		normals[n] = normals[n].normalized() if normals[n].length_squared() > 0.0 else Vector3.UP

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_cache[key] = mesh
	return mesh


## Ajoute un triangle en s'assurant qu'il est vu de l'extérieur (Godot affiche les
## triangles "dans le sens horaire" vus de face) et accumule sa normale.
static func _add_triangle(p: PackedVector3Array, indices: PackedInt32Array, normals: PackedVector3Array,
		a: int, b: int, c: int) -> void:
	var face := (p[b] - p[a]).cross(p[c] - p[a])
	if face.length_squared() < 1e-14:
		return  # triangle dégénéré (aux pôles)
	var center := (p[a] + p[b] + p[c]) / 3.0
	if face.dot(center) > 0.0:
		# La normale "main droite" pointe vers l'extérieur : on inverse l'ordre.
		var tmp := b
		b = c
		c = tmp
		face = -face
	indices.append(a)
	indices.append(b)
	indices.append(c)
	var outward := -face
	normals[a] += outward
	normals[b] += outward
	normals[c] += outward


static func _signed_pow(value: float, exponent: float) -> float:
	return signf(value) * pow(absf(value), exponent)
