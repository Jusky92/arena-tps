# Services

Ce dossier accueillera les micro-services et la configuration des bases de données (responsable : Elian).

Organisation suggérée, un sous-dossier par service :

```
services/
├── <nom-du-service-1>/
├── <nom-du-service-2>/
├── <nom-du-service-3>/
└── docker-compose.yml
```

Les mots de passe et paramètres sensibles vont dans un fichier `.env` (non versionné). Un fichier `.env.example` sans valeurs réelles doit être fourni pour indiquer les variables attendues.
