# Lancer le serveur et les clients — pas à pas

Ce guide explique comment lancer **le serveur dédié** (`ArenaTPS_Server`) sur un PC
Windows ou Linux, puis **le jeu** (`ArenaTPS`) sur le PC de chaque joueur.
Pour les questions de réseau (Internet, Tailscale, box, dépannage), voir
[RESEAU.md](RESEAU.md).

Sommaire :

1. [Ce qu'il faut savoir avant](#1-ce-quil-faut-savoir-avant)
2. [Obtenir les exécutables](#2-obtenir-les-exécutables)
3. [Lancer le serveur sous Linux](#3-lancer-le-serveur-sous-linux)
4. [Lancer le serveur sous Windows](#4-lancer-le-serveur-sous-windows)
5. [Lancer un client (joueur)](#5-lancer-un-client-joueur)
6. [Jouer une partie](#6-jouer-une-partie)
7. [Sans exporter : depuis le code source](#7-sans-exporter--depuis-le-code-source)
8. [Si ça ne marche pas](#8-si-ça-ne-marche-pas)

---

## 1. Ce qu'il faut savoir avant

- **Un seul PC lance le serveur.** Le serveur ne joue pas et n'ouvre pas de fenêtre :
  il affiche seulement du texte dans un terminal. Ce PC peut **aussi** lancer le jeu
  pour jouer, comme les autres.
- **Tout le monde doit avoir la même version** (serveur et jeux exportés depuis le même
  code). Sinon le serveur refuse la connexion avec « Versions différentes ».
- Le serveur écoute sur le port **UDP 24567**. C'est le pare-feu **du PC serveur** qui
  doit l'autoriser. Les PC des joueurs n'ont rien à ouvrir.
- 8 joueurs au maximum par partie.

---

## 2. Obtenir les exécutables

Si quelqu'un vous a déjà envoyé les fichiers, passez à l'étape 3, 4 ou 5.

Sinon, sur un PC qui a le code et **Godot 4.7.2** :

1. Une seule fois, installer les modèles d'export : dans Godot,
   **Éditeur → Gérer les modèles d'exportation… → Télécharger et installer**.
2. Exporter, depuis la racine du dépôt `client/` :

   ```bash
   tools/build_server.sh all    # le serveur, Windows + Linux
   tools/build_client.sh all    # le jeu, Windows + Linux
   ```

   Sous Windows, ces scripts se lancent depuis **Git Bash** ou **WSL**. Sans terminal,
   passer par Godot : **Projet → Exporter…**, choisir le préréglage
   (« Serveur Windows », « Serveur Linux », « Windows » ou « Linux »),
   **Exporter le projet…** en décochant « Exporter avec le débogage ».

3. On obtient :

   | Fichier | Rôle | Pour qui |
   |---|---|---|
   | `TPSArena_Jeu/server/linux/ArenaTPS_Server.x86_64` | serveur Linux | le PC serveur |
   | `TPSArena_Jeu/server/windows/ArenaTPS_Server.exe` **et** `ArenaTPS_Server.console.exe` | serveur Windows (garder les deux fichiers ensemble) | le PC serveur |
   | `client/build/linux/ArenaTPS.x86_64` | jeu Linux | chaque joueur |
   | `client/build/windows/ArenaTPS.exe` | jeu Windows | chaque joueur |

   Chaque fichier contient tout (ressources incluses) : rien d'autre à installer.

---

## 3. Lancer le serveur sous Linux

1. **Copier** `ArenaTPS_Server.x86_64` sur le PC serveur, dans le dossier de votre choix.

2. **Ouvrir un terminal** dans ce dossier et rendre le fichier exécutable (une seule fois) :

   ```bash
   chmod +x ArenaTPS_Server.x86_64
   ```

3. **Ouvrir le port** s'il y a un pare-feu (une seule fois) :

   ```bash
   sudo ufw allow 24567/udp                                    # Ubuntu, Debian avec ufw
   sudo firewall-cmd --permanent --add-port=24567/udp && sudo firewall-cmd --reload   # Fedora
   ```

   Sans pare-feu actif (cas courant sur Debian), il n'y a rien à faire.

4. **Lancer le serveur** :

   ```bash
   ./ArenaTPS_Server.x86_64
   ```

   Avec des options (toutes facultatives) :

   ```bash
   ./ArenaTPS_Server.x86_64 --port 24567 --bots 2 --duration 180 --name "Arena TPS"
   ```

5. **Noter les adresses affichées**, par exemple :

   ```
   === Arena TPS — serveur dédié (version 0.6.0-alpha) ===
   Les joueurs se connectent avec REJOINDRE et une de ces adresses :
       192.168.1.20:24567
   ```

   C'est cette adresse que les joueurs taperont (étape 5). Une adresse en `100.x.y.z`
   est une adresse Tailscale (jeu par Internet, voir RESEAU.md).

6. **Laisser le terminal ouvert** tant qu'on joue. **Ctrl+C** arrête le serveur.

   Pour qu'il continue après la fermeture du terminal (serveur distant en SSH, par
   exemple) :

   ```bash
   nohup ./ArenaTPS_Server.x86_64 > serveur.log 2>&1 &   # lancer en arrière-plan
   tail -f serveur.log                                    # suivre ce qu'il affiche
   pkill -f ArenaTPS_Server                               # l'arrêter
   ```

---

## 4. Lancer le serveur sous Windows

1. **Copier les deux fichiers** `ArenaTPS_Server.exe` et `ArenaTPS_Server.console.exe`
   dans le **même dossier** du PC serveur. Le second affiche la console et a besoin du
   premier.

   > ⚠️ Ne pas double-cliquer sur `ArenaTPS_Server.exe` : le serveur tournerait
   > **sans aucune fenêtre**, invisible. Il faudrait alors l'arrêter depuis le
   > Gestionnaire des tâches. Toujours utiliser `ArenaTPS_Server.console.exe`.

2. **Lancer le serveur.** Au choix :
   - double-cliquer sur `ArenaTPS_Server.console.exe` (réglages par défaut) ;
   - ou, pour passer des options, ouvrir le dossier dans l'Explorateur, taper
     `powershell` dans la barre d'adresse puis Entrée, et lancer :

     ```powershell
     .\ArenaTPS_Server.console.exe --port 24567 --bots 2 --duration 180
     ```

3. **SmartScreen** (« Windows a protégé votre ordinateur ») peut apparaître au premier
   lancement, car l'exécutable n'est pas signé : **Informations complémentaires →
   Exécuter quand même**.

4. **Autoriser le pare-feu.** Au premier lancement, Windows demande s'il faut autoriser
   ArenaTPS_Server sur le réseau : cocher **Réseaux privés**, puis **Autoriser**.

   Si la fenêtre n'est pas apparue ou a été refusée, ouvrir un **PowerShell en
   administrateur** (clic droit sur le menu Démarrer → Terminal (administrateur)) :

   ```powershell
   New-NetFirewallRule -DisplayName "Arena TPS (UDP 24567)" -Direction Inbound `
     -Protocol UDP -LocalPort 24567 -Action Allow -Profile Private
   ```

   > Si votre connexion Wi-Fi est réglée en réseau **public**, Windows bloque quand
   > même. Passer le réseau en **privé** : Paramètres → Réseau et Internet → Wi-Fi
   > (ou Ethernet) → propriétés de la connexion → **Réseau privé**.

5. **Noter les adresses affichées** dans la console (comme sous Linux, étape 3.5).

6. **Laisser la console ouverte** tant qu'on joue. **Ctrl+C** ou fermer la fenêtre
   arrête le serveur.

---

## 5. Lancer un client (joueur)

À faire sur le PC de **chaque joueur** (y compris le PC serveur, si quelqu'un y joue).

### Windows

1. Copier `ArenaTPS.exe` où vous voulez (Bureau, Documents…).
2. Double-cliquer dessus. Si **SmartScreen** apparaît : **Informations
   complémentaires → Exécuter quand même**.

### Linux

1. Copier `ArenaTPS.x86_64` où vous voulez.
2. Dans un terminal, dans ce dossier :

   ```bash
   chmod +x ArenaTPS.x86_64    # une seule fois
   ./ArenaTPS.x86_64
   ```

   (Ou clic droit → Propriétés → Permissions → « Autoriser l'exécution », puis
   double-clic.)

### Ensuite, pour tout le monde

3. **Se connecter.** Le back-end est encore simulé : n'importe quel identifiant et mot
   de passe sont acceptés. Le pseudo affiché en jeu vient de l'identifiant (la partie
   avant `@` pour une adresse e-mail) : choisissez-en un différent pour chaque joueur.
4. Dans la page **JOUER**, cadre **JOUER EN LIGNE** : taper l'adresse donnée par le
   serveur, par exemple `192.168.1.20` (ajouter `:port` seulement si le serveur a été
   lancé avec un autre port que 24567, ex. `192.168.1.20:24568`).
5. Cliquer **REJOINDRE**. Après quelques secondes, le **salon** s'ouvre. Si une partie
   est déjà en cours, on arrive directement dedans.

L'adresse est retenue pour la prochaine fois.

---

## 6. Jouer une partie

1. Le **premier joueur arrivé dans le salon est le chef** (étiquette « chef »).
2. Le chef règle **les bots** et **la durée**. Les autres voient les réglages changer.
3. Chacun peut **CHANGER DE CLASSE** avant le lancement.
4. Le chef clique **LANCER LA PARTIE** (ou Entrée) : la partie démarre chez tout le monde.
5. À la fin, l'écran de fin s'affiche. **REJOUER** ramène au salon, toujours connecté.
   Le serveur revient au salon une dizaine de secondes après la fin.
6. **Échap → Quitter**, ou **QUITTER LE SALON**, pour se déconnecter.

Si le chef part, le joueur suivant devient chef. Un joueur qui arrive pendant une
partie la rejoint directement.

---

## 7. Sans exporter : depuis le code source

Pour tester pendant le développement, avec **Godot 4.7.2** installé et `godot` dans le
PATH, depuis le dossier `client/front/` :

```bash
# Le serveur (Linux ou Windows, même commande)
godot --headless -- --server --bots 2 --duration 60

# Un client (dans un autre terminal ; répéter pour plusieurs joueurs)
godot
```

Les clients rejoignent `127.0.0.1`. Sous Windows, remplacer `godot` par le chemin de
l'exécutable, par exemple `& "C:\Godot\Godot_v4.7.2-stable_win64.exe" --headless -- --server`.

Dans l'éditeur, on peut tout lancer d'un coup : **Débogage → Personnaliser les
instances de lancement…**, activer plusieurs instances (par exemple 3), et donner à la
première les arguments `--headless -- --server`. F5 lance alors le serveur et deux
clients.

---

## 8. Si ça ne marche pas

| Problème | À vérifier |
|---|---|
| « Aucune réponse de … » | Le serveur est-il lancé ? L'adresse est-elle une de celles **qu'il affiche** ? Le pare-feu **du PC serveur** autorise-t-il l'UDP 24567 ? (Windows : réseau en **privé**.) |
| « Versions différentes » | Réexporter le serveur **et** les jeux depuis le même code, et redistribuer. |
| « Le port 24567 est déjà utilisé » (ou « Couldn't create an ENet host ») | Un serveur tourne déjà sur ce PC, souvent lancé d'un double-clic donc sans fenêtre. Linux : `pgrep -af ArenaTPS_Server` pour le voir, `pkill -f ArenaTPS_Server` pour l'arrêter. Windows : Gestionnaire des tâches. Ou lancer avec `--port 24568`. |
| « La partie est pleine » | 8 joueurs sont déjà là. |
| « Ce compte est déjà connecté » | Le même jeu est ouvert deux fois avec la même session : se reconnecter. |
| Le serveur Linux ne démarre pas (« Permission non accordée ») | Oublié `chmod +x ArenaTPS_Server.x86_64`. |
| Les options (`--port`, `--bots`…) semblent ignorées | Les placer après `--` : `./ArenaTPS_Server.x86_64 -- --port 24568`. Le serveur lit les deux formes. |
| La console Windows se ferme tout de suite | Lancer depuis PowerShell (étape 4.2) pour lire le message d'erreur. |

Plus de détails, et le jeu par Internet : [RESEAU.md](RESEAU.md).
