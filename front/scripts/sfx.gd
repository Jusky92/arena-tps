extends Node
## Lecture des effets sonores. Autoload "Sfx".
##
##   Sfx.ui("ui_click")                       son d'interface (bus Interface)
##   Sfx.play("hit")                          son de partie non spatialisé (bus Effets)
##   Sfx.play_at("shot_smg", position)        son de partie placé dans le monde 3D
##
## Les sons sont générés par tools/generate_sounds.py (front/assets/sounds/).

const SOUNDS := {
	"shot_shotgun": preload("res://assets/sounds/shot_shotgun.wav"),
	"shot_smg": preload("res://assets/sounds/shot_smg.wav"),
	"shot_sniper": preload("res://assets/sounds/shot_sniper.wav"),
	"hit": preload("res://assets/sounds/hit.wav"),
	"kill": preload("res://assets/sounds/kill.wav"),
	"reload": preload("res://assets/sounds/reload.wav"),
	"ability_shield": preload("res://assets/sounds/ability_shield.wav"),
	"ability_dash": preload("res://assets/sounds/ability_dash.wav"),
	"ability_pierce": preload("res://assets/sounds/ability_pierce.wav"),
	"spawn": preload("res://assets/sounds/spawn.wav"),
	"deflect": preload("res://assets/sounds/deflect.wav"),
	"ui_click": preload("res://assets/sounds/ui_click.wav"),
	"ui_open": preload("res://assets/sounds/ui_open.wav"),
	"ui_close": preload("res://assets/sounds/ui_close.wav"),
}

## Son de tir selon le modèle d'arme (WeaponData.Model : SHOTGUN, SMG, SNIPER).
const SHOT_BY_MODEL := ["shot_shotgun", "shot_smg", "shot_sniper"]
## Son de capacité selon ClassData.Ability (SHIELD, DASH, PIERCE).
const ABILITY_SOUNDS := ["ability_shield", "ability_dash", "ability_pierce"]

const MAX_VOICES := 24      ## nombre max de sons simultanés (évite la saturation)

var _voices := 0


func ui(sound: String, volume_db := 0.0) -> void:
	_play_2d(sound, Settings.UI_BUS, volume_db, 1.0)


func play(sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	_play_2d(sound, Settings.SFX_BUS, volume_db, pitch)


func play_at(sound: String, position: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	if Effects.headless() or not SOUNDS.has(sound) or _voices >= MAX_VOICES:
		return
	var scene := get_tree().current_scene
	if scene == null or not scene is Node3D:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = SOUNDS[sound]
	p.bus = Settings.SFX_BUS
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.unit_size = 10.0
	p.max_distance = 110.0
	p.attenuation_filter_cutoff_hz = 6000.0
	scene.add_child(p)
	p.global_position = position
	_start(p)


func shot_sound(model: int) -> String:
	return SHOT_BY_MODEL[clampi(model, 0, SHOT_BY_MODEL.size() - 1)]


func ability_sound(ability: int) -> String:
	return ABILITY_SOUNDS[clampi(ability, 0, ABILITY_SOUNDS.size() - 1)]


func _play_2d(sound: String, bus: String, volume_db: float, pitch: float) -> void:
	if Effects.headless() or not SOUNDS.has(sound) or _voices >= MAX_VOICES:
		return
	var p := AudioStreamPlayer.new()
	p.stream = SOUNDS[sound]
	p.bus = bus
	p.volume_db = volume_db
	p.pitch_scale = pitch
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
