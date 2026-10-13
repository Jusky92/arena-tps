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


# --------------------------------------------------------------------------- matériaux japonais


def wood_planks(size: int = 512) -> None:
    """Planches de bois verticales (échoppes, poutres, passerelles). Albedo clair à teinter."""
    planks = 8
    cell = size // planks
    grain = RNG.standard_normal((size, size))
    acc = np.zeros_like(grain)
    for d in range(-20, 21):                       # fibres étirées verticalement
        acc += np.roll(grain, d, axis=0)
    fibre = normalize(acc)
    rings = normalize(np.sin(np.arange(size)[None, :] / 2.3 + fibre * 6.0))
    tone = np.repeat(np.kron(RNG.uniform(-0.07, 0.07, planks), np.ones(cell))[None, :], size, axis=0)
    gap = np.repeat((((np.arange(size) / cell) % 1.0) < 0.035)[None, :].astype(float), size, axis=0)
    knots = np.clip((noise(size, 0.8) - 0.86) * 7, 0, 1)

    gray = 0.62 + (fibre - 0.5) * 0.14 + (rings - 0.5) * 0.10 + tone - gap * 0.4 - knots * 0.3
    albedo = gray_to_rgb(gray, (1.0, 0.86, 0.66))
    height = (rings - 0.5) * 0.3 - gap * 1.0 - knots * 0.4
    rough = 0.78 + (rings - 0.5) * 0.12 + gap * 0.15
    write_set("wood_planks", albedo, blur(height, 1), rough, 4.0)


def roof_tile(size: int = 512) -> None:
    """Tuiles japonaises (kawara) : rangées de demi-cylindres et nervures."""
    rows, cols = 6, 10
    yy, xx = np.mgrid[0:size, 0:size].astype(float)
    row_h, col_w = size / rows, size / cols
    in_row = (yy % row_h) / row_h
    in_col = (xx % col_w) / col_w
    # Galbe de la tuile (bombé) + recouvrement entre rangées.
    barrel = np.sqrt(np.clip(1.0 - (in_col * 2 - 1) ** 2, 0, 1))
    overlap = np.clip(1.0 - in_row * 2.2, 0, 1)
    step = np.clip((in_row - 0.88) * 8, 0, 1)
    grain = noise(size, 1.8)
    moss = np.clip((noise(size, 1.2) - 0.74) * 5, 0, 1)

    height = barrel * 0.8 + overlap * 0.4 - step * 0.8
    gray = 0.40 + barrel * 0.22 + (grain - 0.5) * 0.10 - step * 0.25
    albedo = gray_to_rgb(gray, (0.86, 0.93, 1.0))              # gris-bleu ardoise
    albedo = albedo * (1 - moss[..., None] * 0.5) + np.array([0.28, 0.34, 0.18]) * moss[..., None] * 0.5
    rough = 0.72 + (grain - 0.5) * 0.15 + moss * 0.2
    write_set("roof_tile", albedo, blur(height, 1), rough, 6.0)


def plaster_wall(size: int = 512) -> None:
    """Mur blanc de temple (shikkui) : enduit à la chaux, légères coulures."""
    coarse = noise(size, 2.4)
    fine = noise(size, 0.7)
    trowel = normalize(blur(noise(size, 1.4), 3))
    stains = np.clip((noise(size, 1.8) - 0.7) * 3, 0, 1)
    gray = 0.86 + (coarse - 0.5) * 0.06 + (fine - 0.5) * 0.04 + (trowel - 0.5) * 0.05 - stains * 0.12
    albedo = gray_to_rgb(gray, (1.0, 0.99, 0.95))
    height = (coarse - 0.5) * 0.4 + (fine - 0.5) * 0.2
    rough = 0.92 + (fine - 0.5) * 0.08
    write_set("plaster_wall", albedo, height, rough, 3.0)


def stone_paver(size: int = 512) -> None:
    """Dallage de pierre irrégulier (allées de temple, places)."""
    cells = 4                                                  # 4 divise 512 : pas de reste
    cell = size // cells
    tones = np.kron(RNG.uniform(-0.07, 0.07, (cells, cells)), np.ones((cell, cell)))
    joints = grid_lines(size, cells, width=5.0, soft=2.0)
    wobble = (noise(size, 2.0) - 0.5) * 6.0                    # joints non rectilignes
    joints = np.clip(joints + wobble * joints, 0, 1)
    speck = noise(size, 0.25)
    base = noise(size, 1.9)
    gray = 0.56 + tones + (base - 0.5) * 0.12 + (speck - 0.5) * 0.07 - joints * 0.35
    albedo = gray_to_rgb(gray, (1.0, 0.97, 0.92))
    height = -joints * 1.0 + (base - 0.5) * 0.25
    rough = 0.82 + (base - 0.5) * 0.15 + joints * 0.1
    write_set("stone_paver", albedo, blur(height, 1), rough, 5.0)


def gravel_zen(size: int = 512) -> None:
    """Gravier blanc ratissé du jardin sec (karesansui) : sillons ondulés."""
    y = np.arange(size)[:, None] * np.ones((1, size))
    x = np.ones((size, 1)) * np.arange(size)[None, :]
    wave = np.sin((y + np.sin(x / size * np.pi * 2) * 14.0) / size * np.pi * 2 * 10)
    furrows = normalize(wave)
    grain = blur(noise(size, 0.25), 1)
    stones = np.clip((noise(size, 0.2) - 0.78) * 6, 0, 1)
    gray = 0.80 + (furrows - 0.5) * 0.10 + (grain - 0.5) * 0.12 - stones * 0.08
    albedo = gray_to_rgb(gray, (1.0, 0.98, 0.93))
    height = (furrows - 0.5) * 0.7 + grain * 0.5 + stones * 0.4
    rough = 0.95 - stones * 0.1
    write_set("gravel_zen", albedo, height, rough, 5.0)


def shoji(size: int = 512) -> None:
    """Cloison de papier washi sur cadre de bois (portes, fenêtres éclairées)."""
    fibres = blur(noise(size, 0.4), 1)
    paper = 0.92 + (fibres - 0.5) * 0.08
    frame = np.maximum(grid_lines(size, 4, width=7.0, soft=1.0), grid_lines(size, 2, width=11.0, soft=1.0))
    border = np.zeros((size, size))
    b = max(size // 42, 3)
    border[:b, :] = border[-b:, :] = border[:, :b] = border[:, -b:] = 1.0
    wood = np.clip(frame + border, 0, 1)
    albedo = gray_to_rgb(paper, (1.0, 0.97, 0.88))
    albedo = albedo * (1 - wood[..., None]) + np.array([0.26, 0.15, 0.09]) * wood[..., None]
    height = wood * 0.8 + (fibres - 0.5) * 0.1
    rough = 0.9 - wood * 0.2
    write_set("shoji", albedo, blur(height, 1), rough, 4.0)


def tatami(size: int = 512) -> None:
    """Nattes de tatami : paille tressée, bordure sombre."""
    mats = 2
    cell = size // mats
    yy, xx = np.mgrid[0:size, 0:size]
    in_y, in_x = (yy % cell) / cell, (xx % cell) / cell
    # Tressage : lignes fines alternées selon la natte.
    weave_h = (np.sin(yy / 2.0) * 0.5 + 0.5)
    weave_v = (np.sin(xx / 2.0) * 0.5 + 0.5)
    checker = ((yy // cell + xx // cell) % 2) == 0
    weave = np.where(checker, weave_h, weave_v)
    border = ((in_y < 0.04) | (in_y > 0.96) | (in_x < 0.04) | (in_x > 0.96)).astype(float)
    dirt = noise(size, 2.0)
    gray = 0.74 + (weave - 0.5) * 0.10 + (dirt - 0.5) * 0.08
    albedo = gray_to_rgb(gray, (1.0, 0.93, 0.62))
    albedo = albedo * (1 - border[..., None]) + np.array([0.12, 0.14, 0.2]) * border[..., None]
    height = (weave - 0.5) * 0.5 - border * 0.6
    rough = 0.9 - border * 0.25 + (dirt - 0.5) * 0.1
    write_set("tatami", albedo, height, rough, 3.0)


def water_pond(size: int = 512) -> None:
    """Surface d'eau du bassin : rides douces, albedo sombre (le reflet vient du matériau)."""
    ripples = normalize(np.sin(noise(size, 2.6) * 18.0) + np.sin(noise(size, 1.8) * 12.0))
    gray = 0.16 + (ripples - 0.5) * 0.06
    albedo = gray_to_rgb(gray, (0.55, 0.95, 0.9))
    height = (ripples - 0.5) * 0.6
    rough = 0.08 + (ripples - 0.5) * 0.05
    write_set("water_pond", albedo, blur(height, 1), rough, 3.0)


def shutter(size: int = 512) -> None:
    """Rideau métallique de boutique (ruelle) : lames horizontales, tags effacés."""
    slats = np.repeat((np.sin(np.arange(size) / size * np.pi * 2 * 26) * 0.5 + 0.5)[:, None], size, axis=1)
    wear = noise(size, 2.2)
    scuff = np.clip((noise(size, 0.5) - 0.78) * 5, 0, 1)
    gray = 0.44 + (slats - 0.5) * 0.22 + (wear - 0.5) * 0.10 + scuff * 0.1
    albedo = gray_to_rgb(gray, (0.98, 0.99, 1.0))
    height = (slats - 0.5) * 1.0
    rough = 0.55 + (wear - 0.5) * 0.2
    write_set("shutter", albedo, height, rough, 6.0)


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
    # Matériaux du thème japonais.
    wood_planks()
    roof_tile()
    plaster_wall()
    stone_paver()
    gravel_zen()
    shoji()
    tatami()
    water_pond()
    shutter()
    print("Terminé.")


if __name__ == "__main__":
    main()
