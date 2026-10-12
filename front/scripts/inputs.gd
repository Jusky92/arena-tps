extends Node
## Déclare les touches du jeu au démarrage.
## Touches PHYSIQUES : la position "WASD" d'un clavier QWERTY correspond à
## ZQSD sur un clavier AZERTY. Les flèches marchent aussi.

const KEY_ACTIONS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back":    [KEY_S, KEY_DOWN],
	"move_left":    [KEY_A, KEY_LEFT],
	"move_right":   [KEY_D, KEY_RIGHT],
	"jump":         [KEY_SPACE],
	"sprint":       [KEY_SHIFT],
	"back_to_menu": [KEY_ESCAPE],
}

# Réglage de la souris (sensibilité de la caméra).
var mouse_sensitivity: float = 0.003


func _ready() -> void:
	for action in KEY_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in KEY_ACTIONS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
