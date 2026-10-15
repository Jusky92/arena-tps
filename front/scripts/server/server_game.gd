extends Node3D
## Partie en cours sur le serveur dédié (sans affichage). Créée par server_main.gd
## au lancement de la partie, libérée au retour au salon.
##
## Le serveur ne joue pas : il arbitre.
##   - les joueurs humains sont des pantins qui suivent l'état envoyé par leur client ;
##   - les bots sont simulés ici (BotBrain) et diffusés comme les joueurs ;
##   - il arbitre les tirs : il tient le chargeur de chaque arme (le client annonce
##     ses tirs et ses rechargements), puis un client signale seulement « j'ai touché
##     telle cible à tel endroit avec mon arme » ; le serveur vérifie (arme de la
##     classe, tir annoncé, portée, ligne de vue), choisit la zone (tête / corps) et
##     calcule les dégâts ;
##   - il annonce les éliminations, décide des réapparitions et tient le chronomètre ;
##   - à la fin, il envoie les résultats au back (match.finished) via BackendLink.

const PlayerScene := preload("res://scenes/player.tscn")

## Lien vers le back (donné par server_main.gd avant l'ajout à l'arbre).
var link: BackendLink

# Lus par BotBrain (scripts/bots/bot_brain.gd) à travers `brain.game`.
var map: Node3D                         # map choisie (Net.settings.map, voir MapCatalog)
var players: Array = []                 # tous les personnages (pantins + bots)
var roam_points: Array = []
var nav_map: RID

var _nodes := {}                        # identifiant réseau -> personnage
var _human_states := {}                 # identifiant -> dernier état reçu du client
var _respawns := {}                     # identifiant -> temps restant avant réapparition
## Scores par user_id (bots : "bot:<id>"), gardés même quand le joueur part :
## match.finished inclut les joueurs partis en cours de route, une seule fois
## chacun, même s'ils sont revenus avec un autre identifiant réseau.
var _results := {}
var _result_keys := {}                  # identifiant réseau -> clé dans _results
var _match_id := ""
var _started_at := ""
var _running := false
## Armes de chaque personnage, tenues par le serveur : identifiant -> {emplacement:
## {data, ammo, reload_end, next_shot, tokens, expires}}. Emplacements : 0 principale,
## 1 secondaire, 2 arme spéciale (bonus), Projectile.GRENADE_SLOT grenades. `tokens` =
## fins de validité (s) des impacts autorisés par les derniers tirs annoncés.
var _arsenal := {}

## Tolérances de l'arbitrage des tirs (les positions vues par le tireur ont un peu
## de retard sur celles du serveur).
const RANGE_MARGIN := 3.0               # mètres au-delà de la portée de l'arme
const HITBOX_MARGIN := 0.3              # mètres autour de la capsule de la cible
const LOS_MARGIN := 0.6                 # un mur à moins de ça du point touché ne bloque pas
const FIRE_INTERVAL_TOLERANCE := 0.7   # un tir peut arriver 30 % plus tôt (gigue réseau)
const RELOAD_TOLERANCE := 0.8           # un rechargement peut finir 20 % plus tôt
const HIT_WINDOW := 1.0                 # secondes pour signaler l'impact d'un tir annoncé
const PIERCE_BURST := 5                 # touches d'un seul tir (balles perforantes)
const AREA_HITS := 4                    # touches d'un coup de katana ou d'un tick de flammes
const CLOSE_RANGE_MARGIN := 1.0         # marge de portée du katana et des flammes (m)
const CLOSE_ARC_MARGIN := 25.0          # marge d'angle du katana et des flammes (degrés)
const MUZZLE_MARGIN := 3.0              # distance max entre le tireur et le départ d'un projectile
const BURN_TICK := 0.5                  # secondes entre deux dégâts de brûlure
const SPECIAL_SLOT := 2                 # arme spéciale ramassée (bonus)
const CHARGE_WINDOW := 0.8              # une charge de l'Oni touche pendant au plus ça (s)
const CHARGE_REACH := 3.5               # distance max d'un ennemi percuté (m)

## Brûlures en cours : identifiant -> {dps, until, shooter_id, weapon, pending}.
var _burns := {}
var _burn_timer := 0.0
var _projectiles := {}                  # identifiant -> Projectile (qui fait foi)
## Bonus de la map (socles, ramassages, réapparitions) : version qui fait foi.
var pickups: PickupDirector
var _charges := {}                      # tireur -> {start: début de sa dernière charge (s), hits: cibles touchées}
var _next_projectile_id := 1


func _ready() -> void:
	map = MapCatalog.scene_of(Net.settings.get("map", MapCatalog.DEFAULT_ID)).instantiate()
	add_child(map)
	nav_map = MatchRules.bake_navigation(self, map)
	roam_points = MatchRules.roam_points(map)
	for id in Net.players:
		_spawn(id)
	_match_id = Uuid.v4()
	_started_at = _now_iso()
	_running = true

	Net.arbiter = self
	add_to_group("projectile_host")
	pickups = PickupDirector.new()
	pickups.name = "Pickups"
	add_child(pickups)
	pickups.setup(map.pickup_points(), true)
	pickups.players_provider = func() -> Array: return players
	pickups.picked.connect(_on_pickup)
	pickups.state_changed.connect(func(pad_id: int, available: bool) -> void: Net.push_pickup.rpc(pad_id, available))
	for point in map.pickup_points():
		var p: Vector3 = point[1]
		roam_points.append(Vector3(p.x, 0, p.z))      # les bots passent par les bonus
	Net.special_given.connect(_on_special_given)
	Net.aura_started.connect(_on_aura_started)
	Net.remote_states.connect(_on_remote_states)
	Net.player_died.connect(_on_death)
	Net.player_respawned.connect(_on_respawn)
	Net.remote_spawned.connect(_on_joined)
	Net.remote_left.connect(_on_left)


func _exit_tree() -> void:
	Net.arbiter = null


func _process(delta: float) -> void:
	if not _running:
		return
	_publish_states()
	_update_burns(delta)
	for id in _respawns.keys():
		_respawns[id] -= delta
		if _respawns[id] <= 0.0:
			_respawns.erase(id)
			_respawn(id)
	Net.match_time_left -= delta
	if Net.match_time_left <= 0.0:
		_end_match()


# ---------------------------------------------------------------- Personnages

func _spawn(id: int) -> CharacterBody3D:
	var info: Dictionary = Net.players[id]
	var bot := Net.is_bot(id)
	var p: CharacterBody3D = PlayerScene.instantiate()
	p.class_data = load(info.class_id)
	p.loadout = Net.loadout_of(id)
	p.player_name = info.name
	p.is_local = false
	p.is_remote = not bot           # un humain suit l'état envoyé par son client
	p.peer_id = id
	if bot:
		var brain := BotBrain.new()
		brain.game = self
		brain.skill = randf_range(0.35, 0.75)
		p.brain = brain
	p.name = "Net_%d" % id
	add_child(p)
	# Un humain choisit son point d'apparition et le pantin s'y replace dès le
	# premier état reçu ; un bot apparaît loin des autres.
	p.global_transform = MatchRules.best_spawn(map, players, p)
	p.add_to_group("players")       # utilisé par les caméras et capteurs de la map
	p.start_spawn_protection()
	players.append(p)
	_nodes[id] = p
	_reset_arsenal(id)
	var user_id: String = "" if bot else info.get("user_id", "")
	var key := ("bot:%d" % id) if bot else (user_id if not user_id.is_empty() else "pair:%d" % id)
	_result_keys[id] = key
	if not _results.has(key):
		_results[key] = {"user_id": user_id, "bot": bot, "kills": 0, "deaths": 0}
	return p


func _remove_node(id: int) -> void:
	var node = _nodes.get(id)
	if is_instance_valid(node):
		players.erase(node)
		node.remove_from_group("players")
		node.queue_free()
	_nodes.erase(id)
	_human_states.erase(id)
	_respawns.erase(id)
	_arsenal.erase(id)
	_burns.erase(id)


## Un joueur arrive en cours de partie. S'il n'y a plus de place, un bot lui cède la sienne.
func _on_joined(id: int, _info: Dictionary) -> void:
	if _nodes.has(id) or not Net.players.has(id):
		return
	_spawn(id)
	if not Net.is_bot(id):
		Net.push_pickups.rpc_id(id, pickups.snapshot())     # état des bonus pour le nouveau
	if _nodes.size() > Net.max_players:
		var bots := _nodes.keys().filter(func(i): return Net.is_bot(i))
		if not bots.is_empty():
			bots.sort()
			Net.remove_player(bots[0])


## Un joueur est parti (ou un bot a été retiré). Ses scores restent dans _results.
func _on_left(id: int) -> void:
	_remove_node(id)
	if _running and Net.human_count() == 0:
		Net.log_line("SERVEUR : plus aucun joueur, fin de la partie")
		_end_match()


# ---------------------------------------------------------------- Réseau

## Diffuse l'état de tous les personnages : les bots simulés ici, et les
## humains tels que leur client les a envoyés (sans le lissage du pantin).
func _publish_states() -> void:
	var states := {}
	for id in _nodes:
		var node: CharacterBody3D = _nodes[id]
		if not is_instance_valid(node):
			continue
		if Net.is_bot(id):
			states[id] = node.net_state()
		elif _human_states.has(id):
			states[id] = _human_states[id]
	Net.publish_state(states)


func _on_remote_states(_sender_id: int, states: Dictionary) -> void:
	for id in states:
		var node = _nodes.get(id)
		if is_instance_valid(node) and node.is_remote:
			node.apply_net_state(states[id])
			_human_states[id] = states[id]


# ---------------------------------------------------------------- Arbitrage des tirs
# Appelé par Net (Net.arbiter = self) pour les tirs des clients et ceux des bots.

## Un tir annoncé (balle, coup de katana, tick de flammes) avec l'arme `slot`.
## Refusé si le chargeur est vide ou si le tir arrive plus vite que la cadence.
## Accepté : décompte une munition et autorise les impacts qui suivent.
func on_fire(shooter_id: int, slot: int) -> bool:
	var w := _weapon_state(shooter_id, slot)
	var shooter = _nodes.get(shooter_id)
	if w.is_empty() or not is_instance_valid(shooter) or not shooter.alive:
		return false
	var data: WeaponData = w.data
	var now := _now()
	if w.reload_end > 0.0:
		w.reload_end = 0.0      # le client a annulé son rechargement (changement d'arme)
	if not data.unlimited() and w.ammo <= 0:
		return false
	if now < w.next_shot:
		return false
	w.next_shot = now + FIRE_INTERVAL_TOLERANCE / data.fire_rate
	if not data.unlimited():
		w.ammo -= 1
	var hits := data.pellets
	if data.kind in [WeaponData.Kind.MELEE, WeaponData.Kind.FLAME]:
		hits = AREA_HITS
	elif shooter.class_data.ability == ClassData.Ability.PIERCE and data.is_hitscan():
		hits *= PIERCE_BURST
	for i in hits:
		w.tokens.append(now + HIT_WINDOW)
	return true


## Début d'un rechargement : le chargeur sera plein au bout du temps de l'arme.
func on_reload(shooter_id: int, slot: int) -> void:
	var w := _weapon_state(shooter_id, slot)
	if w.is_empty() or w.data.unlimited() or w.ammo >= w.data.mag_size or w.reload_end > 0.0:
		return
	w.reload_end = _now() + w.data.reload_time * RELOAD_TOLERANCE


## Un tireur signale un impact. Le serveur vérifie qu'il est plausible et qu'il suit
## un tir annoncé, choisit la zone touchée et calcule lui-même les dégâts à partir
## de la fiche de l'arme. `hit_offset` = point touché - position de la cible.
func resolve_hit(target_id: int, shooter_id: int, hit_offset: Vector3, weapon: String) -> void:
	var node = _nodes.get(target_id)
	var shooter = _nodes.get(shooter_id)
	if not is_instance_valid(node) or not is_instance_valid(shooter):
		return
	if not node.alive or node.is_protected() or not shooter.alive or node == shooter:
		return
	if weapon == shooter.CHARGE_NAME:
		_resolve_charge(node, shooter, target_id, shooter_id)
		return
	var slot := _slot_named(shooter_id, weapon)
	if slot < 0:
		Net.log_line("SERVEUR : tir de %d sur %d refusé (%s n'est pas dans sa classe)" % [shooter_id, target_id, weapon])
		return
	var weapon_data: WeaponData = _arsenal[shooter_id][slot].data
	var reason := _reject_reason(node, shooter, hit_offset, weapon_data)
	if not reason.is_empty():
		Net.log_line("SERVEUR : tir de %d sur %d refusé (%s)" % [shooter_id, target_id, reason])
		return
	if not _consume_hit(shooter_id, slot):
		return   # aucun tir annoncé pour cet impact : ignoré sans bruit

	var headshot := weapon_data.is_hitscan() and MatchRules.is_headshot(node, hit_offset)
	var amount := int(round(MatchRules.hit_damage(weapon_data, headshot) * shooter.damage_multiplier()))
	_damage(target_id, shooter_id, amount, weapon, headshot)
	if weapon_data.kind == WeaponData.Kind.MELEE and weapon_data.knockback > 0.0:
		var away: Vector3 = (node.global_position - shooter.global_position).normalized()
		_effect(target_id, "knockback", weapon_data.knockback, 0.0, away)
	if weapon_data.burn_time > 0.0 and node.alive:
		_burns[target_id] = {"dps": weapon_data.burn_dps, "until": _now() + weapon_data.burn_time,
			"shooter_id": shooter_id, "weapon": weapon, "pending": 0.0}


## Applique des dégâts (bouclier compris) et annonce vie, provenance et élimination.
func _damage(target_id: int, shooter_id: int, amount: int, weapon: String, headshot := false) -> void:
	var node = _nodes.get(target_id)
	if not is_instance_valid(node) or not node.alive or node.is_protected():
		return
	var damage := MatchRules.damage_taken(node, amount)
	# Armure (bonus) : elle prend les coups en premier.
	if node.armor > 0:
		var absorbed := mini(node.armor, damage)
		node.armor -= absorbed
		damage -= absorbed
		_effect(target_id, "armor", node.armor, 0.0)
	node.health = maxi(node.health - damage, 0)
	var shooter = _nodes.get(shooter_id)
	if node.brain and is_instance_valid(shooter) and shooter != node:
		node.brain.on_damaged(node, shooter)
	Net.push_health.rpc(target_id, node.health, node.class_data.max_health)
	Net.send_hit(target_id, shooter_id, damage, headshot)
	if node.health == 0:
		_burns.erase(target_id)
		Net.push_death.rpc(target_id, shooter_id, weapon, headshot)


## Effet subi : appliqué ici pour un bot (simulé par le serveur), envoyé au client
## pour un humain (il simule lui-même son déplacement).
func _effect(target_id: int, kind: String, value: float, duration: float, direction := Vector3.ZERO) -> void:
	var node = _nodes.get(target_id)
	if not is_instance_valid(node):
		return
	if Net.is_bot(target_id):
		node.apply_effect(kind, value, duration, direction, null)
	else:
		Net.send_effect(target_id, kind, value, duration, direction)


## Brûlures : dégâts réguliers tant qu'elles durent.
func _update_burns(delta: float) -> void:
	_burn_timer -= delta
	if _burn_timer > 0.0 or _burns.is_empty():
		return
	_burn_timer = BURN_TICK
	var now := _now()
	for id in _burns.keys():
		var burn: Dictionary = _burns[id]
		if now > burn.until:
			_burns.erase(id)
			continue
		burn.pending += burn.dps * BURN_TICK
		var amount := int(burn.pending)
		if amount > 0:
			burn.pending -= amount
			_damage(id, burn.shooter_id, amount, burn.weapon)


# ---------------------------------------------------------------- Projectiles

## Tir d'un projectile (roquette, lance-caca) ou lancer de grenade (slot 2) : le
## serveur vérifie munitions, cadence et point de départ, puis simule le projectile.
func on_fire_projectile(shooter_id: int, slot: int, origin: Vector3, velocity: Vector3) -> void:
	var shooter = _nodes.get(shooter_id)
	var w := _weapon_state(shooter_id, slot)
	if not is_instance_valid(shooter) or w.is_empty():
		return
	var data: WeaponData = w.data
	if not data.kind in [WeaponData.Kind.PROJECTILE, WeaponData.Kind.THROWN]:
		return
	if origin.distance_to(shooter.chest_position()) > MUZZLE_MARGIN:
		Net.log_line("SERVEUR : projectile de %d refusé (départ trop loin du tireur)" % shooter_id)
		return
	if not on_fire(shooter_id, slot):
		return
	var speed := minf(velocity.length(), data.projectile_speed * 1.1)
	launch_projectile(data, shooter, origin, velocity.normalized() * speed)


## Crée le projectile qui fait foi et l'annonce aux clients (qui l'affichent).
func launch_projectile(data: WeaponData, shooter: Node, origin: Vector3, velocity: Vector3) -> void:
	var projectile := Projectile.new()
	projectile.id = _next_projectile_id
	_next_projectile_id += 1
	projectile.setup(data, shooter, origin, velocity, true)
	projectile.exploded.connect(_on_projectile_exploded)
	add_child(projectile)
	_projectiles[projectile.id] = projectile
	Net.push_projectile.rpc(projectile.id, data.id, origin, velocity, projectile.shooter_id)


func _on_projectile_exploded(projectile: Projectile, position: Vector3, direct_target: Node) -> void:
	_projectiles.erase(projectile.id)
	var shooter: Node = projectile.shooter if is_instance_valid(projectile.shooter) else null
	_explode(position, projectile.data, shooter, projectile.shooter_id, direct_target)
	Net.push_explosion.rpc(projectile.id, position, projectile.data.id)


## Explosion qui fait foi : dégâts de zone (Surcharge comprise), recul et effets.
func _explode(position: Vector3, data: WeaponData, shooter: Node, shooter_id: int, direct_target: Node) -> void:
	var multiplier: float = shooter.damage_multiplier() if shooter and shooter.has_method("damage_multiplier") else 1.0
	for victim in MatchRules.explosion_victims(get_world_3d(), position, data, shooter, direct_target):
		var node: Node = victim.node
		var target_id: int = node.peer_id if "peer_id" in node else 0
		if target_id == 0 or not _nodes.has(target_id):
			continue
		_damage(target_id, shooter_id, int(round(victim.damage * multiplier)), data.display_name)
		if data.knockback > 0.0:
			_effect(target_id, "knockback", data.knockback, 0.0, victim.direction)
		if data.slow_time > 0.0:
			_effect(target_id, "slow", data.slow_factor, data.slow_time)
		if data.splat_time > 0.0:
			_effect(target_id, "splat", 1.0, data.splat_time)



## Charge de l'Oni : seulement pour un Oni, à courte distance, dans une fenêtre de
## CHARGE_WINDOW secondes, et pas plus souvent que sa capacité ne se recharge.
func _resolve_charge(node: Node3D, shooter: Node3D, target_id: int, shooter_id: int) -> void:
	if shooter.class_data.ability != ClassData.Ability.CHARGE:
		return
	if shooter.global_position.distance_to(node.global_position) > CHARGE_REACH:
		return
	var now := _now()
	var charge: Dictionary = _charges.get(shooter_id, {"start": -1000.0, "hits": []})
	if now - charge.start > CHARGE_WINDOW:
		if now - charge.start < shooter.class_data.ability_cooldown * 0.7:
			Net.log_line("SERVEUR : charge de %d refusée (capacité pas encore rechargée)" % shooter_id)
			return
		charge = {"start": now, "hits": []}
		_charges[shooter_id] = charge
	if target_id in charge.hits:
		return      # une seule fois par cible et par charge
	charge.hits.append(target_id)
	_damage(target_id, shooter_id, int(round(shooter.CHARGE_DAMAGE * shooter.damage_multiplier())), shooter.CHARGE_NAME)
	var push: Vector3 = (node.global_position - shooter.global_position)
	push.y = 0.0
	_effect(target_id, "knockback", shooter.CHARGE_KNOCKBACK, 0.0, (push.normalized() + Vector3.UP * 0.4).normalized())


## Raison du refus d'un impact, ou "" s'il est accepté.
func _reject_reason(node: Node3D, shooter: Node3D, hit_offset: Vector3, weapon_data: WeaponData) -> String:
	if not weapon_data.kind in [WeaponData.Kind.HITSCAN, WeaponData.Kind.MELEE, WeaponData.Kind.FLAME]:
		return "arme sans impact direct"     # projectiles : le serveur les simule lui-même
	var close := weapon_data.kind in [WeaponData.Kind.MELEE, WeaponData.Kind.FLAME]
	var margin := CLOSE_RANGE_MARGIN if close else RANGE_MARGIN
	if shooter.global_position.distance_to(node.global_position) > weapon_data.max_range + margin:
		return "hors de portée"
	if close:
		# Katana et flammes : la cible doit être devant le tireur.
		var to_target := node.global_position - shooter.global_position
		to_target.y = 0.0
		var forward := -shooter.global_basis.z
		forward.y = 0.0
		if to_target.length() > 0.5 and rad_to_deg(to_target.angle_to(forward)) > weapon_data.arc_deg / 2.0 + CLOSE_ARC_MARGIN:
			return "cible derrière le tireur"
	var height := MatchRules.body_height(node)
	var radius: float = (node.collision.shape as CapsuleShape3D).radius
	if Vector2(hit_offset.x, hit_offset.z).length() > radius + HITBOX_MARGIN \
			or hit_offset.y < -HITBOX_MARGIN or hit_offset.y > height + HITBOX_MARGIN:
		return "point d'impact hors de la cible"
	# Ligne de vue : des yeux du tireur au point touché, seul le décor peut bloquer.
	var eye := shooter.global_position + Vector3.UP * (MatchRules.body_height(shooter) - 0.2)
	var impact := node.global_position + hit_offset
	var query := PhysicsRayQueryParameters3D.create(eye, impact)
	var exclude: Array[RID] = []
	for p in players:
		if is_instance_valid(p):
			exclude.append(p.get_rid())
	query.exclude = exclude
	var wall := get_world_3d().direct_space_state.intersect_ray(query)
	if not wall.is_empty() and (wall.position as Vector3).distance_to(impact) > LOS_MARGIN:
		return "mur entre le tireur et la cible"
	return ""


## Armes d'un personnage remises à neuf (apparition, réapparition, changement de classe).
func _reset_arsenal(id: int) -> void:
	var node = _nodes.get(id)
	if not is_instance_valid(node):
		return
	var slots := {}
	for i in mini(node.weapons.size(), 2):
		slots[i] = _weapon_entry(node.weapons[i].data)
	slots[Projectile.GRENADE_SLOT] = _weapon_entry(WeaponCatalog.GRENADE, WeaponCatalog.GRENADES_PER_LIFE)
	_arsenal[id] = slots


static func _weapon_entry(data: WeaponData, ammo := -1) -> Dictionary:
	var expires := INF if data.special_duration <= 0.0 else _now() + data.special_duration + 1.0
	return {"data": data, "ammo": data.mag_size if ammo < 0 else ammo, "reload_end": 0.0, "next_shot": 0.0,
		"tokens": [], "expires": expires}


## État serveur de l'arme `slot` d'un personnage ({} si inconnue). Termine au passage
## un rechargement arrivé à son terme.
func _weapon_state(id: int, slot: int) -> Dictionary:
	var slots: Dictionary = _arsenal.get(id, {})
	if not slots.has(slot):
		return {}
	var w: Dictionary = slots[slot]
	if _now() > w.expires:
		slots.erase(slot)       # arme spéciale arrivée au bout de sa durée
		return {}
	if w.reload_end > 0.0 and _now() >= w.reload_end:
		w.ammo = w.data.mag_size
		w.reload_end = 0.0
	return w


## Emplacement de l'arme `weapon` (nom affiché) dans la classe du tireur, -1 si absente.
func _slot_named(id: int, weapon: String) -> int:
	var slots: Dictionary = _arsenal.get(id, {})
	for slot in slots:
		if slots[slot].data.display_name == weapon:
			return slot
	return -1


## Utilise une touche autorisée par un tir récent de l'arme `slot`.
func _consume_hit(id: int, slot: int) -> bool:
	var w := _weapon_state(id, slot)
	if w.is_empty():
		return false
	var now := _now()
	var tokens: Array = w.tokens.filter(func(t): return t >= now)
	w.tokens = tokens
	if tokens.is_empty():
		return false
	tokens.pop_front()
	return true


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Élimination (annoncée par push_death, qui s'exécute aussi ici).
func _on_death(victim_id: int, killer_id: int, _weapon: String, _headshot: bool) -> void:
	var victim = _nodes.get(victim_id)
	if is_instance_valid(victim):
		victim.net_die()
	var victim_key: String = _result_keys.get(victim_id, "")
	var killer_key: String = _result_keys.get(killer_id, "")
	if _results.has(victim_key):
		_results[victim_key].deaths += 1
	if _results.has(killer_key) and killer_id != victim_id:
		_results[killer_key].kills += 1
	_respawns[victim_id] = MatchRules.RESPAWN_DELAY


## Réapparition décidée ici, avec le spécialiste et la classe choisis par le joueur
## (Net.set_loadout).
func _respawn(id: int) -> void:
	var node = _nodes.get(id)
	if not is_instance_valid(node):
		return
	var t := MatchRules.best_spawn(map, players, node)
	Net.push_respawn.rpc(id, t.origin, t.basis.get_euler().y, Net.class_path_of(id), Net.loadout_of(id))


## Réapparition (annoncée par push_respawn, qui s'exécute aussi ici).
func _on_respawn(id: int, position: Vector3, yaw: float, class_id: String, loadout: Dictionary) -> void:
	var node = _nodes.get(id)
	if not is_instance_valid(node):
		return
	if MatchRules.needs_rebuild(node, class_id, loadout):
		_remove_node(id)
		node = _spawn(id)
	else:
		_reset_arsenal(id)
	node.respawn(position, yaw)
	node.teleport(position, yaw)
	if node.brain:
		node.brain.reset()


# ---------------------------------------------------------------- Fin de partie

func _end_match() -> void:
	if not _running:
		return
	_running = false
	Net.match_time_left = 0.0
	link.match_finished(_match_result())
	Net.push_match_over.rpc(Net.sorted_players())


## Résultat au format de l'événement match.finished (voir BackendLink.match_finished).
## Le classement compte les bots, mais seuls les joueurs humains sont envoyés.
func _match_result() -> Dictionary:
	var rows := []
	for key in _results:
		rows.append(_results[key].duplicate())
	MatchRules.rank(rows)
	var results := []
	for row in rows:
		if not row.bot and not row.user_id.is_empty():
			results.append({"user_id": row.user_id, "kills": row.kills, "deaths": row.deaths, "placement": row.placement})
	return {
		"match_id": _match_id,
		"server_id": link.server_id,
		"party_id": link.party_id,
		"map": map.map_id(),
		"started_at": _started_at,
		"ended_at": _now_iso(),
		"players": results,
	}


static func _now_iso() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"


# ---------------------------------------------------------------- Bonus de la map

## Un personnage a ramassé un bonus : le serveur applique l'effet et prévient le joueur.
func _on_pickup(_pad_id: int, kind: int, node: Node) -> void:
	var id: int = node.peer_id
	if not _nodes.has(id):
		return
	match kind:
		Pickups.Kind.HEAL:
			node.health = mini(node.health + Pickups.HEAL_AMOUNT, node.class_data.max_health)
			Net.push_health.rpc(id, node.health, node.class_data.max_health)
		Pickups.Kind.ARMOR:
			node.armor = mini(node.armor + Pickups.ARMOR_AMOUNT, Pickups.ARMOR_MAX)
			_effect(id, "armor", node.armor, 0.0)
		Pickups.Kind.DOUBLE_JUMP:
			_effect(id, "double_jump", 0.0, Pickups.DOUBLE_JUMP_TIME)
		Pickups.Kind.SPEED:
			_effect(id, "speed", Pickups.SPEED_BONUS, Pickups.SPEED_TIME)
		Pickups.Kind.SUPER:
			var power := Pickups.random_super()
			node.super_power = power
			_effect(id, "super", power, 0.0)
		_:
			var data := WeaponCatalog.find(Pickups.weapon_of(kind))
			if data:
				_arsenal[id][SPECIAL_SLOT] = _weapon_entry(data)
				Net.push_special.rpc(id, data.id)      # tout le monde affiche l'arme
	_effect(id, "picked", kind, 0.0)


## Arme spéciale annoncée (push_special s'exécute aussi ici) : le personnage du
## serveur la reçoit aussi (bots : ils tirent avec ; humains : arsenal cohérent).
func _on_special_given(id: int, weapon_id: String) -> void:
	var node = _nodes.get(id)
	var data := WeaponCatalog.find(weapon_id)
	if is_instance_valid(node) and data:
		node.give_special(data)


## Effet de super-pouvoir visible (push_aura s'exécute aussi ici).
func _on_aura_started(id: int, kind: int, duration: float) -> void:
	var node = _nodes.get(id)
	if is_instance_valid(node):
		node.apply_aura(kind, duration)


## Client : « je déclenche mon super-pouvoir » (Net.use_super).
func activate_super_of(id: int) -> void:
	var node = _nodes.get(id)
	if is_instance_valid(node):
		activate_super(node)


## Déclenche le super-pouvoir en réserve d'un personnage (humain ou bot).
func activate_super(node: Node) -> void:
	var id: int = node.peer_id
	var power: int = node.super_power
	if power < 0 or not node.alive or not _nodes.has(id):
		return
	node.super_power = -1
	_effect(id, "super", -1, 0.0)
	match power:
		Pickups.Super.OVERLOAD:
			Net.push_aura.rpc(id, power, Pickups.OVERLOAD_TIME)
		Pickups.Super.INVISIBILITY:
			Net.push_aura.rpc(id, power, Pickups.INVISIBILITY_TIME)
		Pickups.Super.SHOCKWAVE:
			var center: Vector3 = node.chest_position()
			_explode(center, Pickups.SHOCKWAVE, node, id, null)
			Net.push_explosion.rpc(0, center, Pickups.SHOCKWAVE.id)
