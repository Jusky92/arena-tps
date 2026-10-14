extends CanvasLayer
## Interface en jeu : vie, capacité, munitions, réticule, effets de dégâts,
## protection d'apparition, écran de mort. La mise en page est dans scenes/ui/hud.tscn
## (modifiable dans l'éditeur, styles dans ui/theme/neon_theme.tres) ; ce script
## ne fait que la mettre à jour. On l'attache au joueur avec bind() (rappelé si le
## joueur change de classe).

const HEALTH_HIGH := Color(0.32, 0.95, 0.55)
const HEALTH_MID := Color(1.0, 0.84, 0.25)
const HEALTH_LOW := Color(1.0, 0.33, 0.36)
const LOW_HEALTH_RATIO := 0.35
const HP_PER_TICK := 25            # un repère sur la barre de vie tous les 25 PV
const KEY_HELP_TIME := 10.0        # l'aide des touches s'efface après ce délai

@onready var _vignette: ColorRect = %Vignette
@onready var _crosshair: Crosshair = %Crosshair
@onready var _protect_box: Control = %Protect
@onready var _protect_label: Label = %ProtectLabel
@onready var _protect_bar: ProgressBar = %ProtectBar
@onready var _next_class_label: Label = %NextClass
@onready var _vital_panel: PanelContainer = %VitalPanel
@onready var _class_label: Label = %ClassName
@onready var _health_value: Label = %HealthValue
@onready var _health_max: Label = %HealthMax
@onready var _health_bar: ProgressBar = %HealthBar
@onready var _ghost_bar: ProgressBar = %GhostBar
@onready var _health_ticks: Control = %HealthTicks
@onready var _ability_icon: TextureRect = %AbilityIcon
@onready var _ability_label: Label = %AbilityLabel
@onready var _ability_bar: ProgressBar = %AbilityBar
@onready var _weapon_icon: TextureRect = %WeaponIcon
@onready var _weapon_label: Label = %WeaponName
@onready var _ammo_label: Label = %Ammo
@onready var _ammo_max: Label = %AmmoMax
@onready var _reload_bar: ProgressBar = %ReloadBar
@onready var _key_help: Label = %KeyHelp
@onready var _death_overlay: Control = %DeathOverlay
@onready var _death_title: Label = %DeathTitle
@onready var _killer_label: Label = %Killer
@onready var _countdown: Label = %Countdown

var _player: Node
var _health_fill: StyleBoxFlat
var _ability_fill: StyleBoxFlat
var _vital_style: StyleBoxFlat
var _max_health := 100
var _health_tween: Tween
var _vignette_tween: Tween
var _ammo_tween: Tween
var _was_low_ammo := false
var _key_help_started := false


func _ready() -> void:
	# Copies des styles du thème qu'on recolore selon la classe / la vie.
	_health_fill = _health_bar.get_theme_stylebox("fill").duplicate()
	_health_bar.add_theme_stylebox_override("fill", _health_fill)
	_ability_fill = _ability_bar.get_theme_stylebox("fill").duplicate()
	_ability_bar.add_theme_stylebox_override("fill", _ability_fill)
	_vital_style = _vital_panel.get_theme_stylebox("panel").duplicate()
	_vital_panel.add_theme_stylebox_override("panel", _vital_style)
	_health_ticks.draw.connect(_draw_health_ticks)
	_ammo_label.resized.connect(func() -> void: _ammo_label.pivot_offset = _ammo_label.size / 2.0)
	_death_title.resized.connect(func() -> void: _death_title.pivot_offset = _death_title.size / 2.0)


## Relie le HUD à un joueur (appelé par la scène de jeu).
func bind(player: Node) -> void:
	if _player and is_instance_valid(_player):
		for pair in [["health_changed", _on_health_changed], ["damaged", _on_damaged],
				["ammo_changed", _on_ammo_changed], ["hit_confirmed", _on_hit_confirmed]]:
			if _player.is_connected(pair[0], pair[1]):
				_player.disconnect(pair[0], pair[1])
		if is_instance_valid(_player.weapon) and _player.weapon.fired.is_connected(_on_fired):
			_player.weapon.fired.disconnect(_on_fired)
	_player = player
	var data: ClassData = player.class_data
	_class_label.text = data.display_name.to_upper()
	_class_label.add_theme_color_override("font_color", data.color.lightened(0.3))
	_vital_style.border_color = Color(data.color, 0.6)
	_ability_fill.bg_color = data.color
	_ability_icon.texture = UiIcons.ability(data)
	_weapon_icon.texture = UiIcons.weapon(data.weapon)
	_weapon_label.text = data.weapon.display_name
	player.health_changed.connect(_on_health_changed)
	player.damaged.connect(_on_damaged)
	player.ammo_changed.connect(_on_ammo_changed)
	player.hit_confirmed.connect(_on_hit_confirmed)
	player.weapon.fired.connect(_on_fired)
	# Affiche tout de suite l'état actuel (les signaux du joueur ont pu partir avant le branchement).
	_on_health_changed(player.health, data.max_health, false)
	_on_ammo_changed(player.weapon.ammo, data.weapon.mag_size, player.weapon.is_reloading())
	_start_key_help_fade()


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var data: ClassData = _player.class_data
	# Capacité : barre de recharge.
	var ratio: float = _player.ability_ready_ratio()
	_ability_bar.value = ratio
	if _player.ability_active():
		_ability_label.text = "%s  ·  ACTIVE" % data.ability_name.to_upper()
		_ability_icon.modulate = Color.WHITE
	elif ratio >= 1.0:
		_ability_label.text = "[E]  %s  ·  PRÊT" % data.ability_name.to_upper()
		_ability_icon.modulate = data.color.lightened(0.3)
	else:
		_ability_label.text = "[E]  %s  ·  %.1f s" % [data.ability_name.to_upper(), (1.0 - ratio) * data.ability_cooldown]
		_ability_icon.modulate = Color(1, 1, 1, 0.35)
	_ability_fill.bg_color = data.color if ratio >= 1.0 else data.color.darkened(0.45)

	# Rechargement.
	var weapon: Node = _player.weapon
	_reload_bar.visible = weapon.is_reloading()
	_reload_bar.value = weapon.reload_progress()

	# Réticule : masqué en courant, écart = dispersion réelle de l'arme à l'écran.
	_crosshair.visible = _player.alive and not _player.is_sprinting()
	if _crosshair.visible:
		_crosshair.set_spread(_spread_pixels(data))

	# Protection d'apparition.
	var protect: float = _player.spawn_protection
	_protect_box.visible = _player.alive and protect > 0.0
	if _protect_box.visible:
		_protect_label.text = "PROTÉGÉ  %.1f s" % protect
		_protect_bar.value = protect / _player.SPAWN_PROTECTION_TIME


## Dispersion de l'arme (degrés) convertie en pixels à l'écran, plus un écart
## quand on se déplace ou qu'on est en l'air.
func _spread_pixels(data: ClassData) -> float:
	var w := data.weapon
	var deg: float = w.aim_spread_deg if _player.is_aiming() else w.spread_deg
	if _player.crouching:
		deg *= _player.CROUCH_SPREAD_FACTOR
	var camera: Camera3D = _player.camera
	var half_height := get_viewport().get_visible_rect().size.y / 2.0
	var px := tan(deg_to_rad(deg)) / tan(deg_to_rad(camera.fov / 2.0)) * half_height
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length() / maxf(data.sprint_speed, 0.1)
	var airborne := 0.0 if _player.is_on_floor() else 8.0
	return 4.0 + px + speed * 10.0 + airborne


# ---------------------------------------------------------------- Événements

func _on_health_changed(health: int, max_health: int, animate := true) -> void:
	var lost := health < _health_bar.value and animate
	if max_health != _max_health:
		_max_health = max_health
		_health_ticks.queue_redraw()
	_health_bar.max_value = max_health
	_ghost_bar.max_value = max_health
	_health_value.text = str(health)
	_health_max.text = "/ %d" % max_health
	if _health_tween:
		_health_tween.kill()
	if animate:
		# La vraie barre descend tout de suite ; la barre blanche "fantôme" rattrape ensuite.
		_health_tween = create_tween()
		_health_tween.tween_property(_health_bar, "value", float(health), 0.12)
		if lost:
			_health_tween.tween_interval(0.35)
		_health_tween.tween_property(_ghost_bar, "value", float(health), 0.35 if lost else 0.12)
	else:
		_health_bar.value = health
		_ghost_bar.value = health

	var ratio := float(health) / max_health
	var color := HEALTH_HIGH if ratio > 0.6 else (HEALTH_MID if ratio > LOW_HEALTH_RATIO else HEALTH_LOW)
	_health_fill.bg_color = color
	_health_fill.shadow_color = Color(color, 0.3)
	_health_value.add_theme_color_override("font_color", Color.WHITE if ratio > LOW_HEALTH_RATIO else HEALTH_LOW)
	var low := clampf((LOW_HEALTH_RATIO - ratio) / LOW_HEALTH_RATIO, 0.0, 1.0) if health > 0 else 0.0
	(_vignette.material as ShaderMaterial).set_shader_parameter("low_health", low)


func _on_damaged(_amount: int) -> void:
	var mat := _vignette.material as ShaderMaterial
	if _vignette_tween:
		_vignette_tween.kill()
	mat.set_shader_parameter("intensity", 0.7)
	_vignette_tween = create_tween()
	_vignette_tween.tween_method(func(v: float) -> void: mat.set_shader_parameter("intensity", v), 0.7, 0.0, 0.45)


func _on_ammo_changed(ammo: int, mag_size: int, reloading: bool) -> void:
	_ammo_label.text = str(ammo)
	_ammo_max.text = "/ %d" % mag_size
	_ammo_label.modulate.a = 0.4 if reloading else 1.0
	var low: bool = not reloading and ammo <= maxi(1, mag_size / 4)
	_ammo_label.add_theme_color_override("font_color", HEALTH_LOW if low else Color.WHITE)
	if low and not _was_low_ammo:
		if _ammo_tween:
			_ammo_tween.kill()
		_ammo_label.scale = Vector2.ONE * 1.25
		_ammo_tween = create_tween()
		_ammo_tween.tween_property(_ammo_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)
	_was_low_ammo = low


func _on_fired(_recoil_deg: float) -> void:
	_crosshair.kick()


## Marque de touche sur le réticule (rouge quand on élimine), avec un son de confirmation.
func _on_hit_confirmed(killed: bool) -> void:
	Sfx.play("kill" if killed else "hit", -2.0 if killed else -6.0)
	_crosshair.hit(killed)


func show_death(killer_name: String) -> void:
	_death_overlay.visible = true
	_death_title.text = "ÉLIMINÉ"
	_killer_label.visible = not killer_name.is_empty()
	_killer_label.text = "PAR %s" % killer_name.to_upper()
	# Entrée en "glitch" : le titre clignote et se resserre.
	_death_overlay.modulate.a = 0.0
	_death_title.scale = Vector2.ONE * 1.35
	var tween := create_tween()
	tween.tween_property(_death_overlay, "modulate:a", 1.0, 0.15)
	tween.parallel().tween_property(_death_title, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	for a in [0.3, 1.0, 0.5, 1.0]:
		tween.tween_property(_death_title, "modulate:a", a, 0.04)


func set_respawn_countdown(seconds: float) -> void:
	_countdown.text = "Réapparition dans %d…" % ceili(seconds)


func hide_death() -> void:
	_death_overlay.visible = false
	_countdown.text = ""


## Classe choisie dans le menu pause, appliquée à la prochaine apparition ("" = aucune).
func set_next_class(display_name: String, color := Color.WHITE) -> void:
	_next_class_label.visible = not display_name.is_empty()
	_next_class_label.text = "Prochaine apparition : %s" % display_name.to_upper()
	_next_class_label.add_theme_color_override("font_color", color.lightened(0.3))


# ---------------------------------------------------------------- Dessin

## Repères verticaux sur la barre de vie (un tous les HP_PER_TICK points de vie).
func _draw_health_ticks() -> void:
	var count := ceili(float(_max_health) / HP_PER_TICK)
	var w := _health_ticks.size.x
	var h := _health_ticks.size.y
	for i in range(1, count):
		var x := roundf(w * i * HP_PER_TICK / float(_max_health))
		_health_ticks.draw_rect(Rect2(x - 1.0, 0.0, 2.0, h), Color(0.02, 0.03, 0.06, 0.85))


func _start_key_help_fade() -> void:
	if _key_help_started:
		return
	_key_help_started = true
	var tween := create_tween()
	tween.tween_interval(KEY_HELP_TIME)
	tween.tween_property(_key_help, "modulate:a", 0.0, 1.0)
