# Arena TPS

Jeu de tir multijoueur en 3D, en vue à la troisième personne, en mode chacun pour soi (8 joueurs par partie). Le projet sert de support à la mise en œuvre d'une **architecture micro-services**.

Projet réalisé en binôme par **Julien** (client de jeu) et **Elian** (micro-services et bases de données) — Architecture SI, M2, CFA INSTA.

## Organisation du dépôt

```
arena-tps/
├── front/       Client du jeu (Godot 4.7.2) — responsable : Julien
├── services/    Micro-services et bases de données — responsable : Elian
├── tools/       Scripts de génération des ressources (textures, masques, animations)
└── README.md
```

## Lancer le jeu

1. Installer **Godot 4.7.2** (version imposée pour toute l'équipe).
2. Dans le gestionnaire de projets de Godot, cliquer sur **Importer** et sélectionner `front/project.godot`. Le premier import des modèles et textures prend quelques dizaines de secondes.
3. Lancer avec **F5**.

### Parcours

| Écran | Contenu |
|---|---|
| Connexion / inscription | Connexion, création de compte, vérification de l'e-mail par code à 6 chiffres, mot de passe oublié |
| Menu principal | Profil (niveau, XP), groupe jusqu'à 8 joueurs, créer / rejoindre un serveur, entraînement, liste d'amis avec statuts |
| Serveurs publics | Liste des parties en cours (joueurs, ping, mode, map) |
| Statistiques | Statistiques du joueur, classement mondial ou entre amis |
| Classes | Choix de la classe avec aperçu 3D animé |
| Partie | Match à mort de 3 minutes contre des bots, tableau des scores, écran de fin |

Le **back-end est simulé** (`front/scripts/backend/backend.gd`) : la connexion accepte tout, les amis, serveurs et classements sont factices, et les statistiques des parties jouées sont enregistrées localement. Les fonctions reprennent les routes du BFF prévues dans l'architecture ; il suffira de remplacer leur contenu par des appels HTTP.

### Commandes

| Touche | Action |
|---|---|
| Souris | Orienter la caméra |
| Clic gauche | Tirer |
| Clic droit | Viser (zoom, meilleure précision) |
| Z Q S D ou flèches | Se déplacer |
| Maj | Courir |
| Espace | Sauter |
| Ctrl ou C (maintenir) | S'accroupir : hitbox plus basse, tir plus précis, déplacement plus lent |
| R | Recharger |
| E | Capacité de la classe |
| Tab (maintenir) | Tableau des scores |
| Échap | Menu pause (la partie continue) |
| F9 | S'infliger 25 dégâts (test) |

### Menu pause

**Échap** ouvre le menu pause du joueur local. La partie **ne s'arrête pas** : les bots (et plus tard les autres joueurs) continuent, et notre personnage reste dans l'arène, immobile et vulnérable. Le menu propose :

- **Reprendre** ;
- **Changer de classe** : la classe choisie est utilisée à la prochaine apparition, le score de la partie est conservé ;
- **Paramètres** : volume général, effets, interface, sensibilité de la souris, inversion de l'axe vertical (enregistrés dans `user://parametres.cfg`, autoload `Settings`) ;
- **Quitter la partie** (avec confirmation).

### Protection d'apparition

Pendant **3 secondes** après chaque apparition, le joueur ne prend aucun dégât (bulle lumineuse visible par tous, compte à rebours sous le réticule). Les balles sont déviées et les bots ne le visent pas. La protection s'arrête dès que le joueur tire. Durée réglable dans `player.gd` (`SPAWN_PROTECTION_TIME`).

### Sons

Effets sonores générés par `tools/generate_sounds.py` (tirs des 3 armes, impacts, élimination, rechargement, capacités, apparition, interface). Les sons des autres joueurs sont spatialisés. Lecture via l'autoload `Sfx`, sur les bus audio `Effets` et `Interface`.

## Modes de jeu

- **Match à mort** (« Créer un serveur » ou « Rejoindre un serveur ») : le joueur affronte des bots pendant 3 minutes. Fil des éliminations, séries, meneur, tableau des scores et classement final. Le résultat est envoyé au back simulé (équivalent de l'événement `match.finished`).
- **Entraînement** : le joueur seul avec des mannequins-robots (dont certains accroupis), sans limite de temps.

### Bots

`front/scripts/bots/bot_brain.gd` remplit les mêmes commandes que le clavier et la souris (`PlayerCommands`) : le joueur est ainsi découpé en **entrées** et **simulation**, la séparation dont le futur serveur de jeu autoritaire aura besoin. Les bots :

- repèrent les ennemis (champ de vision, murs bloquants) et réagissent quand on leur tire dessus ;
- visent avec un temps de réaction et une erreur qui diminue, tirent en rafales ou au coup par coup ;
- se déplacent grâce à un maillage de navigation calculé au chargement à partir des collisions de la map ;
- utilisent leur capacité (bouclier, dash, tir perforant).

## Classes et armes

Les classes et les armes sont décrites par des fichiers de données modifiables dans l'inspecteur de Godot :

- `front/data/classes/*.tres` : points de vie, vitesse, arme, capacité, apparence ;
- `front/data/weapons/*.tres` : dégâts, cadence, chargeur, dispersion, zoom, modèle 3D.

| Classe | PV | Arme | Capacité |
|---|---|---|---|
| Tank | 150 | Fusil à pompe (9 plombs) | Bouclier : -70 % de dégâts pendant 3 s |
| Assassin | 80 | Mitraillette | Dash : bond rapide dans la direction du déplacement |
| Tireur | 100 | Fusil de précision (200 m) | Tir perforant : les balles traversent les ennemis pendant 6 s |

## Personnages

Personnages humains au style cyberpunk (`front/scripts/character/`) :

| Fichier | Rôle |
|---|---|
| `human_rig.gd` | Corps humain importé, animations (repos, marche, jogging, sprint, accroupi, saut, mort) mélangées selon la vitesse |
| `aim_ik_modifier.gd` | Après l'animation : bas du corps tourné vers le déplacement (pas chassés, marche arrière), buste vers la visée, mains posées sur l'arme (cinématique inverse) |
| `human_designs.gd` | Chara design par classe : corps, coupe et couleur de cheveux, combinaison, équipement accroché aux os |
| `cyber_suit.gdshader` (dans `front/shaders/`) | Combinaison colorée par classe avec liserés néon, visage conservé |
| `character_rig.gd`, `character_designs.gd` | Robots procéduraux (mannequins d'entraînement) et modèles 3D des armes |
| `character_preview.gd` | Aperçus 3D animés des menus |

L'animation est pilotée par l'état du personnage (vitesse, au sol, accroupi, angle de visée) : en multijoueur, il suffira de transmettre cet état pour animer les autres joueurs.

## La map « Arena »

Arène de 120 x 120 m définie dans `front/scripts/maps/arena_map.gd` et chargée par `front/scenes/maps/arena.tscn` (scène séparée du jeu, réutilisable par le futur serveur).

| Zone | Contenu |
|---|---|
| Centre | Tour à 3 m, 4 rampes, auvent, marquage « CFA INSTA ARENA » |
| Nord-ouest | Parc à conteneurs, portique de levage |
| Nord-est | Entrepôt « LAB IoT » : bras robotiques 6 axes, tapis roulant, mezzanine, écran de supervision |
| Sud-ouest | Deux tours à 5 m reliées par une passerelle, panneau CFA INSTA |
| Sud-est | Place : pergola, arbres, fontaine, kiosque, station météo |
| Avenues | Deux axes qui se croisent, barrières, lampadaires |

Décor connecté (`front/scripts/maps/props/`) : caméras de surveillance qui suivent le joueur le plus proche, capteurs (température, humidité, CO2, bruit, lumière, présence) avec valeurs en direct, drones en patrouille, tableau de bord IoT, station météo, enseignes et bannières CFA INSTA.

Les éléments de la map sont des listes et fonctions dans le script : après une modification, cliquer sur **Reconstruire la map** dans l'inspecteur de la scène `arena.tscn` (la map et ses animations sont visibles dans l'éditeur).

## Outils (`tools/`)

| Script | Rôle |
|---|---|
| `generate_textures.py` | Textures tuilables de la map (béton, métal, conteneurs…) générées par bruit mathématique |
| `generate_suit_masks.py` | Masques des combinaisons calculés à partir des poids de skinning des modèles |
| `extract_animations.gd` | Extraction d'une bibliothèque d'animations compacte depuis le pack d'animations |
| `generate_sounds.py` | Effets sonores du jeu, calculés par synthèse (aucun son externe) |

Dépendances Python : `numpy`, `pillow`.

## Crédits et licences des ressources

- Personnages et animations : **Quaternius** — Universal Base Characters, Universal Animation Library, Modular Character Outfits — licence **CC0** (domaine public). Textes de licence dans `front/assets/characters/quaternius/licenses/`.
- Polices : **Orbitron** et **Rajdhani** (Google Fonts) — licence **SIL Open Font License** (fichiers OFL dans `front/assets/fonts/`).
- Textures de la map, effets sonores, équipements, robots, armes et décors IoT : générés par le projet.

## Règles de travail

1. **Une seule version de Godot : 4.7.2.** Ouvrir le projet avec une autre version le convertit et provoque des conflits.
2. **Ne jamais versionner le dossier `.godot/`** : c'est un cache régénéré automatiquement (déjà exclu par le `.gitignore`).
3. **Versionner les fichiers `.uid` et `.import`** : Godot s'en sert pour retrouver les ressources et leurs réglages d'import.
4. **Éviter de modifier la même scène `.tscn` à deux en même temps** : ces fichiers fusionnent mal.
5. **Ne jamais committer de secrets** (mots de passe, clés) : utiliser un fichier `.env`, exclu du dépôt, et fournir un `.env.example`.
6. **Travailler sur des branches** et fusionner dans `main` uniquement du code fonctionnel.

## Convention de branches et de commits

- `main` : version stable, toujours fonctionnelle
- `front/<sujet>` : travail sur le client (ex. `front/tir`)
- `services/<sujet>` : travail sur le back (ex. `services/auth`)

Messages de commit courts, au présent, préfixés par la zone concernée :

```
front: ajoute le tir par raycast
services: crée le service d'authentification
docs: complète le README
```

## État d'avancement

- [x] Écrans de connexion, inscription, vérification par code, mot de passe oublié
- [x] Menu principal multijoueur (profil, groupe, amis, serveurs, statistiques) sur back-end simulé
- [x] Personnages humains cyberpunk animés (3 classes) et mannequins-robots
- [x] Déplacement, course, saut, accroupissement, caméra à la troisième personne
- [x] Tir, munitions, classes, armes et capacités
- [x] Map « Arena » 120 x 120 m texturée, décor CFA INSTA et IoT animé
- [x] Match à mort contre des bots, tableau des scores, écran de fin
- [x] Menu pause local (changement de classe, son, sensibilité), protection d'apparition, effets sonores
- [ ] Connexion au vrai back-end (BFF)
- [ ] Serveur de jeu dédié (Godot headless) et joueurs distants
- [ ] Micro-services et bases de données
