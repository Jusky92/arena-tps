#!/usr/bin/env bash
# Lance le serveur de jeu dédié (Linux) branché sur le vrai back (mode Server List).
#
# Usage, depuis n'importe où :
#     tools/lancer_serveur.sh                  # réglages par défaut
#     tools/lancer_serveur.sh --port 24568     # options en plus, passées au serveur
#
# Ce qu'il fait :
#   - prend l'exécutable exporté par tools/build_server.sh (../server/linux/) ;
#   - lit GAME_SERVER_SECRET dans le .env du back (../../backend/.env) ;
#   - annonce aux joueurs l'adresse IP actuelle de ce PC (celle de la route par défaut).
#
# Chaque réglage peut être changé par une variable d'environnement :
#     SERVEUR=…  ENV_BACK=…  SERVERLIST_URL=…  ADRESSE_PUBLIQUE=…
#     ADRESSE_PUBLIQUE=100.101.102.103 tools/lancer_serveur.sh      # ex. adresse Tailscale
#
# Prérequis : la stack du back est lancée (docker compose up -d dans backend/).
# Ctrl+C arrête le serveur.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVEUR="${SERVEUR:-$ROOT/../server/linux/TPSArena_Server.x86_64}"
ENV_BACK="${ENV_BACK:-$ROOT/../../backend/.env}"
SERVERLIST_URL="${SERVERLIST_URL:-http://localhost:8002}"

if [ ! -x "$SERVEUR" ]; then
	echo "Serveur introuvable : $SERVEUR" >&2
	echo "Exporte-le d'abord : tools/build_server.sh linux (ou indique son chemin avec SERVEUR=…)." >&2
	exit 1
fi

if [ -z "${GAME_SERVER_SECRET:-}" ]; then
	if [ ! -f "$ENV_BACK" ]; then
		echo "Fichier .env du back introuvable : $ENV_BACK (ou indique son chemin avec ENV_BACK=…)." >&2
		exit 1
	fi
	GAME_SERVER_SECRET="$(grep -E '^GAME_SERVER_SECRET=' "$ENV_BACK" | cut -d= -f2- || true)"
	if [ -z "$GAME_SERVER_SECRET" ]; then
		echo "GAME_SERVER_SECRET absent de $ENV_BACK." >&2
		exit 1
	fi
fi
export GAME_SERVER_SECRET

# Adresse de ce PC sur le réseau : celle qu'il utilise pour sortir (Wi-Fi ou Ethernet,
# jamais un pont Docker). Elle change d'un réseau à l'autre : on la recalcule à chaque lancement.
# Toutes les adresses IPv4 réelles de ce PC (sans boucle locale ni interfaces virtuelles).
ADRESSES="$(ip -4 -o addr show scope global 2>/dev/null \
	| awk '$2 !~ /^(docker|br-|veth|virbr|vboxnet|vmnet|lxc|lxd|podman|cni|tailscale)/ {split($4, a, "/"); print $2 " " a[1]}')"
if [ -z "${ADRESSE_PUBLIQUE:-}" ]; then
	ADRESSE_PUBLIQUE="$(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -n1)"
	if [ -z "$ADRESSE_PUBLIQUE" ]; then
		echo "Impossible de trouver l'adresse IP de ce PC : indique-la avec ADRESSE_PUBLIQUE=…" >&2
		exit 1
	fi
	if [ "$(printf '%s\n' "$ADRESSES" | grep -c .)" -gt 1 ]; then
		echo "Ce PC a plusieurs adresses (une par connexion) :"
		printf '%s\n' "$ADRESSES" | sed 's/^/    /'
		echo "Choisie : $ADRESSE_PUBLIQUE (connexion par défaut). Les joueurs doivent être sur le même"
		echo "réseau qu'elle ; sinon relance avec ADRESSE_PUBLIQUE=<une autre adresse> $0"
		echo
	fi
fi

if pgrep -f "TPSArena_Server" >/dev/null; then
	echo "Un serveur de jeu tourne déjà sur ce PC :" >&2
	pgrep -af "TPSArena_Server" >&2
	echo "Arrête-le d'abord (pkill -f TPSArena_Server), ou lance celui-ci sur un autre port (--port 24568)." >&2
	if [[ " $* " != *" --port "* && " $* " != *" --port="* ]]; then
		exit 1
	fi
fi

if ! curl -s --max-time 3 -o /dev/null "$SERVERLIST_URL/health"; then
	echo "Attention : la Server List ne répond pas sur $SERVERLIST_URL (stack du back lancée ?)." >&2
fi

echo "Serveur        : $SERVEUR"
echo "Server List    : $SERVERLIST_URL"
echo "Adresse donnée aux joueurs : $ADRESSE_PUBLIQUE"
echo "Les joueurs saisissent « $ADRESSE_PUBLIQUE » comme adresse du back."
echo

cd "$(dirname "$SERVEUR")"
exec "./$(basename "$SERVEUR")" --serverlist-url "$SERVERLIST_URL" --public-address "$ADRESSE_PUBLIQUE" "$@"
