# Services

Les micro-services d'Arena TPS ne sont pas dans ce dépôt : ils sont dans le dépôt séparé **`TPSArena_backend`** (responsable : Elian), récupéré à côté de celui-ci, dans `../../backend/` (son `README.md` explique comment lancer la stack avec Docker Compose).

| Service | Rôle |
|---|---|
| Auth | Comptes, vérification de l'e-mail, connexion, jetons |
| Social | Amis, groupes, invitations, classes enregistrées (`/loadouts/me`) |
| Server List | Serveurs de jeu : enregistrement, battements de cœur, réservations, tickets d'accès, résultats des parties |
| Stats | Statistiques, XP, niveaux, succès, classements |
| Real-time | Présence et notifications en direct (WebSocket) |
| BFF | Point d'entrée unique du jeu (HTTP) |

Le jeu ne parle qu'au **BFF** et à **Real-time** ; le serveur de jeu dédié parle seulement à la **Server List**. Pour lancer le back avec le jeu, voir [docs/LANCER.md](../docs/LANCER.md), section 7.

Les mots de passe et paramètres sensibles vont dans un fichier `.env` (non versionné), accompagné d'un `.env.example` sans valeurs réelles.
