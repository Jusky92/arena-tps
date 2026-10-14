# Jouer en ligne — guide complet

Comment jouer à **Arena TPS** à plusieurs : **un PC lance le serveur dédié**
(`ArenaTPS_Server`, sans fenêtre) et chaque joueur le rejoint avec **le jeu**
(`ArenaTPS`, le client lourd exporté en `.exe`).

Sommaire :

1. [Comment ça marche](#1-comment-ça-marche)
2. [Exporter le jeu et le serveur](#2-exporter-le-jeu-et-le-serveur)
3. [Lancer le serveur](#3-lancer-le-serveur)
4. [Jouer sur le même réseau (le plus simple)](#4-jouer-sur-le-même-réseau)
5. [Jouer par Internet avec Tailscale (recommandé)](#5-jouer-par-internet-avec-tailscale)
6. [Jouer par Internet en ouvrant un port](#6-jouer-par-internet-en-ouvrant-un-port)
7. [Pare-feu du PC serveur](#7-pare-feu-du-pc-serveur)
8. [Tester sur un seul PC](#8-tester-sur-un-seul-pc)
9. [Dépannage](#9-dépannage)
10. [Limites actuelles et suite](#10-limites-actuelles-et-suite)

---

## 1. Comment ça marche

Le serveur dédié **ne joue pas** : il arbitre. Les joueurs, eux, lancent tous le même
jeu et s'y connectent. Le PC qui fait tourner le serveur peut aussi lancer le jeu
pour jouer, comme les autres.

```
                         PC serveur
                 ┌─────────────────────────┐
                 │  ArenaTPS_Server        │
                 │  • arbitre la vie       │
                 │  • compte les scores    │
                 │  • gère le chrono       │
                 │  • fait jouer les bots  │
                 └────────────▲────────────┘
                              │ UDP 24567
        ┌─────────────────────┼─────────────────────┐
 ┌──────┴───────┐      ┌──────┴───────┐      ┌──────┴───────┐
 │ ArenaTPS     │      │ ArenaTPS     │      │ ArenaTPS     │
 │ • simule son │      │ • simule son │      │ • simule son │
 │   joueur     │      │   joueur     │      │   joueur     │
 │ • signale ses│      │ • signale ses│      │ • signale ses│
 │   tirs       │      │   tirs       │      │   tirs       │
 └──────────────┘      └──────────────┘      └──────────────┘
```

Qui décide de quoi :

| Élément | Qui décide | Pourquoi |
|---|---|---|
| Déplacement de mon personnage | mon jeu | aucune latence : le jeu reste nerveux |
| Impacts de mes tirs | mon jeu (le tireur) | je tire sur ce que je vois à l'écran |
| Points de vie, éliminations, score | **le serveur** | une seule version de la vérité |
| Chronomètre, réapparitions, fin de match | **le serveur** | tout le monde reste synchronisé |
| Bots | **le serveur** | il les fait jouer et diffuse leur position |
| Réglages et lancement de la partie | **le chef** (premier joueur connecté) | en attendant les groupes du back |

Chaque jeu envoie la position de son joueur au serveur **20 fois par seconde** en UDP
non fiable, et le serveur rediffuse celle de tout le monde : si un paquet se perd, le
suivant arrive 50 ms plus tard. Les évènements importants (dégâts, morts, score)
passent, eux, en mode fiable. Les jeux ne se parlent jamais directement.

Le serveur tourne sans fin : salon → partie → écran de fin → salon. On peut
**rejoindre une partie en cours** s'il reste de la place (8 joueurs au plus ; un bot
cède sa place si besoin).

Le code :

- `front/scripts/net/net.gd` : le protocole, commun au jeu et au serveur ;
- `front/scripts/server/` : le serveur (`server_main.gd`, `server_game.gd`) ;
- `front/scripts/game.gd` : la partie côté joueur (section « Partie en ligne »).

---

## 2. Exporter le jeu et le serveur

Le jeu et le serveur viennent **du même projet Godot**. Seul le préréglage d'export
change : les préréglages « Serveur Windows » et « Serveur Linux » ont l'option
**Dedicated Server** (pas de fenêtre, pas de son).

### Une seule fois : installer les modèles d'export

Dans Godot : **Éditeur → Gérer les modèles d'exportation… → Télécharger et installer**.
C'est environ 1 Go, à ne faire qu'une fois par version de Godot.

### À chaque version du jeu

Depuis la racine du dépôt :

```bash
tools/build_client.sh all     # le jeu      -> build/windows/ArenaTPS.exe, build/linux/…
tools/build_server.sh all     # le serveur  -> ../server/windows/ArenaTPS_Server.exe, ../server/linux/…
```

Ou dans Godot : **Projet → Exporter…**, choisir le préréglage, **Exporter le projet…**,
en décochant « Exporter avec le débogage ».

On obtient **un seul fichier** par plateforme, avec les ressources embarquées. Sous
Windows, le serveur est aussi exporté en `ArenaTPS_Server.console.exe` : c'est celui-là
qu'on lance, pour voir sa console.

> Le serveur et tous les jeux doivent avoir **exactement la même version**. Après
> chaque modification, il faut tout réexporter et renvoyer les fichiers.

---

## 3. Lancer le serveur

> Guide pas à pas (Linux, Windows, pare-feu, clients) : **[LANCER.md](LANCER.md)**.

Sur le PC serveur, dans un terminal :

```bash
# Windows
ArenaTPS_Server.console.exe
# Linux
./ArenaTPS_Server.x86_64
```

Options (toutes facultatives) :

| Option | Défaut | Rôle |
|---|---|---|
| `--port 24567` | 24567 | port UDP d'écoute |
| `--bots 2` | 2 | bots pour compléter (le chef peut changer) |
| `--duration 180` | 180 | durée du match en secondes (le chef peut changer) |
| `--name "Arena TPS"` | Arena TPS | nom du serveur |

Au démarrage, le serveur affiche les **adresses à donner aux joueurs**, par exemple
`192.168.1.20:24567`. **Ctrl+C** l'arrête.

---

## 4. Jouer sur le même réseau

Si tous les PC sont sur le même Wi-Fi ou le même câble (salle de cours, appartement) :

1. Le PC serveur lance `ArenaTPS_Server` (§3) et note une des adresses affichées.
2. Chaque joueur lance `ArenaTPS`, se connecte, saisit l'adresse dans le champ de la
   page JOUER, puis **REJOINDRE**.
3. Le premier arrivé est le **chef** : il règle les bots et la durée, puis
   **LANCER LA PARTIE** démarre le jeu chez tout le monde. S'il part, le joueur
   suivant devient chef.

---

## 5. Jouer par Internet avec Tailscale

C'est la méthode **recommandée** quand vous n'êtes pas sur le même réseau : elle ne
demande aucun réglage de box, et ça marche même derrière un CGNAT (fibre 4G, certaines
offres opérateur).

Tailscale crée un petit réseau privé chiffré entre vos PC : chacun reçoit une adresse
fixe en `100.x.y.z`, comme si vous étiez sur le même Wi-Fi.

1. Tout le monde installe **Tailscale** (gratuit pour un usage personnel) :
   <https://tailscale.com/download>
2. Chacun se connecte avec le **même compte** (ou l'un invite les autres dans son réseau).
3. Le serveur affiche son adresse Tailscale en premier (`100.…`) ; sinon, sur le PC
   serveur : icône Tailscale → nom de la machine, ou `tailscale ip -4`.
4. Les joueurs saisissent cette adresse dans le champ d'adresse.

**ZeroTier** fonctionne exactement pareil si vous préférez.

---

## 6. Jouer par Internet en ouvrant un port

Sans logiciel tiers, mais il faut accéder à la box du PC serveur.

1. Trouver l'adresse IP locale du PC serveur (affichée au démarrage, ex. `192.168.1.20`).
2. Dans l'interface de la box (Freebox, Livebox, SFR…), section
   **Redirection de ports / NAT / Port forwarding**, créer une règle :

   | Champ | Valeur |
   |---|---|
   | Protocole | **UDP** |
   | Port externe | `24567` |
   | Port interne | `24567` |
   | IP de destination | l'IP locale du PC serveur |

3. Récupérer l'**IP publique** de la box : <https://www.monip.org> ou en tapant
   « mon ip » dans un moteur de recherche.
4. Les joueurs saisissent cette IP publique dans le champ d'adresse.

> Attention : l'IP publique change souvent chez les particuliers. Et si l'opérateur
> utilise du CGNAT (IP partagée), l'ouverture de port ne fonctionnera pas :
> passer par Tailscale.
>
> Une redirection de port expose un service à Internet : ne la laissez active que
> le temps de jouer.

---

## 7. Pare-feu du PC serveur

C'est **le PC serveur** qui reçoit les connexions : c'est lui qui doit autoriser
l'UDP 24567. Les PC des joueurs n'ont rien à ouvrir.

**Windows** : au premier lancement, Windows affiche une alerte « Autoriser
ArenaTPS_Server à communiquer sur les réseaux ». Cocher **Réseaux privés** et autoriser.
Si l'alerte a été refusée, créer la règle à la main, dans un **PowerShell administrateur** :

```powershell
New-NetFirewallRule -DisplayName "Arena TPS (UDP 24567)" -Direction Inbound `
  -Protocol UDP -LocalPort 24567 -Action Allow -Profile Private
```

Pour la retirer après la séance :

```powershell
Remove-NetFirewallRule -DisplayName "Arena TPS (UDP 24567)"
```

**Linux** : `sudo ufw allow 24567/udp` (Ubuntu) ou
`sudo firewall-cmd --add-port=24567/udp` (Fedora), s'il y a un pare-feu.

---

## 8. Tester sur un seul PC

Sans rien exporter, depuis le dossier `front/` :

```bash
godot --headless -- --server --bots 2 --duration 60   # le serveur
godot                                                  # un joueur (autant de fois que voulu)
```

Les joueurs rejoignent `127.0.0.1`. Dans l'éditeur, **Débogage → Personnaliser les
instances de lancement** permet de lancer 3 instances d'un coup, la première avec les
arguments `--headless -- --server`.

---

## 9. Dépannage

| Symptôme | Cause probable et solution |
|---|---|
| « Aucune réponse de … » (après 6 s) | Le **serveur** ne reçoit rien. Dans l'ordre : `ArenaTPS_Server` est-il lancé ? l'adresse est-elle une de celles qu'il affiche ? le pare-feu du PC serveur autorise-t-il l'**UDP 24567** (§7) ? |
| « Versions différentes : le serveur a la X, toi la Y » | Le serveur et le jeu ne viennent pas du même code. Réexporter **tout** en même temps. La version est affichée en bas du menu et au démarrage du serveur. |
| « La partie est pleine (8 joueurs) » | 8 joueurs sont déjà connectés. Attendre qu'une place se libère. |
| « Ce compte est déjà connecté à ce serveur » | Le même compte est déjà dans la partie (deux jeux ouverts avec la même session ?). |
| « La partie se termine… » | Le serveur affiche l'écran de fin : réessayer dans quelques secondes. |
| « Le port 24567 est déjà utilisé » | Un autre serveur tourne déjà sur ce PC. Le fermer, ou lancer avec `--port 24568` (et `adresse:24568` côté joueur). |
| `ping` passe mais le jeu ne se connecte pas | Le ping utilise ICMP, le jeu de l'**UDP** : c'est le port 24567/UDP qu'il faut autoriser, pas le ping. |
| Le joueur distant saccade ou « glisse » | Normal au-delà de ~150 ms de latence. Vérifier la qualité du réseau ; en Wi-Fi, préférer le câble. |
| Les personnages se téléportent | Perte de paquets importante. Le jeu rattrape au-delà de 6 m d'écart, c'est le comportement prévu. |

**Journal réseau.** Chaque étape (ouverture du serveur, tentative de connexion,
joueur accepté ou refusé) est écrite dans la console du serveur et dans `reseau.log`
(sur chaque machine) ; côté joueur, le chemin s'affiche avec l'erreur :

- Windows : `%APPDATA%\Godot\app_userdata\Arena TPS\reseau.log`
- Linux : `~/.local/share/godot/app_userdata/Arena TPS/reseau.log`

Si le serveur n'affiche **aucune ligne « connexion du pair »** alors qu'un joueur a
essayé, les paquets n'arrivent pas jusqu'à lui : c'est le pare-feu du PC serveur (ou
le réseau).

---

## 10. Limites actuelles et suite

Ce qui est volontairement simple pour l'instant :

- **Pas d'anti-triche** : chaque jeu annonce ses propres déplacements et impacts.
  Entre camarades ce n'est pas un problème.
- **Pas de rembobinage (lag compensation)** : on touche ce qu'on voit à l'écran, avec
  le décalage de la latence. Acceptable en dessous de ~100 ms.
- **Pas de reconnexion automatique** : si la connexion tombe, il faut revenir au menu
  et rejoindre à nouveau (la partie en cours reste rejoignable).
- **Pas encore de back** : le serveur fonctionne en mode LAN (`LanLink`). Il accepte
  tout le monde et écrit seulement dans sa console les évènements `player.match` et
  `match.finished` qu'il enverra au back.

La suite :

1. **Brancher le back** : le serveur s'enregistrera auprès de la Server List, vérifiera
   le ticket d'accès de chaque joueur et enverra les résultats (`match.finished`). Une
   partie sera lancée par un groupe (party) depuis le menu, au lieu du chef du salon.
2. **Serveur entièrement autoritaire** : la simulation passera côté serveur, qui
   recevra seulement les commandes des joueurs (`PlayerCommands`, déjà séparées des
   entrées depuis le début) et renverra l'état du monde.
