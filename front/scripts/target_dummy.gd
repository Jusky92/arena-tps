extends StaticBody3D
## Mannequin d'entraînement : un robot qui encaisse des dégâts, tombe à 0 PV,
## puis se relève. Il expose la même méthode `take_damage` que les joueurs,
## ce qui permet de tester le tir sans serveur. Peut être accroupi (hitbox basse).

@export var max_health: int = 100
@export var respawn_delay: float = 3.0
@export var crouched: bool = false

const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.25

@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var health_label: Label3D = $HealthLabel

var health: int
var rig: CharacterRig


func _ready() -> void:
	rig = CharacterRig.new()
	add_child(rig)
	rig.build("dummy", WeaponData.Model.SMG)

	# Hitbox adaptée à la posture (forme copiée pour ne pas modifier les autres mannequins).
	var capsule: CapsuleShape3D = collision.shape.duplicate()
	capsule.height = CROUCH_HEIGHT if crouched else STAND_HEIGHT
	collision.shape = capsule
	collision.position.y = capsule.height / 2.0
	health_label.position.y = capsule.height + 0.3
	_reset()


func _process(_delta: float) -> void:
	# Immobile, mais vivant : respiration et posture gérées par le rig.
	rig.set_state(Vector3.ZERO, true, 1.0 if crouched else 0.0, 0.0)


## Inflige des dégâts. Renvoie true si ce coup a éliminé la cible.
func take_damage(amount: int, _from: Node, _headshot := false) -> bool:
	if health <= 0:
		return false
	health = max(health - amount, 0)
	_update_label()
	rig.flash()
	if health == 0:
		_die()
		return true
	return false


func _die() -> void:
	rig.play_death()
	health_label.visible = false
	collision.set_deferred("disabled", true)
	get_tree().create_timer(respawn_delay).timeout.connect(_reset)


func _reset() -> void:
	health = max_health
	rig.reset()
	health_label.visible = true
	collision.set_deferred("disabled", false)
	_update_label()


func _update_label() -> void:
	health_label.text = "%d PV" % health
