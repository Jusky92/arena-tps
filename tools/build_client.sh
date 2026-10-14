#!/usr/bin/env bash
# Exporte le client lourd du jeu (Windows et/ou Linux).
#
# Usage, depuis la racine du dépôt :
#     tools/build_client.sh            # Windows (le cas courant : le .exe pour Elian)
#     tools/build_client.sh linux      # Linux
#     tools/build_client.sh macos      # macOS (Mac Intel et Apple Silicon, non signé par Apple)
#     tools/build_client.sh all        # les trois
#
# Prérequis : Godot 4.7.2 accessible en ligne de commande (variable GODOT ou
# commande `godot`), et les modèles d'exportation installés une fois dans l'éditeur
# (Éditeur → Gérer les modèles d'exportation…).
set -euo pipefail

GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-windows}"

if ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "Godot introuvable. Installe-le ou indique son chemin :" >&2
	echo "    GODOT=/chemin/vers/Godot_v4.7.2-stable_linux.x86_64 tools/build_client.sh" >&2
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
	windows) export_one "Windows" "$ROOT/build/windows/ArenaTPS.exe" ;;
	linux)   export_one "Linux"   "$ROOT/build/linux/ArenaTPS.x86_64" ;;
	macos)   export_one "macOS"   "$ROOT/build/macos/ArenaTPS.zip" ;;
	all)
		export_one "Windows" "$ROOT/build/windows/ArenaTPS.exe"
		export_one "Linux"   "$ROOT/build/linux/ArenaTPS.x86_64"
		export_one "macOS"   "$ROOT/build/macos/ArenaTPS.zip"
		;;
	*)
		echo "Cible inconnue : $TARGET (attendu : windows, linux, macos ou all)" >&2
		exit 1
		;;
esac

echo
echo "Terminé. Envoie le fichier à ton camarade : il n'a rien d'autre à installer."
echo "Pour jouer ensemble, voir docs/RESEAU.md."
