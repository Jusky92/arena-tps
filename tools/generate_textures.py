"""Génère les textures de la map (béton, métal, conteneurs, rayures de danger...).

Toutes les textures sont "tuilables" (elles se répètent sans raccord visible) et
fabriquées à partir de bruit mathématique : aucun fichier externe, aucun droit d'auteur.

Pour chaque matériau on produit :
  - <nom>_albedo.png     la couleur
  - <nom>_normal.png     le relief (format OpenGL, celui de Godot)
  - <nom>_rough.png      la rugosité (blanc = mat, noir = brillant)

Utilisation (depuis la racine du dépôt) :
    python3 tools/generate_textures.py
Dépendances : numpy, pillow  (pip install numpy pillow)
"""

from pathlib import Path

import numpy as np
from PIL import Image

OUT = Path(__file__).resolve().parent.parent / "front" / "textures"
RNG = np.random.default_rng(42)  # graine fixe : mêmes textures à chaque génération


# --------------------------------------------------------------------------- outils


def noise(size: int, beta: float = 2.0, seed: int | None = None) -> np.ndarray:
    """Bruit fractal périodique (tuilable) dans [0, 1].
    beta élevé = grosses taches douces, beta faible = grain fin."""
    rng = np.random.default_rng(seed) if seed is not None else RNG
    white = rng.standard_normal((size, size))
    fx = np.fft.fftfreq(size)[:, None]
    fy = np.fft.fftfreq(size)[None, :]
    f = np.sqrt(fx**2 + fy**2)
    f[0, 0] = 1.0
    spectrum = np.fft.fft2(white) / f ** (beta / 2.0)
    spectrum[0, 0] = 0.0
    out = np.real(np.fft.ifft2(spectrum))
    return normalize(out)


def normalize(a: np.ndarray) -> np.ndarray:
    a = a - a.min()
    m = a.max()
    return a / m if m > 0 else a


def blur(a: np.ndarray, radius: int) -> np.ndarray:
    """Flou périodique simple (moyenne glissante, en boucle sur les bords)."""
    out = a.copy()
    for axis in (0, 1):
        acc = np.zeros_like(out)
        for d in range(-radius, radius + 1):
            acc += np.roll(out, d, axis=axis)
        out = acc / (2 * radius + 1)
    return out


def grid_lines(size: int, cells: int, width: float, soft: float = 1.5) -> np.ndarray:
    """1 sur les joints d'une grille de cells x cells, 0 ailleurs (bords adoucis)."""
    period = size / cells
    coords = np.arange(size)
    d = np.abs(((coords + period / 2) % period) - period / 2)  # distance au joint le plus proche
    line = np.clip(1.0 - (d - width / 2) / soft, 0.0, 1.0)
    return np.maximum(line[:, None], line[None, :])


def dots(size: int, cells: int, radius: float, offset=(0.5, 0.5), jitter: float = 0.0) -> np.ndarray:
    """Petits disques en relief (boulons, trous) répétés sur une grille, profil arrondi."""
    period = size / cells
    yy, xx = np.mgrid[0:size, 0:size].astype(float)
    cx = ((xx / period - offset[0] + 0.5) % 1.0 - 0.5) * period
    cy = ((yy / period - offset[1] + 0.5) % 1.0 - 0.5) * period
    d = np.sqrt(cx**2 + cy**2)
    return np.clip(1.0 - (d / radius) ** 2, 0.0, 1.0)


def height_to_normal(h: np.ndarray, strength: float) -> np.ndarray:
    """Convertit une carte de hauteur en normal map (convention OpenGL, Y vers le haut)."""
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5
    nx = -dx * strength
    ny = dy * strength
    nz = np.ones_like(h)
    length = np.sqrt(nx**2 + ny**2 + nz**2)
    n = np.stack([nx / length, ny / length, nz / length], axis=-1)
    return (n * 0.5 + 0.5)


def save_rgb(name: str, rgb: np.ndarray) -> None:
    img = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8), "RGB")
    img.save(OUT / f"{name}.png", optimize=True)


def save_gray(name: str, g: np.ndarray) -> None:
    img = Image.fromarray((np.clip(g, 0, 1) * 255).astype(np.uint8), "L")
    img.save(OUT / f"{name}.png", optimize=True)


def gray_to_rgb(g: np.ndarray, tint=(1.0, 1.0, 1.0)) -> np.ndarray:
    return np.stack([g * tint[0], g * tint[1], g * tint[2]], axis=-1)


def write_set(name: str, albedo: np.ndarray, height: np.ndarray, rough: np.ndarray, strength: float) -> None:
    save_rgb(f"{name}_albedo", albedo)
    save_rgb(f"{name}_normal", height_to_normal(height, strength))
    save_gray(f"{name}_rough", rough)
    print(f"  {name}")


# --------------------------------------------------------------------------- matériaux


def concrete_floor(size: int = 1024) -> None:
    """Dalles de béton (4 x 4 par texture) avec joints, taches et petits trous."""
    base = noise(size, 2.2) * 0.55 + noise(size, 1.2) * 0.45
    stains = noise(size, 3.0)
    pits = (noise(size, 0.6) > 0.9).astype(float) * 0.6
    joints = grid_lines(size, 4, width=3.0)
    # Chaque dalle a une teinte légèrement différente.
    cell = size // 4
    tiles = np.kron(RNG.uniform(-0.05, 0.05, (4, 4)), np.ones((cell, cell)))

    gray = 0.50 + (base - 0.5) * 0.18 + (stains - 0.5) * 0.12 + tiles - pits * 0.08 - joints * 0.22
    albedo = gray_to_rgb(gray, (1.0, 0.99, 0.96))
    height = base * 0.4 - joints * 1.0 - pits * 0.6
    rough = 0.82 + (stains - 0.5) * 0.2 - joints * 0.1
    write_set("concrete_floor", albedo, blur(height, 1), rough, 6.0)


def concrete_wall(size: int = 512) -> None:
    """Béton brut architectural : trous de banche alignés et lignes de coffrage."""
    base = noise(size, 2.0) * 0.6 + noise(size, 1.0) * 0.4
    streaks = blur(noise(size, 1.5), 2)
    streaks = np.roll(np.repeat(streaks.mean(axis=0, keepdims=True), size, axis=0), 0, axis=0)
    holes = dots(size, 2, radius=size * 0.018, offset=(0.25, 0.25))
    pour_lines = np.zeros(size)
    pour_lines[::size // 2] = 1.0
    pour = np.clip(blur(pour_lines[:, None] * np.ones((1, size)), 1) * 3, 0, 1)

    gray = 0.62 + (base - 0.5) * 0.14 + (streaks - 0.5) * 0.08 - holes * 0.35 - pour * 0.08
    albedo = gray_to_rgb(gray, (0.99, 0.99, 1.0))
    height = base * 0.3 - holes * 1.2 - pour * 0.3
    rough = 0.88 - holes * 0.2 + (base - 0.5) * 0.1
    write_set("concrete_wall", albedo, height, rough, 4.0)


def metal_panel(size: int = 512) -> None:
    """Panneaux métalliques boulonnés (2 x 2), brossés, légèrement usés. Albedo neutre pour être teinté."""
    # Métal brossé : bruit étiré horizontalement (flou uniquement le long des lignes).
    streaks = RNG.standard_normal((size, size))
    acc = np.zeros_like(streaks)
    for d in range(-24, 25):
        acc += np.roll(streaks, d, axis=1)
    brushed = normalize(acc)
    seams = grid_lines(size, 2, width=4.0, soft=1.0)
    bolts = np.maximum.reduce([
        dots(size, 2, radius=7, offset=(o1, o2)) for o1 in (0.06, 0.94) for o2 in (0.06, 0.94)
    ])
    wear = noise(size, 2.6)
    scratches = (noise(size, 0.4) > 0.9).astype(float) * 0.5

    gray = 0.70 + (brushed - 0.5) * 0.08 + (wear - 0.5) * 0.10 - seams * 0.35 + bolts * 0.08 + scratches * 0.08
    albedo = gray_to_rgb(gray)
    height = -seams * 1.0 + bolts * 0.8 + brushed * 0.05
    rough = 0.42 + (wear - 0.5) * 0.25 + seams * 0.3 - scratches * 0.15
    write_set("metal_panel", albedo, height, rough, 5.0)


def container(size: int = 512) -> None:
    """Tôle ondulée de conteneur maritime, salissures en bas, rouille. Albedo neutre (teinté par matériau)."""
    x = np.arange(size) / size
    ribs_count = 8
    phase = (x * ribs_count) % 1.0
    # Profil trapézoïdal des ondulations.
    profile = np.clip(np.abs(phase - 0.5) * 4.0 - 0.5, 0.0, 1.0)
    ribs = np.repeat(profile[None, :], size, axis=0)

    grime = noise(size, 2.8)
    rust = np.clip((noise(size, 1.6) - 0.72) * 4.0, 0, 1)
    paint = noise(size, 1.0)

    gray = 0.78 + (paint - 0.5) * 0.06 - (grime - 0.5) * 0.12 - ribs * 0.06
    albedo = gray_to_rgb(gray)
    albedo = albedo * (1 - rust[..., None] * 0.55) + rust[..., None] * np.array([0.42, 0.22, 0.12]) * 0.55
    height = ribs * 1.0 + rust * 0.15
    rough = 0.55 + rust * 0.35 + (grime - 0.5) * 0.15
    write_set("container", albedo, blur(height, 1), rough, 7.0)


def hazard(size: int = 512) -> None:
    """Bandes de danger jaunes et noires, peinture écaillée."""
    yy, xx = np.mgrid[0:size, 0:size].astype(float)
    stripes = (((xx + yy) / (size / 4)) % 1.0) < 0.5
    chips = np.clip((noise(size, 1.2) - 0.7) * 5.0, 0, 1)
    dirt = noise(size, 2.5)
    yellow = np.array([0.95, 0.72, 0.08])
    black = np.array([0.06, 0.06, 0.06])
    bare = np.array([0.45, 0.45, 0.47])
    albedo = np.where(stripes[..., None], yellow, black)
    albedo = albedo * (1 - chips[..., None]) + bare * chips[..., None]
    albedo = albedo * (0.85 + dirt[..., None] * 0.15)
    height = -chips * 0.5 + dirt * 0.1
    rough = 0.6 + chips * 0.2
    write_set("hazard", albedo, height, rough, 3.0)


def grating(size: int = 512) -> None:
    """Caillebotis métallique (passerelles, rampes)."""
    bars_major = grid_lines(size, 16, width=6.0, soft=1.0)
    bars_minor = np.repeat((((np.arange(size) / (size / 32)) % 1.0) < 0.18)[None, :].astype(float), size, axis=0)
    metal = np.maximum(bars_major, bars_minor * 0.8)
    wear = noise(size, 2.2)
    gray = 0.10 + metal * (0.48 + (wear - 0.5) * 0.15)
    albedo = gray_to_rgb(gray, (0.97, 0.98, 1.0))
    height = metal
    rough = 0.9 - metal * 0.45
    write_set("grating", albedo, blur(height, 1), rough, 6.0)


def asphalt(size: int = 512) -> None:
    """Asphalte sombre avec gravillons et marquage usé (pour les allées extérieures)."""
    grain = blur(noise(size, 0.3), 1)
    big = noise(size, 2.4)
    stones = np.clip((noise(size, 0.2) - 0.75) * 6, 0, 1)
    gray = 0.20 + (grain - 0.5) * 0.08 + (big - 0.5) * 0.06 + stones * 0.12
    albedo = gray_to_rgb(gray, (1.0, 1.0, 1.03))
    height = grain * 0.4 + stones * 0.6
    rough = 0.9 - stones * 0.15
    write_set("asphalt", albedo, height, rough, 4.0)


def plaza_tiles(size: int = 512) -> None:
    """Grandes dalles de pierre claire (place), joints fins."""
    cell = size // 4
    tones = np.kron(RNG.uniform(-0.05, 0.05, (4, 4)), np.ones((cell, cell)))
    base = noise(size, 1.8)
    speck = noise(size, 0.2)
    joints = grid_lines(size, 4, width=2.0, soft=1.0)
    gray = 0.70 + tones + (base - 0.5) * 0.08 + (speck - 0.5) * 0.06 - joints * 0.3
    albedo = gray_to_rgb(gray, (1.0, 0.96, 0.9))
    height = -joints + base * 0.15
    rough = 0.7 + (base - 0.5) * 0.2 + joints * 0.2
    write_set("plaza_tiles", albedo, height, rough, 4.0)


def facade(size: int = 512) -> None:
    """Façade d'immeuble (fond de décor) : grille de fenêtres, certaines allumées."""
    floors, cols = 8, 8
    cell_h, cell_w = size // floors, size // cols
    yy, xx = np.mgrid[0:size, 0:size]
    in_y = (yy % cell_h) / cell_h
    in_x = (xx % cell_w) / cell_w
    window = ((in_y > 0.18) & (in_y < 0.82) & (in_x > 0.12) & (in_x < 0.88)).astype(float)
    lit_cells = RNG.uniform(0, 1, (floors, cols)) > 0.62
    warmth = RNG.uniform(0.0, 1.0, (floors, cols))
    lit = np.kron(lit_cells.astype(float), np.ones((cell_h, cell_w))) * window
    warm = np.kron(warmth, np.ones((cell_h, cell_w)))
    wall = noise(size, 2.0)

    wall_rgb = gray_to_rgb(0.42 + (wall - 0.5) * 0.06)
    glass = np.array([0.16, 0.2, 0.26])
    lamp = np.stack([0.75 * np.ones_like(warm), 0.62 + warm * 0.08, 0.42 + warm * 0.2], axis=-1)
    window_rgb = glass * (1 - lit[..., None]) + lamp * lit[..., None]
    albedo = wall_rgb * (1 - window[..., None]) + window_rgb * window[..., None]
    height = -window * 0.6
    rough = 0.85 - window * 0.75
    write_set("facade", albedo, height, rough, 3.0)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    print(f"Génération des textures dans {OUT}")
    concrete_floor()
    concrete_wall()
    metal_panel()
    container()
    hazard()
    grating()
    asphalt()
    plaza_tiles()
    facade()
    print("Terminé.")


if __name__ == "__main__":
    main()
