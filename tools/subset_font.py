"""Allège la police japonaise en ne gardant que les caractères utilisés par le jeu.

Noto Sans JP complet pèse environ 4,5 Mo (plus de 17 000 glyphes). Le jeu n'affiche
qu'une centaine de caractères (enseignes, lanternes, distributeurs) : on produit donc
un sous-ensemble de quelques dizaines de kilo-octets, versionnable sans alourdir le dépôt.

Le script lit tous les scripts GDScript du projet, relève les caractères japonais et
les signes utilisés, puis découpe la police d'origine.

Usage (depuis la racine du dépôt) :
    python3 tools/subset_font.py chemin/vers/NotoSansJP-Bold.otf
Dépendances : fonttools  (pip install fonttools)
"""

import sys
import unicodedata
from pathlib import Path

from fontTools import subset

ROOT = Path(__file__).resolve().parent.parent
SCRIPTS = ROOT / "front" / "scripts"
OUT = ROOT / "front" / "assets" / "fonts" / "NotoSansJP-Bold.otf"

# Toujours inclus : chiffres, lettres et ponctuation courants (les enseignes mêlent
# souvent latin et japonais), plus quelques symboles.
ALWAYS = set(
    "0123456789"
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    "abcdefghijklmnopqrstuvwxyz"
    " .,:;!?·-–—()[]/%+°'\"&#@*"
    "àâäéèêëîïôöùûüçÀÂÄÉÈÊËÎÏÔÖÙÛÜÇ"
    "￥、。「」々〜"
)


def is_japanese(ch: str) -> bool:
    """Vrai pour un kanji, un hiragana, un katakana ou une ponctuation japonaise."""
    code = ord(ch)
    return (
        0x3000 <= code <= 0x303F       # ponctuation CJK
        or 0x3040 <= code <= 0x309F    # hiragana
        or 0x30A0 <= code <= 0x30FF    # katakana
        or 0x4E00 <= code <= 0x9FFF    # kanji
        or 0xFF00 <= code <= 0xFFEF    # formes pleine largeur (￥, ！…)
    )


def collect() -> set:
    """Caractères japonais trouvés dans les scripts du jeu."""
    found = set()
    for path in SCRIPTS.rglob("*.gd"):
        for ch in path.read_text(encoding="utf-8"):
            if is_japanese(ch):
                found.add(ch)
    return found


def main() -> None:
    if len(sys.argv) < 2:
        print(__doc__)
        raise SystemExit(1)
    source = Path(sys.argv[1])
    chars = collect()
    print(f"{len(chars)} caractères japonais trouvés dans {SCRIPTS} :")
    for ch in sorted(chars):
        print(f"  {ch}  U+{ord(ch):04X}  {unicodedata.name(ch, '?')}")

    text = "".join(sorted(chars | ALWAYS))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    subset.main([
        str(source),
        f"--text={text}",
        f"--output-file={OUT}",
        "--layout-features=*",
        "--name-IDs=*",
        "--notdef-outline",
        "--recalc-bounds",
    ])
    size_kb = OUT.stat().st_size / 1024
    print(f"\nÉcrit : {OUT}  ({size_kb:.0f} Ko pour {len(text)} caractères)")


if __name__ == "__main__":
    main()
