# Arena TPS

Jeu de tir multijoueur en 3D, en vue à la troisième personne, conçu pour que toute la classe puisse jouer simultanément. Le projet sert de support à la mise en œuvre d'une **architecture micro-services**.

Projet réalisé en binôme par **Julien** et **Elian**.

## Concept

- Arène 3D, chacun pour soi
- Parties de 3 minutes, réapparition illimitée à une position aléatoire
- Le joueur ayant réalisé le plus d'éliminations remporte la partie
- Évolution prévue : classes de personnages (Tank, Assassin, Tireur) dotées de statistiques et d'une capacité propres

## Organisation du dépôt

```
arena-tps/
├── front/       Client du jeu (Godot 4.7.2) — responsable : Julien
├── services/    Micro-services et bases de données — responsable : Elian
└── README.md
```

## Contraintes du projet

- Architecture micro-services
- Au moins 3 micro-services
- Au moins 2 bases de données
- 1 front (le client du jeu)

## Lancer le front

1. Installer **Godot 4.7.2** (version imposée pour toute l'équipe, voir ci-dessous).
2. Dans le gestionnaire de projets de Godot, cliquer sur **Importer** et sélectionner `front/project.godot`.
3. Lancer le projet avec **F5**.

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
| Échap | Revenir au menu |
| F9 | S'infliger 25 dégâts (test, à retirer) |

## Classes et armes

Les classes et les armes sont décrites par des fichiers de données modifiables dans l'inspecteur de Godot :

- `front/data/classes/*.tres` : points de vie, vitesse, arme, capacité ;
- `front/data/weapons/*.tres` : dégâts, cadence, chargeur, dispersion, zoom.

| Classe | PV | Arme | Capacité |
|---|---|---|---|
| Tank | 150 | Fusil à pompe (9 plombs) | Bouclier : -70 % de dégâts pendant 3 s |
| Assassin | 80 | Mitraillette | Dash : bond rapide dans la direction du déplacement |
| Tireur | 100 | Fusil de précision | Tir perforant : les balles traversent les ennemis pendant 6 s |

Pour ajouter une classe : dupliquer un fichier `.tres` de classe, ajuster ses valeurs, puis l'ajouter à la liste `CLASSES` de `front/scripts/game_state.gd`.

## Personnages

Chaque classe a son propre personnage en 3D, construit et animé par code (`front/scripts/character/`) :

| Fichier | Rôle |
|---|---|
| `part_mesh.gd` | Génère les pièces 3D (formes arrondies paramétrables) |
| `character_designs.gd` | Chara design de chaque classe : palette de couleurs, pièces d'armure, modèles d'armes |
| `character_rig.gd` | Squelette et animation procédurale : marche/course dans toutes les directions, saut, atterrissage, accroupi, visée, recul, mort |
| `character_preview.gd` | Aperçu 3D animé de l'écran de choix de classe |

L'animation est calculée à partir de l'état du personnage (vitesse, au sol, accroupi, angle de visée) : en multijoueur, il suffira de transmettre cet état pour animer les autres joueurs.

## La map « Arena »

Arène de 120 x 120 m prévue pour 8 joueurs, définie dans `front/scripts/maps/arena_map.gd` et chargée par `front/scenes/maps/arena.tscn` (scène séparée du jeu, réutilisable par le futur serveur).

| Zone | Contenu |
|---|---|
| Centre | Tour à 3 m, 4 rampes, auvent |
| Nord-ouest | Parc à conteneurs, portique de levage |
| Nord-est | Entrepôt avec mezzanine à 3,5 m |
| Sud-ouest | Deux tours à 5 m reliées par une passerelle |
| Sud-est | Place : pergola, arbres, fontaine, kiosque |
| Avenues | Deux axes qui se croisent, avec barrières et lampadaires |

- Les éléments (conteneurs, barrières, caisses, arbres, points d'apparition) sont des listes en haut du script : les modifier puis cliquer sur **Reconstruire la map** dans l'inspecteur de la scène `arena.tscn`.
- Les textures sont générées par `tools/generate_textures.py` (Python, numpy, pillow) : aucune ressource externe, aucun droit d'auteur.
- Les matériaux sont dans `front/data/materials/` et se règlent dans l'inspecteur.

## Règles de travail

1. **Une seule version de Godot : 4.7.2.** Ouvrir le projet avec une autre version le convertit et provoque des conflits.
2. **Ne jamais versionner le dossier `.godot/`** : il s'agit d'un cache régénéré automatiquement (déjà exclu par le `.gitignore`).
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

- [x] Menu principal (Jouer / Quitter)
- [x] Arène 3D avec obstacles
- [x] Apparition aléatoire du joueur
- [x] Déplacement, course, saut, caméra à la troisième personne
- [x] Tir (cadence, chargeur, rechargement) et cibles d'entraînement
- [x] Classes (Tank, Assassin, Tireur), armes et capacités
- [x] Écran de choix de classe
- [x] Points de vie, mort et réapparition, HUD complet
- [x] Map « Arena » 120 x 120 m texturée (6 zones, 16 points d'apparition)
- [x] Personnages 3D animés (3 classes + mannequin), armes modélisées
- [x] Accroupissement
- [ ] Partie chronométrée et tableau des scores
- [ ] Bots d'entraînement
- [ ] Connexion au serveur de jeu
- [ ] Affichage des autres joueurs
- [ ] Micro-services et bases de données
