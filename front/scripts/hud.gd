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
const HEARTBEAT_INTERVAL := 0.9    # battement de cœur quand la vie est basse
const INVISIBLE_TINT := Color(0.45, 0.78, 1.0)
const REVEALED_TINT := Color(1.0, 0.55, 0.2)
const InvisibilityShader := preload("res://shaders/invisibility_vignette.gdshader")

@onready var _vignette: ColorRect = %Vignette
@onready var _crosshair: Crosshair = %Crosshair
@onready var _damage_indicator: DamageIndicator = %DamageIndicator
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
@onready var _other_icon: TextureRect = %OtherIcon
@onready var _other_key: Label = %OtherKey
@onready var _grenade_icons: Array[TextureRect] = [%Grenade1, %Grenade2]
@onready var _splat: ColorRect = %Splat
@onready var _buffs: Label = %Buffs
@onready var _armor_bar: ProgressBar = %ArmorBar
@onready var _super_chip: Control = %SuperChip
@onready var _super_label: Label = %SuperLabel
@onready var _status: Label = %Status
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
var _splat_tween: Tween
var _heartbeat := 0.0
# Invisibilité (super-pouvoir) : voile sur les bords de l'écran et étiquette sous le
# réticule, construits ici (pas dans hud.tscn).
var _invis_overlay: ColorRect
var _invis_material: ShaderMaterial
var _invis_box: VBoxContainer
var _invis_label: Label
var _invis_bar: ProgressBar
var _was_invisible := false


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
	_build_invisibility_indicator()


func _build_invisibility_indicator() -> void:
	var root: Control = _protect_box.get_parent()
	_invis_material = ShaderMaterial.new()
	_invis_material.shader = InvisibilityShader
	_invis_overlay = ColorRect.new()
	_invis_overlay.name = "InvisibleVeil"
	_invis_overlay.material = _invis_material
	_invis_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_invis_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_invis_overlay.visible = false
	root.add_child(_invis_overlay)
	root.move_child(_invis_overlay, 0)        # sous le reste du HUD
	_invis_box = VBoxContainer.new()
	_invis_box.name = "Invisible"
	_invis_box.set_anchors_preset(Control.PRESET_CENTER)
	_invis_box.offset_left = -120.0
	_invis_box.offset_right = 120.0
	_invis_box.offset_top = 118.0
	_invis_box.offset_bottom = 160.0
	_invis_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_invis_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_invis_box.add_theme_constant_override("separation", 4)
	_invis_box.visible = false
	root.add_child(_invis_box)
	_invis_label = Label.new()
	_invis_label.theme_type_variation = &"HudLabel"
	_invis_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_invis_box.add_child(_invis_label)
	_invis_bar = ProgressBar.new()
	_invis_bar.theme_type_variation = &"ProtectBar"
	_invis_bar.custom_minimum_size = Vector2(0, 4)
	_invis_bar.max_value = 1.0
	_invis_bar.show_percentage = false
	_invis_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_invis_box.add_child(_invis_bar)


## Relie le HUD à un joueur (appelé par la scène de jeu).
func bind(player: Node) -> void:
	if _player and is_instance_valid(_player):
		for pair in [["health_changed", _on_health_changed], ["damaged", _on_damaged],
				["ammo_changed", _on_ammo_changed], ["hit_confirmed", _on_hit_confirmed],
				["weapon_switched", _on_weapon_switched], ["grenades_changed", _on_grenades_changed],
				["splatted", _on_splatted]]:
			if _player.is_connected(pair[0], pair[1]):
				_player.disconnect(pair[0], pair[1])
		for w in _player.weapons:
			if is_instance_valid(w) and w.fired.is_connected(_on_fired):
				w.fired.disconnect(_on_fired)
	_player = player
	_damage_indicator.player = player
	var data: ClassData = player.class_data
	_class_label.text = data.display_name.to_upper()
	_class_label.add_theme_color_override("font_color", data.color.lightened(0.3))
	_vital_style.border_color = Color(data.color, 0.6)
	_ability_fill.bg_color = data.color
	_ability_icon.texture = UiIcons.ability(data)
	player.health_changed.connect(_on_health_changed)
	player.damaged.connect(_on_damaged)
	player.ammo_changed.connect(_on_ammo_changed)
	player.hit_confirmed.connect(_on_hit_confirmed)
	player.weapon_switched.connect(_on_weapon_switched)
	player.grenades_changed.connect(_on_grenades_changed)
	player.splatted.connect(_on_splatted)
	for w in player.weapons:
		w.fired.connect(_on_fired)
	# Affiche tout de suite l'état actuel (les signaux du joueur ont pu partir avant le branchement).
	_on_health_changed(player.health, data.max_health, false)
	_on_weapon_switched(player.weapon_slot)
	_on_grenades_changed(player.grenades)
	_splat.visible = false
	_start_key_help_fade()


func _process(delta: float) -> void:
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
		# Arme légendaire : réticule doré, qui grossit quand un ennemi est accroché.
		var legendary: bool = weapon.data != null and weapon.data.legendary
		var locked: bool = legendary and weapon.assist_target() != null
		_crosshair.modulate = LegendaryEvent.GOLD if legendary else Color.WHITE
		_crosshair.pivot_offset = _crosshair.size / 2.0
		_crosshair.scale = Vector2.ONE * (1.45 if locked else 1.0)

	_status.visible = _player.alive and _player.is_slowed()
	_update_bonuses()
	_update_invisibility()

	# Vie basse : battement de cœur.
	if _player.alive and float(_player.health) / data.max_health <= LOW_HEALTH_RATIO:
		_heartbeat -= delta
		if _heartbeat <= 0.0:
			_heartbeat = HEARTBEAT_INTERVAL
			Sfx.play("heartbeat", -6.0)
	else:
		_heartbeat = 0.0

	# Protection d'apparition.
	var protect: float = _player.spawn_protection
	_protect_box.visible = _player.alive and protect > 0.0
	if _protect_box.visible:
		_protect_label.text = "PROTÉGÉ  %.1f s" % protect
		_protect_bar.value = protect / _player.SPAWN_PROTECTION_TIME


## Dispersion de l'arme (degrés) convertie en pixels à l'écran, plus un écart
## quand on se déplace ou qu'on est en l'air.
func _spread_pixels(data: ClassData) -> float:
	var w: WeaponData = _player.weapon.data
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


func _on_damaged(_amount: int, source: Vector3) -> void:
	_damage_indicator.add(source)
	Sfx.play("hurt", -7.0)
	var mat := _vignette.material as ShaderMaterial
	if _vignette_tween:
		_vignette_tween.kill()
	mat.set_shader_parameter("intensity", 0.7)
	_vignette_tween = create_tween()
	_vignette_tween.tween_method(func(v: float) -> void: mat.set_shader_parameter("intensity", v), 0.7, 0.0, 0.45)


## Arme en main : grande icône et munitions ; une autre arme en petit, avec sa touche
## (avec une arme spéciale en main : la principale).
func _on_weapon_switched(slot: int) -> void:
	var current: WeaponData = _player.weapon.data
	_weapon_icon.texture = UiIcons.weapon(current)
	_weapon_label.text = current.display_name
	var other_slot := 1 if slot == 0 else 0
	var other: WeaponData = _player.weapons[other_slot].data if _player.weapons.size() > other_slot else null
	_other_icon.texture = UiIcons.weapon(other)
	_other_key.text = "[%d]" % (other_slot + 1)
	_on_ammo_changed(_player.weapon.ammo, current.mag_size, _player.weapon.is_reloading())


## Bonus en cours : armure, effets avec leur temps restant, super-pouvoir en réserve.
func _update_bonuses() -> void:
	var p := _player
	_armor_bar.visible = p.armor > 0
	_armor_bar.value = p.armor
	var parts := []
	if p.double_jump_time > 0.0:
		parts.append("DOUBLE SAUT %d s" % ceili(p.double_jump_time))
	if p.speed_time > 0.0:
		parts.append("VITESSE %d s" % ceili(p.speed_time))
	if p.overload_time > 0.0:
		parts.append("SURCHARGE %d s" % ceili(p.overload_time))
	if p.special and p.special_time_left() > 0.0:
		parts.append("%s %d s" % [p.special.data.display_name.to_upper(), ceili(p.special_time_left())])
	if p.armor > 0:
		parts.append("ARMURE %d" % p.armor)
	_buffs.visible = p.alive and not parts.is_empty()
	_buffs.text = "  ·  ".join(parts)
	_super_chip.visible = p.alive and p.super_power >= 0
	if _super_chip.visible:
		var info: Dictionary = Pickups.SUPER_INFO[p.super_power]
		_super_label.text = "[F] %s" % info.name.to_upper()
		_super_label.add_theme_color_override("font_color", info.color)


## Invisibilité : voile bleuté et « INVISIBLE » ; en tirant, on est vu un instant
## (orange, « DÉCOUVERT »). Un son au début et à la fin.
func _update_invisibility() -> void:
	var invisible: bool = _player.alive and _player.invisible_time > 0.0
	if invisible != _was_invisible:
		_was_invisible = invisible
		Sfx.play("powerup", -8.0, 1.25 if invisible else 0.7)
	_invis_overlay.visible = invisible
	_invis_box.visible = invisible
	if not invisible:
		return
	var revealed: bool = _player.is_revealed()
	var tint := REVEALED_TINT if revealed else INVISIBLE_TINT
	_invis_material.set_shader_parameter("tint", tint)
	_invis_material.set_shader_parameter("strength", 1.3 if revealed else 1.0)
	var left := ceili(_player.invisible_time)
	_invis_label.text = ("DÉCOUVERT  ·  %d s" if revealed else "INVISIBLE  ·  %d s") % left
	_invis_label.add_theme_color_override("font_color", tint)
	_invis_bar.value = _player.invisible_time / Pickups.INVISIBILITY_TIME
	_invis_bar.modulate = tint


func _on_grenades_changed(count: int) -> void:
	for i in _grenade_icons.size():
		_grenade_icons[i].modulate.a = 1.0 if i < count else 0.18


## Touché par le lance-caca : tache cartoon qui s'estompe.
func _on_splatted(duration: float) -> void:
	var mat := _splat.material as ShaderMaterial
	mat.set_shader_parameter("seed", randf() * 100.0)
	mat.set_shader_parameter("amount", 1.0)
	_splat.visible = true
	if _splat_tween:
		_splat_tween.kill()
	_splat_tween = create_tween()
	_splat_tween.tween_interval(duration * 0.6)
	_splat_tween.tween_method(func(v: float) -> void: mat.set_shader_parameter("amount", v), 1.0, 0.0, duration * 0.4)
	_splat_tween.tween_callback(func() -> void: _splat.visible = false)


func _on_ammo_changed(ammo: int, mag_size: int, reloading: bool) -> void:
	if mag_size <= 0:
		_ammo_label.text = "∞"      # katana : pas de chargeur
		_ammo_max.text = ""
		_ammo_label.modulate.a = 1.0
		_ammo_label.add_theme_color_override("font_color", Color.WHITE)
		_was_low_ammo = false
		return
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


## Marque de touche sur le réticule (jaune à la tête, rouge quand on élimine), avec un
## son de confirmation : « tic » pour une touche, « ting » métallique pour la tête.
func _on_hit_confirmed(killed: bool, headshot: bool) -> void:
	if headshot:
		Sfx.play("headshot", -3.0)
	if killed:
		Sfx.play("kill", -2.0)
	elif not headshot:
		Sfx.play("hit", -5.0)
	_crosshair.hit(killed, headshot)


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
	_damage_indicator.clear()
	_splat.visible = false
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
