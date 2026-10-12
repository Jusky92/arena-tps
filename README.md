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
| Souris | Viser / orienter la caméra |
| Z Q S D ou flèches | Se déplacer |
| Maj | Courir |
| Espace | Sauter |
| Échap | Revenir au menu |

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
- [ ] Connexion au serveur de jeu
- [ ] Affichage des autres joueurs
- [ ] Micro-services et bases de données
