# Arena TPS

Jeu de tir multijoueur en 3D, en vue à la troisième personne, en mode chacun pour soi (**jusqu'à 16 joueurs** par partie, complétés par des bots). Deux maps : **« NEO-EDO »**, un quartier japonais où un temple traditionnel côtoie les néons de Tokyo, et **« Hikari Mall »**, un centre commercial abandonné sur deux niveaux. Le projet sert de support à la mise en œuvre d'une **architecture micro-services**.

Projet réalisé en binôme par **Julien** (client de jeu et serveur de jeu) et **Elian** (micro-services et bases de données) — Architecture SI, M2, CFA INSTA.

## Sommaire

1. [Organisation du dépôt](#organisation-du-dépôt)
2. [Lancer le jeu](#lancer-le-jeu)
3. [Jouer en ligne](#jouer-en-ligne)
4. [Commandes](#commandes)
5. [Modes de jeu](#modes-de-jeu)
6. [Spécialistes, classes et armes](#spécialistes-classes-et-armes)
7. [Bonus de la map](#bonus-de-la-map)
8. [Les maps](#les-maps)
9. [Sons](#sons)
10. [Architecture du code](#architecture-du-code)
11. [Tester](#tester)
12. [Outils](#outils-tools)
13. [Crédits et licences](#crédits-et-licences-des-ressources)
14. [Règles de travail](#règles-de-travail)
15. [État d'avancement](#état-davancement)

## Organisation du dépôt

```
arena-tps/
├── front/       Projet Godot 4.7.2 : le jeu ET le serveur de jeu dédié — responsable : Julien
├── services/    Renvoi vers le dépôt du back (TPSArena_backend) — responsable : Elian
├── tools/       Scripts de génération des ressources (textures, sons, police) et d'export
├── docs/        Guides : lancer le serveur et les clients, jouer en réseau
└── README.md
```

Les micro-services (Auth, Social, Server List, Stats, Real-time, BFF) sont dans le dépôt séparé **`TPSArena_backend`**, à cloner à côté de celui-ci.

## Lancer le jeu

1. Installer **Godot 4.7.2** (version imposée pour toute l'équipe).
2. Dans le gestionnaire de projets de Godot, cliquer sur **Importer** et choisir `front/project.godot`. Le premier import des modèles et textures prend quelques dizaines de secondes.
3. Lancer avec **F5**.
4. Sur l'écran de connexion : se connecter avec un compte (back lancé), ou cliquer sur **« Jouer hors ligne »** pour jouer sans back (n'importe quel identifiant convient).

### Parcours

| Écran | Contenu |
|---|---|
| Connexion / inscription | Connexion, création de compte, vérification de l'e-mail par code à 6 chiffres, mot de passe oublié, adresse du back |
| Accueil — JOUER | Spécialiste et classe choisis (aperçu 3D), groupe, lancement en ligne, serveurs publics, rejoindre par adresse (LAN), partie solo et entraînement avec choix de la map |
| Accueil — SPÉCIALISTES | Choix du personnage (Samouraï, Shinobi, Archer, Oni) avec aperçu 3D animé |
| Accueil — CLASSES | Jusqu'à 10 classes personnalisées : arme principale + arme secondaire (+ 2 grenades) |
| Accueil — STATISTIQUES | Statistiques du joueur, classements mondial et entre amis |
| Salon (LAN) | Joueurs connectés ; le chef choisit la map, le nombre de bots et la durée |
| Partie | HUD (vie, armure, munitions, bonus, super-pouvoir), fil des éliminations, tableau des scores (Tab), écran de fin avec podium |

## Jouer en ligne

Le jeu se joue à plusieurs **en vrai réseau**, sur un **serveur dédié** : un PC lance `ArenaTPS_Server` (sans fenêtre, il ne joue pas) et les joueurs le rejoignent avec le jeu. Le jeu et le serveur sont exportés depuis le même projet Godot.

**En LAN** (sans back) :

1. Le PC serveur lance `ArenaTPS_Server`, qui affiche ses adresses.
2. Chaque joueur saisit l'adresse dans le cadre « Rejoindre par adresse » de la page JOUER, puis clique **REJOINDRE**.
3. Le premier joueur connecté (le chef) choisit la map, le nombre de bots et la durée, puis lance la partie. On peut aussi rejoindre une partie en cours.

**Avec le vrai back** : le chef d'un groupe clique **LANCER EN LIGNE**. La Server List réserve un serveur libre, tout le groupe s'y connecte automatiquement, et les résultats partent aux statistiques à la fin de la partie. La liste **SERVEURS PUBLICS** permet de rejoindre une partie en cours.

Guides détaillés :

- lancer le serveur et les clients pas à pas, sous Linux, Windows et macOS : **[docs/LANCER.md](docs/LANCER.md)** ;
- jouer depuis plusieurs maisons, pare-feu et dépannage réseau : **[docs/RESEAU.md](docs/RESEAU.md)**.

### Qui décide de quoi

Le serveur est **l'arbitre** : le jeu de chaque joueur lui envoie des **actions** (« je tire », « je recharge », « j'ai touché telle cible à tel endroit »), jamais des résultats.

| Élément | Qui décide |
|---|---|
| Déplacement de son propre personnage | le jeu du joueur (aucune latence) |
| Validité d'un tir : arme de la classe, munitions, cadence, portée, ligne de vue | **le serveur** |
| Zone touchée (tête ou corps) et dégâts | **le serveur** |
| Vie, armure, éliminations, score, réapparitions, chronomètre | **le serveur** |
| Roquettes, grenades et explosions | **le serveur** (les jeux ne font qu'afficher) |
| Bonus ramassés, réapparition des bonus, super-pouvoirs | **le serveur** |
| Bots | **le serveur** |

Le protocole est décrit en tête de `front/scripts/net/net.gd`, et le serveur se trouve dans `front/scripts/server/`.

## Commandes

| Touche | Action |
|---|---|
| Souris | Orienter la caméra |
| Clic gauche | Tirer |
| Clic droit | Viser (zoom, meilleure précision) |
| Z Q S D ou flèches | Se déplacer (W A S D sur un clavier QWERTY : les touches suivent leur position) |
| Maj | Courir |
| Espace | Sauter (deux fois avec le bonus Double saut) |
| Ctrl ou C (maintenir) | S'accroupir : silhouette plus basse, tir plus précis, déplacement plus lent |
| R | Recharger |
| 1 / 2 / molette | Arme principale / arme secondaire |
| 3 | Arme spéciale ramassée sur la map |
| G | Lancer une grenade (2 par vie) |
| E | Capacité du spécialiste |
| F | Déclencher le super-pouvoir en réserve |
| Tab (maintenir) | Tableau des scores |
| Échap | Menu pause (la partie continue) |
| F9 | S'infliger 25 dégâts (test, versions de développement) |

### Menu pause

**Échap** ouvre le menu pause du joueur local. La partie **ne s'arrête pas** : notre personnage reste dans l'arène, immobile et vulnérable. Le menu propose :

- **Reprendre** ;
- **Changer de spécialiste ou de classe** : le choix s'applique à la prochaine apparition, et le score de la partie est conservé ;
- **Paramètres** : volume général, effets, interface, sensibilité de la souris, inversion de l'axe vertical (enregistrés dans `user://parametres.cfg`) ;
- **Quitter la partie** (avec confirmation).

### Protection d'apparition

Pendant **3 secondes** après chaque apparition, le joueur ne prend aucun dégât : une bulle lumineuse est visible par tous, les balles sont déviées et les bots ne le visent pas. La protection s'arrête dès que le joueur tire.

## Modes de jeu

- **Match à mort** (chacun pour soi) : 3 minutes par défaut (de 1 à 10 minutes), avec fil des éliminations, séries, meneur, tableau des scores, écran de fin et podium.
  - **En ligne**, sur un serveur dédié : de 1 à 16 joueurs, complétés par des bots. Le serveur envoie le résultat au back (`match.finished`), qui calcule XP, niveaux, succès et classements.
  - **« Partie solo »** hors ligne, contre 5 bots : rien n'est compté.
- **Entraînement** : le joueur seul avec des mannequins-robots (dont certains accroupis), sans limite de temps.

Pour les parties hors ligne, la map se choisit sur la page JOUER (« Map hors ligne ») ; en LAN, c'est le chef du salon qui la choisit.

### Tirs à la tête

Chaque arme à balles a un multiplicateur de dégâts pour la tête (×1,5 au fusil à pompe, ×2,5 au fusil de précision). C'est le serveur qui décide de la zone touchée, à partir du point d'impact signalé. Un tir à la tête est récompensé par un son métallique distinct, un réticule jaune et une icône dans le fil des éliminations. Le joueur touché voit d'où vient le tir (indicateur de provenance).

### Bots

`front/scripts/bots/bot_brain.gd` remplit les mêmes commandes que le clavier et la souris (`PlayerCommands`). Le personnage est ainsi découpé en **entrées** et **simulation**. Les bots :

- repèrent les ennemis (champ de vision, murs bloquants) et réagissent quand on leur tire dessus ;
- visent avec un temps de réaction et une erreur qui diminue, et tirent selon leur arme (rafales, coup par coup, corps à corps) ;
- se déplacent grâce à un maillage de navigation calculé au chargement à partir des collisions de la map, sur les deux niveaux du mall comme dans les ruelles de NEO-EDO ;
- utilisent leur capacité, ramassent les bonus et déclenchent leur super-pouvoir.

## Spécialistes, classes et armes

Le joueur choisit un **spécialiste** (le personnage, sa vie et sa capacité), puis une **classe** (son équipement), dans l'esprit de *Black Ops 2*. Tout est décrit par des fichiers de données modifiables dans l'inspecteur de Godot :

- `front/data/classes/*.tres` : spécialistes (points de vie, vitesse, capacité, apparence) ;
- `front/data/weapons/*.tres` : armes (dégâts, cadence, chargeur, portée, dispersion, zoom, explosion, modèle 3D).

### Spécialistes

| Spécialiste | PV | Capacité (E) |
|---|---|---|
| Samouraï 侍 | 150 | Garde de fer : −70 % de dégâts reçus pendant 3 s |
| Shinobi 忍 | 80 | Pas éclair : bond fulgurant dans la direction du déplacement |
| Archer 弓 | 100 | Flèche perforante : les balles traversent les ennemis pendant 6 s |
| Oni 鬼 | 130 | Ruée : charge de 0,35 s, les ennemis percutés prennent 30 dégâts et sont projetés |

### Classes

Une classe = **une arme principale + une arme secondaire + 2 grenades**. Chaque joueur peut en créer **jusqu'à 10** (page CLASSES). Avec le vrai back, elles sont enregistrées sur son compte (service Social, `GET`/`PUT /loadouts/me`) ; hors ligne, dans `user://loadouts.cfg`. Cinq classes sont proposées au départ : Assaut, Corps à corps, Précision, Démolition et Incendiaire.

| Emplacement | Armes |
|---|---|
| Principale | Mitraillette, Fusil à pompe (9 plombs), Fusil de précision (200 m), Lance-roquettes (explosion de 6 m), Lance-flammes (brûlure) |
| Secondaire | Pistolet laser, Katana (corps à corps), Lance-caca (ralentit et tache l'écran de la cible) |
| Équipement | 2 grenades par vie (rebondissent, explosent au bout de quelques secondes) |
| Spéciale (bonus) | Sulfateuse, Fusil laser (balles perforantes), Poing puissant (30 s) |

Les **munitions** sont tenues par le serveur : un chargeur vide ou une cadence trop rapide fait refuser le tir.

## Bonus de la map

Des socles lumineux sont répartis sur chaque map (18 sur NEO-EDO, 17 sur Hikari Mall). Un bonus ramassé réapparaît au bout d'un certain temps.

| Bonus | Effet | Réapparition |
|---|---|---|
| Soin | +50 PV | 20 s |
| Armure | +50 points d'armure (100 au plus), qui absorbent les dégâts en premier | 30 s |
| Double saut | Un second saut en l'air pendant 30 s | 40 s |
| Vitesse | +35 % de vitesse pendant 12 s | 35 s |
| Sulfateuse, Fusil laser, Poing puissant | Arme spéciale sur la touche 3 | 60 s |
| Super-pouvoir (sanctuaire et mezzanine du laboratoire sur NEO-EDO, fontaine du mall) | Un super-pouvoir au hasard, déclenché avec **F** | 90 s |

Super-pouvoirs :

- **Surcharge néon** : dégâts ×1,5 et +25 % de vitesse pendant 12 s ;
- **Onde de choc** : explosion autour du joueur (8 m), qui repousse les ennemis ;
- **Invisibilité** : 10 s presque invisible, avec une courte apparition à chaque tir.

## Les maps

Chaque map est une scène à part (`front/scenes/maps/`), entièrement construite par code et chargée aussi par le serveur dédié. Elles sont listées dans `front/scripts/maps/map_catalog.gd` ; ajouter une map revient à créer sa scène et à l'ajouter à cette liste.

Après une modification d'un script de map, cliquer sur **Reconstruire la map** dans l'inspecteur de la scène (la map et ses animations sont visibles dans l'éditeur).

### NEO-EDO (`neo-edo`)

Arène de 120 × 120 m (`arena_map.gd`, scène `arena.tscn`). Deux ambiances se répondent : un quartier traditionnel et un quartier néon.

| Zone | Contenu |
|---|---|
| Centre | Sanctuaire sur une estrade de 3 m, grand torii, 4 rampes, lanternes de pierre, gardiens komainu |
| Nord-ouest | Marché couvert : échoppes de bois à toits de tuiles, tonneaux de saké, noren, guirlandes de lanternes |
| Nord-est | « IoT 研究所 » : laboratoire néon avec bras robotiques, tapis roulant, mezzanine, écran de supervision |
| Sud-ouest | Pagode à cinq toits et tour de guet reliées par une passerelle à 5 m, bosquets de bambous |
| Sud-est | Jardin sec : gravier ratissé, bassin à carpes koï, pont rouge, cerisiers en fleurs, pavillon de thé |
| Ruelles | Deux axes commerçants : enseignes verticales en kanji, distributeurs de boissons, lampadaires de pierre |

- **Habillage** (`arena_dressing.gd`) : pelouses, des milliers de touffes d'herbe affichées en un seul appel de rendu, buissons, et 24 couverts (murets, jardinières, caisses, chariots, barrières néon) placés à l'écart des points d'apparition.
- **Décor animé** (`front/scripts/maps/props/`) : caméras de surveillance sur les lampadaires qui suivent le joueur le plus proche, écran de supervision du laboratoire, bras robotiques, tapis roulant, cerisiers, lanternes de papier, rideaux de tissu, distributeurs, bassin à carpes.
- Les références **CFA INSTA** sont intégrées au thème : enseigne néon sur le laboratoire, plaque du sanctuaire « ネオ江戸アリーナ », bannières nobori et banderole au-dessus de la ruelle.

### Hikari Mall (`hikari-mall`)

Centre commercial abandonné au crépuscule, 100 × 100 m sur **deux niveaux** (`mall_map.gd`, scène `mall.tscn`). Le rez-de-chaussée est au niveau 0, l'étage à 5 m.

| Zone | Rez-de-chaussée | Étage |
|---|---|---|
| Centre | Atrium sur deux niveaux, fontaine à sec (super-pouvoir), verrière éventrée, rayons de soleil | Galerie avec garde-corps autour du vide, trous dans le plancher |
| Ouest | Supermarché : rayons qui servent de couverts | Balcon effondré |
| Est | Food court : comptoirs néon, tables | Salon |
| Nord | Hall d'entrée | Boutiques |
| Sud | Quai de livraison : camions, palettes | Réserve |
| Coins | Boutiques | Cinéma au nord-ouest (fusil laser dans la cabine de projection), arcade néon au nord-est |

On monte à l'étage par 6 escalators. Les points d'apparition (8 au rez-de-chaussée, 8 à l'étage) et les 17 socles de bonus ont été vérifiés : de la place libre autour, à l'écart des apparitions.

## Sons

Tous les sons sont **générés par synthèse** (`tools/generate_sounds.py`, aucun son externe, donc aucune question de licence) : 36 sons, 52 fichiers avec leurs variantes.

- Tirs propres à chaque arme ; impacts sur le décor et sur les corps ; « tic » de touche ; son distinct pour un tir à la tête ; élimination ; explosions ; pas (on entend un ennemi approcher) ; capacités ; bonus ; interface ; ambiance de la ville.
- Les sons joués souvent ont plusieurs variantes, tirées au hasard avec une légère variation de hauteur.
- Le bus principal a un compresseur et un limiteur ; les sons des autres joueurs sont spatialisés.
- Pour remplacer un son par un enregistrement libre de droits (CC0), il suffit de déposer un fichier du même nom dans `front/assets/sounds/custom/`, sans toucher au code : voir **[front/assets/sounds/LISEZMOI.md](front/assets/sounds/LISEZMOI.md)**.

## Architecture du code

Tout est dans `front/` (projet Godot). Les grandes idées :

| Partie | Rôle |
|---|---|
| `scripts/boot.gd` | Scène de départ : ouvre le serveur dédié (export serveur, `--server` ou sans écran), sinon l'écran de connexion |
| `scripts/player.gd`, `player_commands.gd`, `inputs.gd` | Le personnage simule à partir d'un objet `PlayerCommands`, rempli par le clavier et la souris (joueur local) ou par l'IA (bot) |
| `scripts/weapon.gd`, `scripts/shared/projectile.gd` | Tirs, rechargement, corps à corps, flammes, projectiles et grenades |
| `scripts/game.gd` | La partie côté joueur : hors ligne, elle fait foi ; en ligne, elle affiche ce que décide le serveur |
| `scripts/net/net.gd` (autoload `Net`) | Toute la couche réseau (ENet, UDP 24567), commune au jeu et au serveur : tous les RPC y sont déclarés |
| `scripts/server/` | Serveur dédié : `server_main.gd` (cycle salon → partie → fin), `server_game.gd` (arbitrage), `backend_link.gd` (lien avec la Server List) |
| `scripts/shared/` | Règles partagées entre le serveur et le jeu hors ligne : `MatchRules`, `PickupDirector` (bonus) |
| `scripts/backend/` (autoload `Backend`) | Façade unique vers le back : `bff_backend.gd` (HTTP vers le BFF + WebSocket temps réel) ou `simulated_backend.gd` (hors ligne) |
| `scripts/maps/` | Maps construites par code (`arena_map.gd`, `mall_map.gd`), catalogue des maps, décor animé |
| `scripts/character/` | Personnages humains animés (mélange d'animations, cinématique inverse pour la visée) et mannequins-robots |
| `data/` | Spécialistes et armes (`.tres`) |

Côté back, le jeu ne parle qu'au **BFF** (HTTP) et au service **Real-time** (WebSocket) ; le serveur de jeu parle seulement à la **Server List** (enregistrement, battement de cœur, vérification des tickets, résultats). Il n'y a pas de nouveau service ni de base de données côté jeu.

## Tester

- **Dans l'éditeur** : F5 lance le jeu. Pour une partie en réseau sur un seul PC : **Débogage → Personnaliser les instances de lancement…**, 3 instances, la première avec les arguments `--headless -- --server`.
- **En ligne de commande**, depuis `front/` :

  ```bash
  godot --headless -- --server --bots 4 --duration 120 --map hikari-mall   # serveur
  godot                                                                     # un joueur (répéter)
  ```

  Les joueurs rejoignent `127.0.0.1`.
- **À vérifier à la main** à chaque version :
  - une partie solo sur chaque map ;
  - une partie LAN à deux (changement de map par le chef, tirs, tirs à la tête, bonus, explosions) ;
  - l'écran de fin ;
  - l'entraînement.
- Le serveur écrit chaque connexion, chaque tir refusé (avec sa raison) et chaque fin de partie dans sa console et dans `reseau.log` (voir [docs/RESEAU.md](docs/RESEAU.md)).

## Outils (`tools/`)

| Script | Rôle |
|---|---|
| `generate_textures.py` | Textures tuilables des maps (béton, métal, bois…) générées par bruit mathématique |
| `generate_suit_masks.py` | Masques des combinaisons calculés à partir des poids de skinning des modèles |
| `extract_animations.gd` | Extraction d'une bibliothèque d'animations compacte (à lancer depuis l'éditeur) |
| `generate_sounds.py` | Effets sonores du jeu, calculés par synthèse |
| `subset_font.py` | Allège la police japonaise en ne gardant que les caractères affichés par le jeu (à relancer après avoir ajouté du japonais dans le code) |
| `build_client.sh` | Exporte le client lourd (`.exe` Windows, binaire Linux ou `.app` macOS) |
| `build_server.sh` | Exporte le serveur dédié dans `../server/` (Windows ou Linux, sans fenêtre) |
| `lancer_serveur.sh` | Lance le serveur Linux exporté, branché sur le vrai back (secret lu dans `backend/.env`, adresse IP détectée) |

Dépendances Python : `numpy`, `pillow`, `fonttools`.

## Crédits et licences des ressources

- Personnages et animations : **Quaternius** — Universal Base Characters, Universal Animation Library, Modular Character Outfits — licence **CC0** (domaine public). Textes de licence dans `front/assets/characters/quaternius/licenses/`.
- Polices : **Orbitron**, **Rajdhani** et **Noto Sans JP** (japonais) — licence **SIL Open Font License** (fichiers OFL dans `front/assets/fonts/`). La police japonaise est livrée sous forme de sous-ensemble (voir `tools/subset_font.py`).
- Textures des maps, effets sonores, équipements, robots, armes et décors : générés par le projet.

## Règles de travail

1. **Une seule version de Godot : 4.7.2.** Ouvrir le projet avec une autre version le convertit et provoque des conflits.
2. **Ne jamais versionner le dossier `.godot/`** : c'est un cache régénéré automatiquement (déjà exclu par le `.gitignore`).
3. **Versionner les fichiers `.uid` et `.import`** : Godot s'en sert pour retrouver les ressources et leurs réglages d'import.
4. **Ne pas déplacer de fichiers en dehors de l'éditeur** : les références des scènes `.tscn` casseraient.
5. **Éviter de modifier la même scène `.tscn` à deux en même temps** : ces fichiers fusionnent mal.
6. **Ne jamais committer de secrets** (mots de passe, clés) : utiliser un fichier `.env`, exclu du dépôt, et fournir un `.env.example`.
7. **Travailler sur des branches** et ne fusionner dans `main` que du code fonctionnel.
8. **Changer `BUILD_VERSION`** (`front/scripts/backend/backend.gd`) dès que le protocole réseau change : le serveur refuse un jeu d'une autre version.

### Convention de branches et de commits

- `main` : version stable, toujours fonctionnelle ;
- `front/<sujet>` : travail sur le jeu (ex. `front/phase4-map`) ;
- `services/<sujet>` : travail sur le back (ex. `services/loadouts`).

Messages de commit courts, au présent, préfixés par la zone concernée :

```
front: ajoute le tir par raycast
services: crée le service d'authentification
docs: complète le README
```

## État d'avancement

- [x] Écrans de connexion, inscription, vérification par code, mot de passe oublié
- [x] Accueil multijoueur (profil, groupe, amis, serveurs publics, statistiques)
- [x] Personnages humains cyberpunk animés (4 spécialistes) et mannequins-robots
- [x] Déplacement, course, saut, accroupissement, caméra à la troisième personne
- [x] Classes personnalisables (10 au plus), 8 armes, grenades, capacités
- [x] Tirs à la tête et munitions arbitrés par le serveur, indicateur de provenance
- [x] Bonus sur la map : soin, armure, mobilité, armes spéciales, super-pouvoirs
- [x] Deux maps : NEO-EDO (120 × 120 m) et Hikari Mall (100 × 100 m, 2 niveaux), choix de la map
- [x] Match à mort contre des bots, tableau des scores, écran de fin
- [x] Menu pause local, protection d'apparition, sons générés avec variantes
- [x] Multijoueur en ligne sur serveur dédié (Godot sans écran), 16 joueurs, mode LAN
- [x] Export du client lourd Windows / Linux / macOS (macOS non testé) et du serveur dédié Windows / Linux
- [x] Connexion au vrai back (BFF + temps réel côté jeu, Server List côté serveur), mode hors ligne conservé
- [ ] Serveur entièrement autoritaire (les joueurs n'envoient que leurs commandes)
- [ ] Anti-triche sur les déplacements et compensation de la latence
