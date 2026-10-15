class_name ClassData
extends Resource
## Fiche d'un spécialiste (Samouraï, Shinobi, Archer, Oni) : design et capacité.
## (Le script garde le nom ClassData pour ne pas casser les .tres existants ; dans
## le jeu, « classe » désigne l'équipement, voir WeaponCatalog.)
## Chaque spécialiste est un fichier .tres dans data/classes/.
## Ajouter un spécialiste = dupliquer un .tres, changer les valeurs, l'ajouter à GameState.CLASSES.

enum Ability { SHIELD, DASH, PIERCE, CHARGE }

@export var display_name: String = "Classe"
@export_multiline var description: String = ""
@export var color: Color = Color(0.25, 0.6, 1.0)
## Apparence 3D (voir scripts/character/character_designs.gd) : tank, assassin, tireur.
@export var character_design: String = "tireur"

@export_group("Statistiques")
@export var max_health: int = 100
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var jump_velocity: float = 5.0

@export_group("Arme")
@export var weapon: WeaponData

@export_group("Capacité (touche E)")
@export var ability: Ability = Ability.SHIELD
@export var ability_name: String = "Capacité"
@export_multiline var ability_description: String = ""
@export var ability_cooldown: float = 8.0     ## secondes avant de pouvoir la réutiliser
@export var ability_duration: float = 3.0     ## durée de l'effet (bouclier, dash…)
@export var ability_strength: float = 0.3     ## bouclier : % de dégâts reçus / dash : vitesse
