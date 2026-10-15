# Sons du jeu

## D'où viennent-ils ?

Tous les sons de ce dossier sont **générés par le script `tools/generate_sounds.py`**.
Ils sont calculés de toutes pièces (bruit filtré, oscillateurs, enveloppes, petite réverbération), sans aucun enregistrement extérieur. Il n'y a donc **aucune licence à respecter** : ils appartiennent au projet.

Pour les régénérer, après avoir modifié une recette dans le script, lance depuis la racine du dépôt :

```
python tools/generate_sounds.py      # dépendance : numpy
```

Ouvre ensuite le projet dans Godot pour qu'il réimporte les fichiers, puis commite les `.wav` et leurs `.import`.

Les sons joués souvent existent en plusieurs **variantes** (`step.wav`, `step_2.wav`, `step_3.wav`…). Le jeu en tire une au hasard à chaque lecture, avec en plus une petite variation de hauteur, pour éviter l'effet « mitraillette de copier-coller ».

## Remplacer un son par un vrai enregistrement

Tu peux mettre de vrais sons à la place des sons générés, **sans toucher au code** :

1. Récupère un son **libre de droits**, de préférence **CC0** (domaine public, aucune attribution obligatoire).
2. Renomme-le comme le son à remplacer, au format `.ogg` (conseillé) ou `.wav`. Par exemple : `explosion.ogg`, `headshot.ogg`, `step.ogg`.
   Pour plusieurs variantes, ajoute `_2`, `_3`… : `step.ogg`, `step_2.ogg`, `step_3.ogg`.
3. Dépose-le dans **`front/assets/sounds/custom/`**.
4. Ouvre le projet dans Godot (import automatique). Le jeu utilise alors ta version : le dossier `custom/` passe toujours avant les sons générés.

Pour revenir au son généré, il suffit de supprimer le fichier de `custom/`.

### Où trouver des sons CC0

- **Kenney** (https://kenney.nl/assets) : packs « Impact Sounds », « Sci-fi Sounds », « Interface Sounds ». Tout est en CC0.
- **Freesound** (https://freesound.org) : dans la recherche, filtre la licence sur « Creative Commons 0 ». Les autres licences demandent une attribution, voire interdisent l'usage commercial : à éviter ou à créditer.
- **Sonniss, GameAudioGDC Bundle** (https://sonniss.com/gameaudiogdc) : des gigaoctets de sons professionnels libres de droits (licence Sonniss : usage libre dans un jeu, mais pas de revente des sons seuls).

### À vérifier avant d'ajouter un son

- **La licence.** Note dans ce fichier, à la section « Crédits » ci-dessous, la source et la licence de chaque son ajouté.
- **Le format.** Mono de préférence pour les sons placés dans le monde : un son stéréo n'est pas spatialisé correctement. 44,1 kHz.
- **Le niveau.** Normalise autour de -1 dB crête. Le jeu a déjà un compresseur et un limiteur sur la sortie.
- **La durée.** Coupe le silence au début : un tir doit partir instantanément.

## Liste des sons

| Nom | Joué quand |
|---|---|
| `shot_smg`, `shot_shotgun`, `shot_sniper`, `shot_rocket`, `shot_flame`, `shot_laser` | tir de chaque arme |
| `katana_swing`, `katana_hit` | coup de katana, katana qui touche |
| `poop_launch`, `poop_splat` | tir et impact du lance-caca (cartoon) |
| `grenade_throw`, `grenade_bounce`, `explosion` | grenade lancée, rebond, explosion (roquette, grenade) |
| `hit`, `headshot`, `kill` | touche, tir à la tête, élimination (retours pour le tireur) |
| `impact_body`, `impact_world` | balle dans un personnage, dans le décor |
| `hurt`, `heartbeat` | coup reçu, vie basse |
| `step`, `land` | pas, atterrissage après une chute |
| `switch`, `reload` | changement d'arme, rechargement |
| `ability_shield`, `ability_dash`, `ability_pierce`, `ability_charge` | capacités des spécialistes |
| `pickup`, `powerup` | ramassage d'un bonus, super-pouvoir |
| `spawn`, `deflect` | réapparition, balle déviée par la protection d'apparition |
| `ui_click`, `ui_open`, `ui_close` | interface |
| `ambience` | fond sonore de la map, en boucle |

## Crédits

Aucun son extérieur pour l'instant : tous les sons sont générés par `tools/generate_sounds.py`.
