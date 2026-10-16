#!/usr/bin/env bash
# Exporte le serveur dédié (Windows et/ou Linux), sans fenêtre ni son.
# Même projet Godot que le jeu : seuls les préréglages d'export changent
# ("Serveur Windows" / "Serveur Linux", option Dedicated Server).
#
# Usage, depuis la racine du dépôt :
#     tools/build_server.sh            # Windows (par défaut)
#     tools/build_server.sh linux      # Linux
#     tools/build_server.sh all        # les deux
#
# Les fichiers vont dans TPSArena_Jeu/server/ (à côté de ce dépôt).
# Prérequis : comme tools/build_client.sh (Godot 4.7.2 + modèles d'exportation).
set -euo pipefail

GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(cd "$ROOT/.." && pwd)/server"
TARGET="${1:-windows}"

if ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "Godot introuvable. Installe-le ou indique son chemin :" >&2
	echo "    GODOT=/chemin/vers/Godot_v4.7.2-stable_linux.x86_64 tools/build_server.sh" >&2
	exit 1
fi

export_one() {
	local preset="$1" output="$2"
	mkdir -p "$(dirname "$output")"
	echo "→ Export $preset"
	"$GODOT" --headless --path "$ROOT/front" --export-release "$preset" "$output"
	echo "   $(du -h "$output" | cut -f1)  $output"
}

case "$TARGET" in
	windows) export_one "Serveur Windows" "$OUT/windows/TPSArena_Server.exe" ;;
	linux)   export_one "Serveur Linux"   "$OUT/linux/TPSArena_Server.x86_64" ;;
	all)
		export_one "Serveur Windows" "$OUT/windows/TPSArena_Server.exe"
		export_one "Serveur Linux"   "$OUT/linux/TPSArena_Server.x86_64"
		;;
	*)
		echo "Cible inconnue : $TARGET (attendu : windows, linux ou all)" >&2
		exit 1
		;;
esac

echo
echo "Terminé. Sur le PC serveur, lance TPSArena_Server (sous Windows : TPSArena_Server.console.exe"
echo "pour voir la console). Options : --port 24567 --bots 2 --duration 180"
echo "Les joueurs le rejoignent avec REJOINDRE. Voir docs/RESEAU.md."
