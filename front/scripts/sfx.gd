extends Node
## Lecture des effets sonores. Autoload "Sfx".
##
##   Sfx.ui("ui_click")                          son d'interface (bus Interface)
##   Sfx.play("hit")                             son de partie non spatialisé (bus Effets)
##   Sfx.play_at("shot_smg", position)           son de partie placé dans le monde 3D
##   Sfx.play_at("explosion", position, 0, 1, 160)   … audible plus loin
##
## Les sons sont générés par tools/generate_sounds.py (front/assets/sounds/, aucune
## licence à gérer). Un son peut avoir des variantes (« step », « step_2 »…) : une
## est tirée au hasard à chaque lecture. Pour remplacer un son par un vrai
## enregistrement libre de droits, déposer « nom.ogg » ou « nom.wav » (et ses
## variantes « nom_2.ogg »…) dans front/assets/sounds/custom/ : voir LISEZMOI.md.

const DIR := "res://assets/sounds/"
const CUSTOM_DIR := "res://assets/sounds/custom/"

## Sons du jeu -> nombre de variantes générées.
const VARIANTS := {
	"shot_smg": 3, "shot_shotgun": 2, "shot_sniper": 2, "shot_rocket": 1, "shot_flame": 3,
	"shot_laser": 2, "katana_swing": 2, "katana_hit": 1, "poop_launch": 1, "poop_splat": 1,
	"grenade_throw": 1, "grenade_bounce": 2, "explosion": 2,
	"hit": 1, "headshot": 1, "kill": 1, "impact_body": 2, "impact_world": 3, "hurt": 1, "heartbeat": 1,
	"step": 4, "land": 1, "switch": 1, "reload": 1,
	"ability_shield": 1, "ability_dash": 1, "ability_pierce": 1, "ability_charge": 1,
	"pickup": 1, "powerup": 1, "spawn": 1, "deflect": 1,
	"ui_click": 1, "ui_open": 1, "ui_close": 1, "ambience": 1,
}

## Sons dont la hauteur varie un peu à chaque lecture (moins répétitif).
const PITCH_VARIATION := {
	"shot_smg": 0.05, "shot_shotgun": 0.04, "shot_sniper": 0.03, "shot_laser": 0.06, "shot_flame": 0.1,
	"katana_swing": 0.08, "step": 0.1, "impact_world": 0.12, "impact_body": 0.08, "grenade_bounce": 0.1,
	"explosion": 0.06, "land": 0.06,
}

## Son de tir selon le modèle d'arme (WeaponData.Model : SHOTGUN, SMG, SNIPER, ROCKET,
## FLAMER, LASER, KATANA, POOP, GRENADE).
const SHOT_BY_MODEL := ["shot_shotgun", "shot_smg", "shot_sniper", "shot_rocket", "shot_flame",
	"shot_laser", "katana_swing", "poop_launch", "grenade_throw"]
## Son de capacité selon ClassData.Ability (SHIELD, DASH, PIERCE, CHARGE).
const ABILITY_SOUNDS := ["ability_shield", "ability_dash", "ability_pierce", "ability_charge"]

const MAX_VOICES := 40      ## nombre max de sons simultanés (évite la saturation)
const DEFAULT_RANGE := 110.0

var _voices := 0
var _streams := {}          # nom -> Array[AudioStream] (variantes)


func _ready() -> void:
	if Effects.headless():
		return              # serveur dédié : aucun son
	for sound in VARIANTS:
		_streams[sound] = _load_variants(sound, VARIANTS[sound])


## Variantes d'un son : celles du dossier custom/ si on y a déposé le son, sinon
## celles générées.
func _load_variants(sound: String, count: int) -> Array:
	for ext in ["ogg", "wav"]:
		if ResourceLoader.exists(CUSTOM_DIR + sound + "." + ext):
			var custom := [load(CUSTOM_DIR + sound + "." + ext)]
			var i := 2
			while ResourceLoader.exists(CUSTOM_DIR + "%s_%d.%s" % [sound, i, ext]):
				custom.append(load(CUSTOM_DIR + "%s_%d.%s" % [sound, i, ext]))
				i += 1
			return custom
	var list := []
	for i in range(1, count + 1):
		var path := DIR + (sound if i == 1 else "%s_%d" % [sound, i]) + ".wav"
		if ResourceLoader.exists(path):
			list.append(load(path))
	return list


## Un des fichiers d'un son (tiré au hasard), ou null s'il n'existe pas.
func stream(sound: String) -> AudioStream:
	var list: Array = _streams.get(sound, [])
	return list[randi() % list.size()] if not list.is_empty() else null


## Son en boucle (ambiance) : copie du fichier réglée pour boucler sans fin.
func looping(sound: String) -> AudioStream:
	var s := stream(sound)
	if s is AudioStreamWAV:
		var wav: AudioStreamWAV = (s as AudioStreamWAV).duplicate()
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
		return wav
	if s is AudioStreamOggVorbis:
		var ogg: AudioStreamOggVorbis = (s as AudioStreamOggVorbis).duplicate()
		ogg.loop = true
		return ogg
	return s


func ui(sound: String, volume_db := 0.0) -> void:
	_play_2d(sound, Settings.UI_BUS, volume_db, 1.0)


func play(sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	_play_2d(sound, Settings.SFX_BUS, volume_db, pitch)


## Son placé dans le monde : il baisse avec la distance et s'éteint à `max_distance`
## mètres (explosions : plus loin ; pas : plus près).
func play_at(sound: String, position: Vector3, volume_db := 0.0, pitch := 1.0, max_distance := DEFAULT_RANGE) -> void:
	if Effects.headless() or _voices >= MAX_VOICES:
		return
	var s := stream(sound)
	var scene := get_tree().current_scene
	if s == null or scene == null or not scene is Node3D:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.bus = Settings.SFX_BUS
	p.volume_db = volume_db
	p.pitch_scale = _pitch(sound, pitch)
	p.unit_size = clampf(max_distance / 11.0, 3.0, 16.0)
	p.max_distance = max_distance
	p.attenuation_filter_cutoff_hz = 6000.0
	scene.add_child(p)
	p.global_position = position
	_start(p)


func shot_sound(model: int) -> String:
	return SHOT_BY_MODEL[clampi(model, 0, SHOT_BY_MODEL.size() - 1)]


func ability_sound(ability: int) -> String:
	return ABILITY_SOUNDS[clampi(ability, 0, ABILITY_SOUNDS.size() - 1)]


func _pitch(sound: String, pitch: float) -> float:
	var spread: float = PITCH_VARIATION.get(sound, 0.0)
	return pitch * (1.0 + randf_range(-spread, spread))


func _play_2d(sound: String, bus: String, volume_db: float, pitch: float) -> void:
	if Effects.headless() or _voices >= MAX_VOICES:
		return
	var s := stream(sound)
	if s == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.bus = bus
	p.volume_db = volume_db
	p.pitch_scale = _pitch(sound, pitch)
	# Les sons d'interface continuent même si la scène change (ex. clic sur "Quitter").
	add_child(p)
	_start(p)


func _start(p: Node) -> void:
	_voices += 1
	p.finished.connect(func() -> void:
		_voices -= 1
		p.queue_free())
	p.tree_exiting.connect(func() -> void:
		if p.playing:
			_voices -= 1)
	p.play()
