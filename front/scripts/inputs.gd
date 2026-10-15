extends Node
## Déclare les touches du jeu au démarrage, et celles que le joueur a changées
## (page Paramètres), enregistrées dans user://touches.cfg.
## Touches PHYSIQUES : la position "WASD" d'un clavier QWERTY correspond à
## ZQSD sur un clavier AZERTY. Les flèches marchent aussi.

## Les touches ont changé (réassignation ou retour aux touches par défaut).
signal bindings_changed

const KEY_ACTIONS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back":    [KEY_S, KEY_DOWN],
	"move_left":    [KEY_A, KEY_LEFT],
	"move_right":   [KEY_D, KEY_RIGHT],
	"jump":         [KEY_SPACE],
	"sprint":       [KEY_SHIFT],
	"crouch":       [KEY_CTRL, KEY_C],
	"reload":       [KEY_R],
	"ability":      [KEY_E],
	"weapon_1":     [KEY_1],
	"weapon_2":     [KEY_2],
	"weapon_3":     [KEY_3],
	"super":        [KEY_F],
	"grenade":      [KEY_G],
	"pause":        [KEY_ESCAPE],
	"scoreboard":   [KEY_TAB],
	"debug_hurt":   [KEY_F9],   # test : s'infliger 25 dégâts (à retirer plus tard)
}

const MOUSE_ACTIONS := {
	"fire": [MOUSE_BUTTON_LEFT],
	"aim":  [MOUSE_BUTTON_RIGHT],
	"weapon_next": [MOUSE_BUTTON_WHEEL_DOWN],
	"weapon_prev": [MOUSE_BUTTON_WHEEL_UP],
}

## Actions que le joueur peut réassigner, dans l'ordre de la page Paramètres.
## Échap (pause) reste fixe : il sert aussi à annuler une saisie de touche.
const REBINDABLE := [
	["move_forward", "Avancer"],
	["move_back", "Reculer"],
	["move_left", "Aller à gauche"],
	["move_right", "Aller à droite"],
	["jump", "Sauter"],
	["sprint", "Courir"],
	["crouch", "S'accroupir"],
	["fire", "Tirer"],
	["aim", "Viser"],
	["reload", "Recharger"],
	["ability", "Capacité"],
	["super", "Super-pouvoir"],
	["grenade", "Grenade"],
	["weapon_1", "Arme principale"],
	["weapon_2", "Arme secondaire"],
	["weapon_3", "Arme spéciale"],
	["weapon_next", "Arme suivante"],
	["weapon_prev", "Arme précédente"],
	["scoreboard", "Tableau des scores"],
]
## Touches par action sur la page Paramètres (principale, secondaire).
const SLOTS := 2
const BINDINGS_PATH := "user://touches.cfg"

## La sensibilité de la souris est dans les réglages (autoload Settings).


func _ready() -> void:
	_apply_defaults()
	_load_bindings()


func _apply_defaults() -> void:
	for action in KEY_ACTIONS:
		_ensure_action(action)
		InputMap.action_erase_events(action)
		for key in KEY_ACTIONS[action]:
			InputMap.action_add_event(action, _key_event(key))
	for action in MOUSE_ACTIONS:
		_ensure_action(action)
		InputMap.action_erase_events(action)
		for button in MOUSE_ACTIONS[action]:
			InputMap.action_add_event(action, _mouse_event(button))


func _ensure_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)


# ---------------------------------------------------------------- Réassignation

## Touches d'une action (InputEventKey ou InputEventMouseButton), dans l'ordre des emplacements.
func events_of(action: String) -> Array[InputEvent]:
	return InputMap.action_get_events(action)


## Met `event` (touche ou bouton de souris) à l'emplacement `slot` de `action`.
## La touche est retirée des autres actions qui l'utilisaient : renvoie le nom
## (français) de celle qui l'a perdue, ou "".
func bind(action: String, slot: int, event: InputEvent) -> String:
	var clean := _clean_event(event)
	if clean == null:
		return ""
	var taken_from := ""
	for entry in REBINDABLE:
		if entry[0] == action:
			continue
		for other in events_of(entry[0]):
			if _same(other, clean):
				InputMap.action_erase_event(entry[0], other)
				taken_from = entry[1]
	var events := events_of(action).filter(func(e: InputEvent) -> bool: return not _same(e, clean))
	if slot < events.size():
		events[slot] = clean
	else:
		events.append(clean)
	_set_events(action, events)
	_save_bindings()
	bindings_changed.emit()
	return taken_from


## Vide l'emplacement `slot` de `action`.
func unbind(action: String, slot: int) -> void:
	var events := events_of(action)
	if slot >= events.size():
		return
	events.remove_at(slot)
	_set_events(action, events)
	_save_bindings()
	bindings_changed.emit()


func reset_bindings() -> void:
	_apply_defaults()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BINDINGS_PATH))
	bindings_changed.emit()


## Nom lisible d'une touche, d'après la disposition du clavier du joueur (Z sur AZERTY).
func event_label(event: InputEvent) -> String:
	if event is InputEventKey:
		var physical: Key = (event as InputEventKey).physical_keycode
		match physical:
			KEY_SPACE: return "Espace"
			KEY_SHIFT: return "Maj"
			KEY_CTRL: return "Ctrl"
			KEY_ALT: return "Alt"
			KEY_TAB: return "Tab"
			KEY_ENTER: return "Entrée"
			KEY_BACKSPACE: return "Retour arrière"
			KEY_CAPSLOCK: return "Verr. maj"
			KEY_UP: return "↑"
			KEY_DOWN: return "↓"
			KEY_LEFT: return "←"
			KEY_RIGHT: return "→"
		var local := DisplayServer.keyboard_get_keycode_from_physical(physical)
		return OS.get_keycode_string(local if local != KEY_NONE else physical)
	if event is InputEventMouseButton:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT: return "Clic gauche"
			MOUSE_BUTTON_RIGHT: return "Clic droit"
			MOUSE_BUTTON_MIDDLE: return "Clic milieu"
			MOUSE_BUTTON_WHEEL_UP: return "Molette haut"
			MOUSE_BUTTON_WHEEL_DOWN: return "Molette bas"
			MOUSE_BUTTON_XBUTTON1: return "Souris 4"
			MOUSE_BUTTON_XBUTTON2: return "Souris 5"
		return "Souris %d" % (event as InputEventMouseButton).button_index
	return "?"


## Rappel de touche pour l'interface, par exemple "[E]" (première touche de l'action).
func hint(action: String) -> String:
	var events := events_of(action)
	return "[%s]" % (event_label(events[0]) if not events.is_empty() else "—")


func _set_events(action: String, events: Array) -> void:
	InputMap.action_erase_events(action)
	for event in events:
		InputMap.action_add_event(action, event)


## Seulement ce qui compte pour une action : la touche physique, ou le bouton de souris.
func _clean_event(event: InputEvent) -> InputEvent:
	if event is InputEventKey and (event as InputEventKey).physical_keycode != KEY_NONE:
		return _key_event((event as InputEventKey).physical_keycode)
	if event is InputEventMouseButton:
		return _mouse_event((event as InputEventMouseButton).button_index)
	return null


func _same(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		return (a as InputEventKey).physical_keycode == (b as InputEventKey).physical_keycode
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return (a as InputEventMouseButton).button_index == (b as InputEventMouseButton).button_index
	return false


func _key_event(key: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = key
	return event


func _mouse_event(button: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	return event


# ---------------------------------------------------------------- Fichier

## Une liste par action réassignable : "key:<code physique>" ou "mouse:<bouton>".
func _save_bindings() -> void:
	var cfg := ConfigFile.new()
	for entry in REBINDABLE:
		var codes: Array[String] = []
		for event in events_of(entry[0]):
			if event is InputEventKey:
				codes.append("key:%d" % (event as InputEventKey).physical_keycode)
			elif event is InputEventMouseButton:
				codes.append("mouse:%d" % (event as InputEventMouseButton).button_index)
		cfg.set_value("touches", entry[0], codes)
	cfg.save(BINDINGS_PATH)


func _load_bindings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(BINDINGS_PATH) != OK:
		return
	for entry in REBINDABLE:
		var codes: Variant = cfg.get_value("touches", entry[0], null)
		if not codes is Array:
			continue
		var events: Array[InputEvent] = []
		for code in codes:
			var parts := str(code).split(":")
			if parts.size() != 2 or not parts[1].is_valid_int():
				continue
			if parts[0] == "key":
				events.append(_key_event(int(parts[1]) as Key))
			elif parts[0] == "mouse":
				events.append(_mouse_event(int(parts[1]) as MouseButton))
		_set_events(entry[0], events.slice(0, SLOTS))
