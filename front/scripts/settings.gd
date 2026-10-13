extends Node
## Réglages du joueur (son, souris), enregistrés sur la machine dans
## user://parametres.cfg et rechargés au démarrage. Autoload "Settings".
##
## Bus audio créés ici :
##   Master     volume général
##   ├─ Effets  tirs, impacts, capacités (sons de la partie)
##   └─ Interface  clics des menus, confirmations

signal changed

const PATH := "user://parametres.cfg"
const BASE_SENSITIVITY := 0.003          ## sensibilité "x1.0" (radians par pixel)
const SFX_BUS := "Effets"
const UI_BUS := "Interface"

## Volumes de 0.0 (muet) à 1.0.
var master_volume := 0.8
var sfx_volume := 1.0
var ui_volume := 0.8
## Multiplicateur de la sensibilité de la souris (0.2 à 3.0).
var sensitivity := 1.0
## Inverser l'axe vertical de la souris.
var invert_y := false


func _ready() -> void:
	_ensure_bus(SFX_BUS)
	_ensure_bus(UI_BUS)
	load_settings()
	apply()


## Sensibilité réelle utilisée par la caméra.
func mouse_sensitivity() -> float:
	return BASE_SENSITIVITY * sensitivity


func apply() -> void:
	_set_bus_volume("Master", master_volume)
	_set_bus_volume(SFX_BUS, sfx_volume)
	_set_bus_volume(UI_BUS, ui_volume)
	changed.emit()


func set_value(key: String, value) -> void:
	set(key, value)
	apply()


func reset_defaults() -> void:
	master_volume = 0.8
	sfx_volume = 1.0
	ui_volume = 0.8
	sensitivity = 1.0
	invert_y = false
	apply()
	save_settings()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("son", "general", master_volume)
	cfg.set_value("son", "effets", sfx_volume)
	cfg.set_value("son", "interface", ui_volume)
	cfg.set_value("souris", "sensibilite", sensitivity)
	cfg.set_value("souris", "inverser_y", invert_y)
	cfg.save(PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	master_volume = clampf(cfg.get_value("son", "general", master_volume), 0.0, 1.0)
	sfx_volume = clampf(cfg.get_value("son", "effets", sfx_volume), 0.0, 1.0)
	ui_volume = clampf(cfg.get_value("son", "interface", ui_volume), 0.0, 1.0)
	sensitivity = clampf(cfg.get_value("souris", "sensibilite", sensitivity), 0.2, 3.0)
	invert_y = cfg.get_value("souris", "inverser_y", invert_y)


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, "Master")


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		return
	AudioServer.set_bus_mute(index, linear <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.001)))
