extends Node
## Réglages du joueur (son, souris, vidéo), enregistrés sur la machine dans
## user://parametres.cfg et rechargés au démarrage. Autoload "Settings".
##
## Vidéo :
##   qualité     Basse / Moyenne / Haute (Haute = le rendu prévu par les maps). Appliquée
##               à toute la fenêtre (MSAA, taille des ombres) et à chaque soleil et
##               environnement qui entre dans la scène : les maps n'ont rien à faire.
##   mode        plein écran, fenêtré, fenêtré sans bordures (fenêtre sur tout l'écran)
##   résolution  en fenêtré : taille de la fenêtre ; en plein écran et sans bordures :
##               résolution du rendu 3D (l'écran garde la sienne, l'interface reste nette)
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

const QUALITY_NAMES := ["Basse", "Moyenne", "Haute"]
const QUALITY_HELP := [
	"Sans ombres ni halo lumineux, sans anticrénelage : pour les petites configurations.",
	"Ombres moins détaillées, anticrénelage léger.",
	"Ombres détaillées, halo des néons, anticrénelage : le rendu prévu.",
]
## Taille de l'atlas des ombres du soleil et MSAA de la 3D, par qualité.
const SHADOW_ATLAS := [1024, 2048, 4096]
const MSAA := [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_2X]
## Modes d'affichage : identifiant enregistré, nom affiché.
const WINDOW_MODES := [["fullscreen", "Plein écran"], ["windowed", "Fenêtré"], ["borderless", "Fenêtré sans bordures"]]
## Résolutions proposées (16:9), limitées à la taille de l'écran.
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080),
	Vector2i(2560, 1440), Vector2i(3200, 1800), Vector2i(3840, 2160)]
const VIDEO_KEYS := ["quality", "window_mode", "resolution"]

## Volumes de 0.0 (muet) à 1.0.
var master_volume := 0.8
var sfx_volume := 1.0
var ui_volume := 0.8
## Multiplicateur de la sensibilité de la souris (0.2 à 3.0).
var sensitivity := 1.0
## Inverser l'axe vertical de la souris.
var invert_y := false
## Qualité des graphismes : indice dans QUALITY_NAMES.
var quality := 2
## "fullscreen", "windowed" ou "borderless" (voir WINDOW_MODES).
var window_mode := "windowed"
var resolution := Vector2i(1280, 720)


func _ready() -> void:
	_ensure_bus(SFX_BUS)
	_ensure_bus(UI_BUS)
	_add_mastering()
	load_settings()
	apply()
	if not Effects.headless():
		# Chaque nœud qui entre dans la scène (carte chargée, aperçu…) reçoit la qualité.
		get_tree().node_added.connect(_apply_quality)
		apply_video.call_deferred()      # la fenêtre doit exister


## Traitement du son (pas sur le serveur dédié) :
##   - Master : compresseur (les tirs et explosions claquent sans écraser le reste)
##     puis limiteur (jamais de saturation, même avec beaucoup de sons d'un coup) ;
##   - Effets : réverbération courte et discrète (ruelles en béton de NEO-EDO).
func _add_mastering() -> void:
	if Effects.headless():
		return
	var master := AudioServer.get_bus_index("Master")
	if AudioServer.get_bus_effect_count(master) == 0:
		var compressor := AudioEffectCompressor.new()
		compressor.threshold = -14.0
		compressor.ratio = 4.0
		compressor.attack_us = 5000.0
		compressor.release_ms = 180.0
		compressor.gain = 2.0
		AudioServer.add_bus_effect(master, compressor)
		var limiter := AudioEffectHardLimiter.new()
		limiter.ceiling_db = -0.5
		AudioServer.add_bus_effect(master, limiter)
	var sfx := AudioServer.get_bus_index(SFX_BUS)
	if AudioServer.get_bus_effect_count(sfx) == 0:
		var reverb := AudioEffectReverb.new()
		reverb.room_size = 0.35
		reverb.damping = 0.7
		reverb.wet = 0.08
		reverb.dry = 1.0
		AudioServer.add_bus_effect(sfx, reverb)


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
	if key in VIDEO_KEYS:
		apply_video()
	apply()


func reset_audio() -> void:
	master_volume = 0.8
	sfx_volume = 1.0
	ui_volume = 0.8
	apply()
	save_settings()


func reset_mouse() -> void:
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
	cfg.set_value("video", "qualite", quality)
	cfg.set_value("video", "mode", window_mode)
	cfg.set_value("video", "resolution", resolution)
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
	quality = clampi(int(cfg.get_value("video", "qualite", quality)), 0, QUALITY_NAMES.size() - 1)
	var mode: String = str(cfg.get_value("video", "mode", window_mode))
	window_mode = mode if WINDOW_MODES.any(func(m): return m[0] == mode) else window_mode
	var saved: Variant = cfg.get_value("video", "resolution", resolution)
	if saved is Vector2i and saved.x >= 640 and saved.y >= 360:
		resolution = saved


# ---------------------------------------------------------------- Vidéo

## Résolutions proposées sur cet écran : celles qui tiennent, plus celle de l'écran.
func available_resolutions() -> Array[Vector2i]:
	var screen := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	var list: Array[Vector2i] = []
	for r in RESOLUTIONS:
		if r.x <= screen.x and r.y <= screen.y:
			list.append(r)
	if not screen in list and screen.x >= 640:
		list.append(screen)
	if list.is_empty():
		list.append(RESOLUTIONS[0])
	list.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x * a.y < b.x * b.y)
	return list


## Mode d'affichage, résolution et qualité. Pas sur le serveur dédié (pas de fenêtre).
func apply_video() -> void:
	if Effects.headless():
		return
	var root := get_tree().root
	var screen_id := DisplayServer.window_get_current_screen()
	var screen := DisplayServer.screen_get_size(screen_id)
	var size := Vector2i(mini(resolution.x, screen.x), mini(resolution.y, screen.y))
	match window_mode:
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		"borderless":
			# FULLSCREEN (non exclusif) = fenêtre sans bordures qui couvre l'écran.
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_size(size)
			DisplayServer.window_set_position(DisplayServer.screen_get_position(screen_id) + (screen - size) / 2)
	# En plein écran, la résolution choisie est celle du rendu 3D.
	root.scaling_3d_scale = 1.0 if window_mode == "windowed" else clampf(float(size.y) / screen.y, 0.25, 1.0)
	root.msaa_3d = MSAA[quality]
	RenderingServer.directional_shadow_atlas_set_size(SHADOW_ATLAS[quality], true)
	_apply_quality_tree(root)


func _apply_quality_tree(node: Node) -> void:
	_apply_quality(node)
	for child in node.get_children():
		_apply_quality_tree(child)


## Qualité sur un nœud : ombres des soleils, halo des environnements. Les valeurs
## prévues par la map sont gardées en métadonnée pour pouvoir remonter.
func _apply_quality(node: Node) -> void:
	if node is DirectionalLight3D:
		var sun := node as DirectionalLight3D
		if not sun.has_meta("map_shadow"):
			sun.set_meta("map_shadow", sun.shadow_enabled)
			sun.set_meta("map_shadow_mode", sun.directional_shadow_mode)
		sun.shadow_enabled = sun.get_meta("map_shadow") and quality > 0
		var mode: int = sun.get_meta("map_shadow_mode")
		if quality == 1 and mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS:
			mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_mode = mode
	elif node is WorldEnvironment and (node as WorldEnvironment).environment:
		var env := (node as WorldEnvironment).environment
		if not env.has_meta("map_glow"):
			env.set_meta("map_glow", env.glow_enabled)
		env.glow_enabled = env.get_meta("map_glow") and quality > 0


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
