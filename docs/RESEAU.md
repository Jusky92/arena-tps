# Jouer en ligne — guide complet

Comment jouer à **Arena TPS** à plusieurs, avec **un PC qui héberge** (le serveur) et
les autres qui le rejoignent avec le **client lourd** (le jeu exporté en `.exe`).

Sommaire :

1. [Comment ça marche](#1-comment-ça-marche)
2. [Exporter le client lourd](#2-exporter-le-client-lourd)
3. [Jouer sur le même réseau (le plus simple)](#3-jouer-sur-le-même-réseau)
4. [Jouer par Internet avec Tailscale (recommandé)](#4-jouer-par-internet-avec-tailscale)
5. [Jouer par Internet en ouvrant un port](#5-jouer-par-internet-en-ouvrant-un-port)
6. [Pare-feu Windows](#6-pare-feu-windows)
7. [Dépannage](#7-dépannage)
8. [Limites actuelles et suite](#8-limites-actuelles-et-suite)

---

## 1. Comment ça marche

Le PC qui héberge joue **en même temps qu'il sert** : c'est ce qu'on appelle un
**serveur d'écoute**. Il n'y a rien d'autre à installer que le jeu.

```
   PC de Julien (hôte)                       PC d'Elian (client)
 ┌───────────────────────┐   UDP 24567    ┌───────────────────────┐
 │  Jeu + serveur ENet   │ <────────────> │   Jeu (client lourd)  │
 │  • arbitre la vie     │                │  • simule son joueur  │
 │  • compte les scores  │                │  • envoie son état    │
 │  • gère le chrono     │                │  • signale ses tirs   │
 │  • fait jouer les bots│                │                       │
 └───────────────────────┘                └───────────────────────┘
```

Qui décide de quoi :

| Élément | Qui décide | Pourquoi |
|---|---|---|
| Déplacement de mon personnage | ma machine | aucune latence : le jeu reste nerveux |
| Impacts de mes tirs | ma machine (le tireur) | je tire sur ce que je vois à l'écran |
| Points de vie, éliminations, score | **l'hôte** | une seule version de la vérité |
| Chronomètre, réapparitions, fin de match | **l'hôte** | tout le monde reste synchronisé |
| Bots | **l'hôte** | il les fait jouer et diffuse leur position |

Les positions circulent **20 fois par seconde** en UDP non fiable : si un paquet se
perd, le suivant arrive 50 ms plus tard, inutile de le renvoyer. Les évènements
importants (dégâts, morts, score) passent, eux, en mode fiable.

Tout est dans `front/scripts/net/net.gd`, avec la partie dans `front/scripts/game.gd`
(section « Partie en ligne »).

---

## 2. Exporter le client lourd

À faire **sur le PC de Julien**, puis envoyer le fichier obtenu à Elian.

### Une seule fois : installer les modèles d'export

Dans Godot : **Éditeur → Gérer les modèles d'exportation… → Télécharger et installer**.
C'est environ 1 Go, à ne faire qu'une fois par version de Godot.

### À chaque version du jeu

1. **Projet → Exporter…**
2. Sélectionner le préréglage **Windows** (déjà présent dans `front/export_presets.cfg`).
3. **Exporter le projet…**, choisir le dossier `build/windows/`, nom `ArenaTPS.exe`.
4. Décocher « Exporter avec le débogage ».

On obtient **un seul fichier `ArenaTPS.exe`** d'environ 125 Mo : les ressources sont
embarquées dedans. Elian le met où il veut et double-clique, il n'y a rien à installer.

En ligne de commande, depuis le dossier `front/` :

```bash
godot --headless --export-release "Windows" ../build/windows/ArenaTPS.exe
```

> Les deux PC doivent avoir **exactement la même version du jeu**. Après chaque
> modification, il faut réexporter et renvoyer le `.exe`.

---

## 3. Jouer sur le même réseau

Si les deux PC sont sur le même Wi-Fi ou le même câble (salle de cours, appartement) :

1. **Julien** lance le jeu, se connecte, puis **JOUER → HÉBERGER UNE PARTIE**.
2. L'écran du salon affiche une ou plusieurs adresses du type `192.168.1.20:24567`.
   Un bouton **COPIER** permet de l'envoyer par message.
3. **Elian** lance son `ArenaTPS.exe`, se connecte, colle l'adresse dans le champ
   de la page JOUER, puis **REJOINDRE**.
4. Il apparaît dans le salon de Julien. Julien règle les bots et la durée, puis
   **LANCER LA PARTIE** : le jeu démarre chez tout le monde.

---

## 4. Jouer par Internet avec Tailscale

C'est la méthode **recommandée** quand vous n'êtes pas sur le même réseau : elle ne
demande aucun réglage de box, et ça marche même derrière un CGNAT (fibre 4G, certaines
offres opérateur).

Tailscale crée un petit réseau privé chiffré entre vos deux PC : chacun reçoit une
adresse fixe en `100.x.y.z`, comme si vous étiez sur le même Wi-Fi.

1. Les deux installent **Tailscale** (gratuit pour un usage personnel) :
   <https://tailscale.com/download>
2. Chacun se connecte avec le **même compte** (ou l'un invite l'autre dans son réseau).
3. Julien récupère son adresse Tailscale : icône Tailscale → son nom de machine,
   ou dans un terminal `tailscale ip -4` (par exemple `100.112.8.31`).
4. Julien héberge comme en LAN, Elian saisit `100.112.8.31` dans le champ d'adresse.

**ZeroTier** fonctionne exactement pareil si vous préférez.

---

## 5. Jouer par Internet en ouvrant un port

Sans logiciel tiers, mais il faut accéder à la box de Julien.

1. Trouver l'adresse IP locale du PC hôte (affichée dans le salon, ex. `192.168.1.20`).
2. Dans l'interface de la box (Freebox, Livebox, SFR…), section
   **Redirection de ports / NAT / Port forwarding**, créer une règle :

   | Champ | Valeur |
   |---|---|
   | Protocole | **UDP** |
   | Port externe | `24567` |
   | Port interne | `24567` |
   | IP de destination | l'IP locale du PC hôte |

3. Récupérer l'**IP publique** de la box : <https://www.monip.org> ou en tapant
   « mon ip » dans un moteur de recherche.
4. Elian saisit cette IP publique dans le champ d'adresse.

> Attention : l'IP publique change souvent chez les particuliers. Et si l'opérateur
> utilise du CGNAT (IP partagée), l'ouverture de port ne fonctionnera pas :
> passer par Tailscale.
>
> Une redirection de port expose un service à Internet : ne la laissez active que
> le temps de jouer.

---

## 6. Pare-feu Windows

À la première partie hébergée, Windows affiche une alerte « Autoriser Godot /
ArenaTPS à communiquer sur les réseaux ». Cocher **Réseaux privés** et autoriser.

Si l'alerte a été refusée, créer la règle à la main, dans un **PowerShell administrateur** :

```powershell
New-NetFirewallRule -DisplayName "Arena TPS (UDP 24567)" -Direction Inbound `
  -Protocol UDP -LocalPort 24567 -Action Allow -Profile Private
```

Pour la retirer après la séance :

```powershell
Remove-NetFirewallRule -DisplayName "Arena TPS (UDP 24567)"
```

---

## 7. Dépannage

| Symptôme | Cause probable et solution |
|---|---|
| « Aucune réponse de … » (après 6 s) | Le PC de l'hôte est joignable ou non, mais le **jeu** ne reçoit rien. Dans l'ordre : l'hôte est-il dans le salon ? l'adresse est-elle celle de **son** salon ? son pare-feu autorise-t-il l'**UDP 24567** (§6) ? |
| « Versions différentes : l'hôte a la X, toi la Y » | Les deux exécutables ne viennent pas du même code. Réexporter **les deux** (Windows et Linux) en même temps. La version est affichée en bas du menu. |
| Elian est sous Linux et héberge | Sur Linux, ouvrir le port s'il y a un pare-feu : `sudo ufw allow 24567/udp` (Ubuntu) ou `sudo firewall-cmd --add-port=24567/udp` (Fedora). |
| « Impossible de joindre l'hôte » | Mauvaise adresse, hôte pas encore dans le salon, pare-feu, ou port non ouvert. Vérifier dans l'ordre : l'hôte est bien dans le salon → l'adresse est exacte → le pare-feu autorise → `ping` passe. |
| `ping` passe mais le jeu ne se connecte pas | Le ping utilise ICMP, le jeu de l'**UDP** : c'est le port 24567/UDP qu'il faut autoriser, pas le ping. |
| « Le port 24567 est déjà utilisé » | Une autre instance du jeu tourne déjà. La fermer, ou héberger sur un autre port (`adresse:24568` côté client). |
| « La partie a déjà commencé » | On ne peut rejoindre que depuis le salon. Attendre la fin du match. |
| Le joueur distant saccade ou « glisse » | Normal au-delà de ~150 ms de latence. Vérifier la qualité du réseau ; en Wi-Fi, préférer le câble. |
| Les personnages se téléportent | Perte de paquets importante. Le jeu rattrape au-delà de 6 m d'écart, c'est le comportement prévu. |
| Comportements incohérents entre les deux PC | Versions différentes du jeu : réexporter le `.exe` et le renvoyer. |

**Journal réseau.** Chaque étape (ouverture du serveur, tentative de connexion,
joueur accepté ou refusé) est écrite dans `reseau.log`, dont le chemin s'affiche
avec l'erreur :

- Windows : `%APPDATA%\Godot\app_userdata\Arena TPS\reseau.log`
- Linux : `~/.local/share/godot/app_userdata/Arena TPS/reseau.log`

Si l'hôte n'a **aucune ligne « un joueur se connecte »** alors que le client a essayé,
les paquets n'arrivent pas jusqu'au jeu : c'est le pare-feu de l'hôte (ou le réseau).

Pour vérifier qu'un port UDP est bien joignable depuis l'extérieur :

```powershell
Test-NetConnection -ComputerName 100.112.8.31 -Port 24567 -InformationLevel Detailed
```

(`Test-NetConnection` teste le TCP ; pour l'UDP, le plus simple reste d'essayer de
rejoindre la partie.)

---

## 8. Limites actuelles et suite

Ce qui est volontairement simple pour l'instant :

- **Pas d'anti-triche** : chaque client annonce ses propres impacts. Entre camarades
  ce n'est pas un problème ; dans un vrai jeu, le serveur revérifie tout.
- **Pas de rembobinage (lag compensation)** : on touche ce qu'on voit à l'écran, avec
  le décalage de la latence. Acceptable en dessous de ~100 ms.
- **Pas de reconnexion** : si la connexion tombe, il faut revenir au menu.
- **L'hôte a un léger avantage** : latence nulle pour lui.

La suite prévue avec Elian, c'est le **serveur de jeu dédié** (Godot en mode headless) :
la simulation entière passerait côté serveur, qui recevrait seulement les commandes des
joueurs (`PlayerCommands`, déjà séparées des entrées depuis le début) et renverrait
l'état du monde. Les services (authentification, liste des serveurs, statistiques)
fourniraient alors le ticket de connexion et recevraient l'évènement `match.finished`.
