# Arena TPS

Jeu de tir multijoueur en 3D, en vue à la troisième personne, en mode chacun pour soi (jusqu'à 16 joueurs par partie), dans un quartier japonais **« NEO-EDO »** mêlant temple traditionnel et néons de Tokyo. Le projet sert de support à la mise en œuvre d'une **architecture micro-services**.

Projet réalisé en binôme par **Julien** (client de jeu) et **Elian** (micro-services et bases de données) — Architecture SI, M2, CFA INSTA.

> Pour comprendre le code (architecture, réseau, lien avec le back) : voir [CLAUDE.md](CLAUDE.md) (en anglais).
> Lancer le serveur et les clients : [docs/LANCER.md](docs/LANCER.md).

## Organisation du dépôt

```
arena-tps/
├── front/       Projet Godot 4.7.2 : le jeu ET le serveur dédié — responsable : Julien
├── services/    Simple renvoi : le back est dans un dépôt séparé (TPSArena_backend) — Elian
├── tools/       Génération des ressources, export et lancement du jeu et du serveur
├── docs/        Guides : lancer le serveur et les clients, réseau
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
| Menu principal | Profil (niveau, XP), groupe jusqu'à 16 joueurs (personnage de chaque membre affiché, exclusion et passation du rôle de chef) et invitations, lancement en ligne, rejoindre un serveur LAN par adresse (hors ligne seulement), partie solo et entraînement, amis (recherche, demandes, présence) |
| Serveurs publics | Parties en cours avec des places libres (région, map, joueurs) |
| Statistiques | Statistiques du joueur, succès, classements (XP, victoires, éliminations : le haut ou autour de soi) |
| Spécialistes | Choix du personnage (apparence, vie, vitesse, capacité) avec aperçu 3D animé |
| Classes | Jusqu'à 10 équipements (arme principale, arme secondaire, 2 grenades), enregistrés sur le compte |
| Partie | Match à mort (3 minutes par défaut) contre d'autres joueurs et des bots, sur NEO-EDO ou Hikari Mall, tirs à la tête, bonus, tableau des scores, écran de fin |

### Jouer en ligne

Le jeu se joue à plusieurs **en vrai réseau**, sur un **serveur dédié** : un PC lance
`ArenaTPS_Server` (sans fenêtre, il ne joue pas), les joueurs le rejoignent avec le jeu.
Le jeu et le serveur sont exportés depuis le même projet Godot. Deux façons de jouer :

- **Avec le vrai back** (comptes, amis, statistiques) : le serveur est lancé en mode
  Server List (`tools/lancer_serveur.sh`). Les joueurs se connectent avec leur compte
  (e-mail ou pseudo), forment un groupe, et le chef clique **LANCER EN LIGNE**, règle les bots et la durée,
  puis **LANCER LA PARTIE** : tout le groupe rejoint le serveur automatiquement. Les **SERVEURS PUBLICS** permettent de
  rejoindre une partie en cours.
- **En LAN, sans back** : « Jouer hors ligne » sur l'écran de connexion, puis
  **REJOINDRE PAR ADRESSE** avec l'adresse affichée par le serveur. Le premier joueur
  connecté (le chef) règle les bots et la durée, puis lance la partie.

Lancer le serveur et les clients pas à pas, sous Linux et Windows :
**[docs/LANCER.md](docs/LANCER.md)**. Jouer depuis plusieurs maisons, pare-feu et
dépannage réseau : **[docs/RESEAU.md](docs/RESEAU.md)**.

Qui décide de quoi : chaque jeu simule son propre joueur et signale ses impacts ; le
serveur arbitre la vie, les éliminations, le score, le chronomètre et les réapparitions,
et fait jouer les bots. Le protocole est dans `front/scripts/net/net.gd`, le serveur dans
`front/scripts/server/`.

Le jeu est **connecté au vrai back** (micro-services du dépôt `backend/`, via le BFF et le
service temps réel) : comptes avec vérification de l'e-mail, amis et présence, groupes et
invitations, lancement d'une partie de groupe sur un serveur dédié, serveurs publics,
statistiques, succès et classements (`front/scripts/backend/`). Le lien **« Jouer hors
ligne »** de l'écran de connexion garde un back simulé, sans réseau, pour jouer en LAN
sans lancer le back.

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

**Échap** ouvre le menu pause du joueur local. La partie **ne s'arrête pas** : les bots et les autres joueurs continuent, et notre personnage reste dans l'arène, immobile et vulnérable. Le menu propose :

- **Reprendre** ;
- **Changer de classe** : la classe choisie est utilisée à la prochaine apparition, le score de la partie est conservé ;
- **Paramètres** : volume général, effets, interface, sensibilité de la souris, inversion de l'axe vertical (enregistrés dans `user://parametres.cfg`, autoload `Settings`) ;
- **Quitter la partie** (avec confirmation).

### Protection d'apparition

Pendant **3 secondes** après chaque apparition, le joueur ne prend aucun dégât (bulle lumineuse visible par tous, compte à rebours sous le réticule). Les balles sont déviées et les bots ne le visent pas. La protection s'arrête dès que le joueur tire. Durée réglable dans `player.gd` (`SPAWN_PROTECTION_TIME`).

### Sons

Effets sonores générés par `tools/generate_sounds.py` (tirs des 3 armes, impacts, élimination, rechargement, capacités, apparition, interface). Les sons des autres joueurs sont spatialisés. Lecture via l'autoload `Sfx`, sur les bus audio `Effets` et `Interface`.

## Modes de jeu

- **Match à mort** (en ligne sur serveur dédié, ou « Partie solo » hors ligne contre des bots) : 3 minutes par défaut. Fil des éliminations, séries, meneur, tableau des scores et classement final. En ligne, le serveur envoie le résultat au back (`match.finished`) ; hors ligne, rien n'est compté.
- **Entraînement** : le joueur seul avec des mannequins-robots (dont certains accroupis), sans limite de temps.

### Bots

`front/scripts/bots/bot_brain.gd` remplit les mêmes commandes que le clavier et la souris (`PlayerCommands`) : le joueur est ainsi découpé en **entrées** et **simulation**, la séparation dont le futur serveur de jeu autoritaire aura besoin. Les bots :

- repèrent les ennemis (champ de vision, murs bloquants) et réagissent quand on leur tire dessus ;
- visent avec un temps de réaction et une erreur qui diminue, tirent en rafales ou au coup par coup ;
- se déplacent grâce à un maillage de navigation calculé au chargement à partir des collisions de la map ;
- utilisent leur capacité (bouclier, dash, tir perforant).

## Spécialistes, classes et armes

Deux choix séparés, décrits par des fichiers de données modifiables dans l'inspecteur de Godot :

- le **spécialiste** est le personnage : apparence, points de vie, vitesse et capacité (`front/data/classes/*.tres`, écran SPÉCIALISTES) ;
- la **classe** est l'équipement : une arme principale, une arme secondaire et 2 grenades. Chaque joueur crée jusqu'à 10 classes (onglet CLASSES), enregistrées sur son compte, et choisit la sienne sur la page JOUER. N'importe quel spécialiste peut prendre n'importe quelle classe.

Les armes sont dans `front/data/weapons/*.tres` (dégâts, cadence, chargeur, dispersion, zoom, modèle 3D) et listées dans `front/scripts/data/weapon_catalog.gd`. Le serveur arbitre les tirs à la tête.

| Spécialiste | PV | Capacité |
|---|---|---|
| Samouraï 侍 | 150 | Garde de fer : -70 % de dégâts pendant 3 s |
| Shinobi 忍 | 80 | Shunpo : bond rapide dans la direction du déplacement |
| Archer 弓 | 100 | Flèche perforante : les balles traversent les ennemis pendant 6 s |
| Oni 鬼 | 130 | Charge : ruée de 0,35 s, les ennemis percutés prennent 30 dégâts et sont projetés |

Armes des classes : mitraillette, fusil à pompe, fusil de précision, lance-roquettes, lance-flammes, pistolet laser, katana, lance-caca. D'autres armes (sulfateuse, fusil laser, poing puissant…) ne s'obtiennent qu'avec les bonus ramassés sur la map.

## Personnages

Personnages humains dans le thème « néo-Edo » (`front/scripts/character/`) : armure de samouraï laquée, tenue de shinobi, archer de kyūdō, le tout revisité en cyberpunk.

| Fichier | Rôle |
|---|---|
| `human_rig.gd` | Corps humain importé, animations (repos, marche, jogging, sprint, accroupi, saut, mort) mélangées selon la vitesse |
| `aim_ik_modifier.gd` | Après l'animation : bas du corps tourné vers le déplacement (pas chassés, marche arrière), buste vers la visée, mains posées sur l'arme (cinématique inverse) |
| `human_designs.gd` | Chara design par classe : corps, coupe et couleur de cheveux, combinaison, équipement accroché aux os |
| `cyber_suit.gdshader` (dans `front/shaders/`) | Combinaison colorée par classe avec liserés néon, visage conservé |
| `character_rig.gd`, `character_designs.gd` | Robots procéduraux (mannequins d'entraînement) et modèles 3D des armes |
| `character_preview.gd` | Aperçus 3D animés des menus |

L'animation est pilotée par l'état du personnage (vitesse, au sol, accroupi, angle de visée) : en multijoueur, c'est cet état qui est transmis pour animer les autres joueurs.

## Maps

Deux maps, listées dans `front/scripts/maps/map_catalog.gd` : **NEO-EDO** (par défaut) et **Hikari Mall**, un centre commercial abandonné de 100 x 100 m sur 2 niveaux (`front/scripts/maps/mall_map.gd`, `front/scenes/maps/mall.tscn`). La map d'une partie est choisie par le serveur (`--map`), par le chef du salon en LAN, ou sur la page JOUER pour la partie solo et l'entraînement.

### NEO-EDO

Arène de 120 x 120 m définie dans `front/scripts/maps/arena_map.gd` et chargée par `front/scenes/maps/arena.tscn` (scène séparée du jeu, chargée aussi par le serveur dédié). Deux ambiances se répondent : un quartier traditionnel et un quartier néon.

| Zone | Contenu |
|---|---|
| Centre | Sanctuaire sur une estrade de 3 m, grand torii, 4 escaliers, lanternes de pierre, gardiens komainu |
| Nord-ouest | Marché couvert : échoppes de bois à toits de tuiles, tonneaux de saké, noren, guirlandes de lanternes |
| Nord-est | « IoT 研究所 » : laboratoire néon avec bras robotiques, tapis roulant, mezzanine, écran de supervision |
| Sud-ouest | Pagode à cinq toits et tour de guet reliées par une passerelle à 5 m, bosquets de bambous |
| Sud-est | Jardin sec : gravier ratissé, bassin à carpes koï, pont rouge, cerisiers en fleurs, pavillon de thé |
| Ruelles | Deux axes commerçants : enseignes verticales en kanji, distributeurs de boissons, lampadaires de pierre |

Décor connecté (`front/scripts/maps/props/`) : caméras de surveillance qui suivent le joueur le plus proche, capteurs (température, humidité, CO2, bruit, lumière, présence) avec valeurs en direct, drones en patrouille, tableau de bord IoT, cerisiers animés, lanternes de papier, rideaux de tissu, distributeurs.

Les références **CFA INSTA** sont intégrées au thème : enseigne néon sur le laboratoire, plaque du sanctuaire « ネオ江戸アリーナ », bannières nobori et banderole au-dessus de la ruelle.

Les éléments de la map sont des listes et fonctions dans le script : après une modification, cliquer sur **Reconstruire la map** dans l'inspecteur de la scène `arena.tscn` (la map et ses animations sont visibles dans l'éditeur).

## Outils (`tools/`)

| Script | Rôle |
|---|---|
| `generate_textures.py` | Textures tuilables de la map (béton, métal, conteneurs…) générées par bruit mathématique |
| `generate_suit_masks.py` | Masques des combinaisons calculés à partir des poids de skinning des modèles |
| `extract_animations.gd` | Extraction d'une bibliothèque d'animations compacte depuis le pack d'animations |
| `generate_sounds.py` | Effets sonores du jeu, calculés par synthèse (aucun son externe) |
| `subset_font.py` | Allège la police japonaise en ne gardant que les caractères affichés par le jeu |
| `build_client.sh` | Exporte le client lourd (`.exe` Windows, binaire Linux ou `.app` macOS) |
| `build_server.sh` | Exporte le serveur dédié dans `../server/` (Windows ou Linux, sans fenêtre) |
| `lancer_serveur.sh` | Lance le serveur Linux exporté, branché sur le vrai back (secret lu dans `backend/.env`, adresse IP détectée) |

Dépendances Python : `numpy`, `pillow`.

## Crédits et licences des ressources

- Personnages et animations : **Quaternius** — Universal Base Characters, Universal Animation Library, Modular Character Outfits — licence **CC0** (domaine public). Textes de licence dans `front/assets/characters/quaternius/licenses/`.
- Polices : **Orbitron**, **Rajdhani** et **Noto Sans JP** (japonais) — licence **SIL Open Font License** (fichiers OFL dans `front/assets/fonts/`). La police japonaise est livrée sous-ensemblée (voir `tools/subset_font.py`).
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
- [x] Menu principal multijoueur (profil, groupe, amis, serveurs, statistiques)
- [x] Personnages humains cyberpunk animés (4 spécialistes) et mannequins-robots
- [x] Déplacement, course, saut, accroupissement, caméra à la troisième personne
- [x] Tir, munitions, tirs à la tête, spécialistes, classes (équipements) enregistrées sur le compte, armes, bonus et capacités
- [x] Map « NEO-EDO » 120 x 120 m texturée (sanctuaire, marché, pagode, jardin, ruelles néon), décor CFA INSTA et IoT animé
- [x] Map « Hikari Mall » (centre commercial sur 2 niveaux) et choix de la map
- [x] Match à mort contre des bots, tableau des scores, écran de fin
- [x] Menu pause local (changement de classe, son, sensibilité), protection d'apparition, effets sonores
- [x] Multijoueur en ligne sur serveur dédié (Godot headless), jusqu'à 16 joueurs, mode LAN
- [x] Export du client lourd Windows / Linux / macOS (macOS non testé) et du serveur dédié Windows / Linux
- [x] Connexion au vrai back-end (BFF + temps réel côté jeu, Server List côté serveur), mode hors ligne conservé
- [x] Micro-services et bases de données (dépôt séparé `TPSArena_backend`), envoi des codes par e-mail (Gmail)
- [ ] Serveur entièrement autoritaire (les joueurs n'envoient que leurs commandes)
- [ ] HTTPS / WSS, et une adresse fixe pour jouer depuis l'extérieur de l'école
