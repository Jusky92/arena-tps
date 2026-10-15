class_name WeaponData
extends Resource
## Fiche technique d'une arme. Chaque arme du jeu est un fichier .tres
## (dans data/weapons/) qu'on peut modifier directement dans l'inspecteur Godot.
## La liste des armes jouables est dans WeaponCatalog (scripts/data/weapon_catalog.gd).

## Apparence 3D (modèle procédural, voir CharacterDesigns.build_weapon).
enum Model { SHOTGUN, SMG, SNIPER, ROCKET, FLAMER, LASER, KATANA, POOP, GRENADE }
## Emplacement dans une classe : arme principale, secondaire, ou équipement (grenade).
enum Slot { PRIMARY, SECONDARY, EQUIPMENT }
## Fonctionnement du tir.
##   HITSCAN    : balle instantanée (lancer de rayon)
##   PROJECTILE : projectile simulé par le serveur (roquette, lance-caca)
##   MELEE      : corps à corps dans un arc devant le joueur (katana)
##   FLAME      : cône de flammes à courte portée, brûlure (lance-flammes)
##   THROWN     : objet lancé qui rebondit puis explose (grenade)
enum Kind { HITSCAN, PROJECTILE, MELEE, FLAME, THROWN }

## Identifiant stable (classes sauvegardées, réseau). Ne pas le changer une fois publié.
@export var id: String = ""
@export var display_name: String = "Arme"
@export var model: Model = Model.SMG          ## apparence 3D de l'arme
@export var slot: Slot = Slot.PRIMARY
@export var kind: Kind = Kind.HITSCAN

@export_group("Dégâts")
@export var damage: int = 20                  ## dégâts par projectile / plomb / coup
@export var pellets: int = 1                  ## nombre de projectiles par tir (fusil à pompe > 1)
@export var max_range: float = 100.0          ## portée en mètres
@export var headshot_multiplier: float = 2.0  ## dégâts multipliés quand la balle touche la tête

@export_group("Cadence et munitions")
@export var fire_rate: float = 8.0            ## tirs par seconde (ticks par seconde pour les flammes)
@export var automatic: bool = true            ## true = on maintient le clic, false = un clic par tir
@export var mag_size: int = 12                ## 0 = illimité (katana)
@export var reload_time: float = 1.5          ## secondes

@export_group("Précision")
@export var spread_deg: float = 1.0           ## dispersion en tirant à la hanche
@export var aim_spread_deg: float = 0.3       ## dispersion en visant (clic droit)
@export var aim_fov: float = 55.0             ## champ de vision en visant (plus petit = zoom)
@export var recoil_deg: float = 0.6           ## recul de la caméra à chaque tir

@export_group("Projectile et explosion")
@export var projectile_speed: float = 30.0    ## m/s au départ
@export var projectile_gravity: float = 0.0   ## m/s² (0 = ligne droite)
@export var fuse_time: float = 0.0            ## > 0 : explose après ce délai (grenade), sinon au contact
@export var bounce: float = 0.0               ## rebond (0 = aucun, 1 = parfait)
@export var splash_radius: float = 0.0        ## rayon de l'explosion (0 = pas d'explosion)
@export var splash_damage: int = 0            ## dégâts au centre de l'explosion (la cible touchée en plein prend `damage`)
@export var splash_min_damage: int = 0        ## dégâts au bord de l'explosion
@export var self_damage_factor: float = 0.0   ## part des dégâts de zone subie par le tireur
@export var knockback: float = 0.0            ## poussée donnée par l'explosion ou le coup (m/s)

@export_group("Corps à corps et flammes")
@export var arc_deg: float = 70.0             ## largeur de l'arc (katana) ou du cône (flammes)

@export_group("Effets sur la cible")
@export var slow_factor: float = 0.0          ## 0.4 = 40 % plus lent
@export var slow_time: float = 0.0            ## secondes
@export var splat_time: float = 0.0           ## secondes de tache à l'écran (lance-caca)
@export var burn_dps: float = 0.0             ## dégâts par seconde de brûlure
@export var burn_time: float = 0.0            ## secondes de brûlure

@export_group("Visuel")
@export var tracer_color: Color = Color(1.0, 0.9, 0.4)


## true si l'arme tire des balles instantanées (traçantes, perforation de l'Archer).
func is_hitscan() -> bool:
	return kind == Kind.HITSCAN


## true si l'arme n'a pas de chargeur (katana).
func unlimited() -> bool:
	return mag_size <= 0
