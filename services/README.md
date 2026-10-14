# Services

Les micro-services et les bases de données ne sont **pas dans ce dépôt** : ils sont dans le
dépôt séparé **`TPSArena_backend`** (responsable : Elian), récupéré à côté de celui-ci, dans
`../../backend/`. Son `README.md` explique comment lancer la stack (Docker Compose).

Le jeu s'y connecte par le BFF (HTTP, port 8000) et le service temps réel (WebSocket,
port 8005) ; le serveur de jeu dédié, par la Server List (port 8002). Voir
[docs/LANCER.md](../docs/LANCER.md), section 7.
