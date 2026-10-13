"""Génère les masques des combinaisons cyberpunk des personnages humains.

Le corps Quaternius (CC0) est livré en sous-vêtements. Pour l'habiller, on calcule,
dans l'espace des coordonnées de texture (UV), quelles zones du corps sont :
  R : combinaison (tout sauf la tête)          G : zone secondaire (avant-bras, mollets, pieds)
  B : gants et semelles (mains, doigts, orteils) A : liserés néon (jonctions entre zones)
La zone de chaque pixel est déterminée par les os qui l'influencent (poids de
skinning du modèle, interpolés) : le résultat épouse exactement l'anatomie.

Un shader (front/shaders/cyber_suit.gdshader) colore ensuite chaque zone selon la classe.

Utilisation (depuis la racine du dépôt) : python3 tools/generate_suit_masks.py
Dépendances : numpy, pillow
"""

import json
import struct
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent / "front" / "assets" / "characters" / "quaternius"
SIZE = 1024

HEAD = {"Head", "neck_01"}
SECONDARY = {"lowerarm_l", "lowerarm_r", "calf_l", "calf_r", "foot_l", "foot_r"}
DARK_PREFIX = ("hand_", "index_", "middle_", "pinky_", "ring_", "thumb_", "ball_")

COMPONENT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
COUNT = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def read_accessor(gltf: dict, blob: bytes, index: int) -> np.ndarray:
    acc = gltf["accessors"][index]
    view = gltf["bufferViews"][acc["bufferView"]]
    dtype = COMPONENT[acc["componentType"]]
    n = COUNT[acc["type"]]
    offset = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = view.get("byteStride", 0)
    item = np.dtype(dtype).itemsize * n
    if stride and stride != item:
        raw = np.frombuffer(blob, dtype=np.uint8, count=stride * acc["count"], offset=offset)
        raw = raw.reshape(acc["count"], stride)[:, :item].copy()
        data = raw.view(dtype).reshape(acc["count"], n)
    else:
        data = np.frombuffer(blob, dtype=dtype, count=acc["count"] * n, offset=offset).reshape(acc["count"], n)
    if acc.get("normalized") and dtype in (np.uint8, np.uint16):
        data = data.astype(np.float32) / np.iinfo(dtype).max
    return data


def build_mask(gltf_path: Path, out_path: Path) -> None:
    gltf = json.loads(gltf_path.read_text())
    blob = (gltf_path.parent / gltf["buffers"][0]["uri"]).read_bytes()
    skin = gltf["skins"][0]
    joint_names = [gltf["nodes"][j]["name"] for j in skin["joints"]]

    # Le maillage principal du corps est le plus gros (les autres : yeux, sourcils).
    body = max(gltf["meshes"], key=lambda m: gltf["accessors"][m["primitives"][0]["attributes"]["POSITION"]]["count"])
    prim = body["primitives"][0]
    uv = read_accessor(gltf, blob, prim["attributes"]["TEXCOORD_0"]).astype(np.float32)
    joints = read_accessor(gltf, blob, prim["attributes"]["JOINTS_0"]).astype(np.int32)
    weights = read_accessor(gltf, blob, prim["attributes"]["WEIGHTS_0"]).astype(np.float32)
    tris = read_accessor(gltf, blob, prim["indices"]).reshape(-1, 3)

    # Pour chaque sommet : part d'influence de la tête, de la zone secondaire et des mains/pieds.
    groups = [HEAD, SECONDARY]
    fields = np.zeros((len(uv), 3), dtype=np.float32)
    for k in range(4):
        names = [joint_names[j] for j in joints[:, k]]
        w = weights[:, k]
        fields[:, 0] += w * np.array([n in HEAD for n in names])
        fields[:, 1] += w * np.array([n in SECONDARY for n in names])
        fields[:, 2] += w * np.array([n.startswith(DARK_PREFIX) for n in names])

    # Rasterisation dans l'espace UV avec interpolation des poids à l'intérieur de
    # chaque triangle : les frontières entre zones sont lisses (pas d'escalier).
    reg = np.full((SIZE, SIZE), 255, dtype=np.uint8)
    pix = uv * SIZE
    for a, b, c in tris:
        p0, p1, p2 = pix[a], pix[b], pix[c]
        x0, y0 = np.floor(np.minimum(np.minimum(p0, p1), p2)).astype(int)
        x1, y1 = np.ceil(np.maximum(np.maximum(p0, p1), p2)).astype(int)
        x0, y0 = max(x0, 0), max(y0, 0)
        x1, y1 = min(x1, SIZE - 1), min(y1, SIZE - 1)
        if x1 < x0 or y1 < y0:
            continue
        ys, xs = np.mgrid[y0:y1 + 1, x0:x1 + 1]
        px, py = xs + 0.5, ys + 0.5
        den = (p1[1] - p2[1]) * (p0[0] - p2[0]) + (p2[0] - p1[0]) * (p0[1] - p2[1])
        if abs(den) < 1e-9:
            continue
        l0 = ((p1[1] - p2[1]) * (px - p2[0]) + (p2[0] - p1[0]) * (py - p2[1])) / den
        l1 = ((p2[1] - p0[1]) * (px - p2[0]) + (p0[0] - p2[0]) * (py - p2[1])) / den
        l2 = 1.0 - l0 - l1
        inside = (l0 >= -0.01) & (l1 >= -0.01) & (l2 >= -0.01)
        if not inside.any():
            continue
        f = l0[..., None] * fields[a] + l1[..., None] * fields[b] + l2[..., None] * fields[c]
        r = np.where(f[..., 0] > 0.5, 0, np.where(f[..., 2] > 0.5, 3, np.where(f[..., 1] > 0.5, 2, 1)))
        sub = reg[y0:y1 + 1, x0:x1 + 1]
        sub[inside] = r[inside]

    covered = reg != 255
    # Liserés néon : pixels couverts dont un voisin couvert appartient à une autre zone
    # (on ignore la peau côté visage pour n'avoir qu'un col lumineux).
    edge = np.zeros_like(covered)
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        other = np.roll(np.roll(reg, dy, 0), dx, 1)
        other_cov = np.roll(np.roll(covered, dy, 0), dx, 1)
        edge |= covered & other_cov & (other != reg) & (reg != 0)
    edge_img = Image.fromarray((edge * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3))

    # Le fond (hors triangles) prend la zone voisine pour éviter les bavures aux bords.
    reg_filled = Image.fromarray(np.where(covered, reg, 1).astype(np.uint8))
    reg_f = np.array(reg_filled)
    r_channel = (reg_f != 0).astype(np.uint8) * 255
    g_channel = (reg_f == 2).astype(np.uint8) * 255
    b_channel = (reg_f == 3).astype(np.uint8) * 255
    a_channel = np.array(edge_img)

    soft = lambda ch: np.array(Image.fromarray(ch).filter(ImageFilter.GaussianBlur(1.2)))
    rgba = np.stack([soft(r_channel), soft(g_channel), soft(b_channel), soft(a_channel)], axis=-1)
    Image.fromarray(rgba, "RGBA").save(out_path, optimize=True)
    counts = np.bincount(reg[covered].ravel(), minlength=4)
    print(f"  {out_path.name} : peau {counts[0]}, combinaison {counts[1]}, secondaire {counts[2]}, sombre {counts[3]} px")


def main() -> None:
    print("Génération des masques de combinaison")
    build_mask(ROOT / "base" / "Superhero_Male_FullBody.gltf", ROOT / "textures" / "suit_mask_male.png")
    build_mask(ROOT / "base" / "Superhero_Female_FullBody.gltf", ROOT / "textures" / "suit_mask_female.png")


if __name__ == "__main__":
    main()
