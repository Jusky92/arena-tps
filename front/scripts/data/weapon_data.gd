class_name WeaponData
extends Resource
## Fiche technique d'une arme. Chaque arme du jeu est un fichier .tres
## (dans data/weapons/) qu'on peut modifier directement dans l'inspecteur Godot.

enum Model { SHOTGUN, SMG, SNIPER }

@export var display_name: String = "Arme"
@export var model: Model = Model.SMG          ## apparence 3D de l'arme

@export_group("Dégâts")
@export var damage: int = 20                  ## dégâts par projectile
@export var pellets: int = 1                  ## nombre de projectiles par tir (fusil à pompe > 1)
@export var max_range: float = 100.0          ## portée en mètres

@export_group("Cadence et munitions")
@export var fire_rate: float = 8.0            ## tirs par seconde
@export var automatic: bool = true            ## true = on maintient le clic, false = un clic par tir
@export var mag_size: int = 12
@export var reload_time: float = 1.5          ## secondes

@export_group("Précision")
@export var spread_deg: float = 1.0           ## dispersion en tirant à la hanche
@export var aim_spread_deg: float = 0.3       ## dispersion en visant (clic droit)
@export var aim_fov: float = 55.0             ## champ de vision en visant (plus petit = zoom)
@export var recoil_deg: float = 0.6           ## recul de la caméra à chaque tir

@export_group("Visuel")
@export var tracer_color: Color = Color(1.0, 0.9, 0.4)
