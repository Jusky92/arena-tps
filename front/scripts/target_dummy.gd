extends StaticBody3D
## Cible d'entraînement : encaisse des dégâts, disparaît à 0 PV, puis réapparaît.
## Elle expose la même méthode `take_damage` que les futurs joueurs distants,
## ce qui permet de tester le tir sans serveur.

@export var max_health: int = 100
@export var respawn_delay: float = 3.0

@onready var body_mesh: MeshInstance3D = $Body
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var health_label: Label3D = $HealthLabel

var health: int
var _material: StandardMaterial3D
var _base_color: Color


func _ready() -> void:
	# Copie du matériau pour que chaque cible puisse clignoter indépendamment.
	_material = body_mesh.mesh.material.duplicate()
	body_mesh.material_override = _material
	_base_color = _material.albedo_color
	_reset()


## Inflige des dégâts. Renvoie true si ce coup a éliminé la cible.
func take_damage(amount: int, _from: Node) -> bool:
	if health <= 0:
		return false
	health = max(health - amount, 0)
	_update_label()
	_flash()
	if health == 0:
		_die()
		return true
	return false


func _die() -> void:
	visible = false
	collision.set_deferred("disabled", true)
	get_tree().create_timer(respawn_delay).timeout.connect(_reset)


func _reset() -> void:
	health = max_health
	visible = true
	collision.set_deferred("disabled", false)
	_material.albedo_color = _base_color
	_update_label()


func _update_label() -> void:
	health_label.text = "%d PV" % health


func _flash() -> void:
	_material.albedo_color = Color.WHITE
	var tween := create_tween()
	tween.tween_property(_material, "albedo_color", _base_color, 0.15)
