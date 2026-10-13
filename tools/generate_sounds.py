"""Génère les effets sonores du jeu (WAV mono 16 bits, 44,1 kHz) par synthèse.

Aucun son externe : tout est calculé (bruit filtré, oscillateurs, enveloppes),
ce qui évite toute question de licence.

Usage (depuis la racine du dépôt) :
    python3 tools/generate_sounds.py
Dépendances : numpy
"""
from pathlib import Path
import wave

import numpy as np

RATE = 44100
OUT = Path(__file__).resolve().parent.parent / "front" / "assets" / "sounds"
rng = np.random.default_rng(7)


# ------------------------------------------------------------------ briques de base

def t_axis(duration):
    return np.arange(int(RATE * duration)) / RATE


def noise(duration):
    return rng.uniform(-1, 1, int(RATE * duration))


def lowpass(x, cutoff):
    """Filtre passe-bas du 1er ordre (appliqué deux fois pour une pente plus raide)."""
    a = np.exp(-2 * np.pi * cutoff / RATE)
    for _ in range(2):
        y = np.empty_like(x)
        acc = 0.0
        for i, v in enumerate(x):
            acc = (1 - a) * v + a * acc
            y[i] = acc
        x = y
    return x


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def env(duration, attack, decay_rate):
    t = t_axis(duration)
    e = np.exp(-t * decay_rate)
    n_att = max(int(RATE * attack), 1)
    e[:n_att] *= np.linspace(0, 1, n_att)
    return e


def sine(freq, duration, sweep_to=None):
    t = t_axis(duration)
    if sweep_to is None:
        f = np.full_like(t, freq)
    else:
        f = np.geomspace(freq, sweep_to, len(t))
    return np.sin(2 * np.pi * np.cumsum(f) / RATE)


def pad(x, duration):
    out = np.zeros(int(RATE * duration))
    out[: len(x)] += x[: len(out)]
    return out


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def place(x, offset, total):
    out = np.zeros(int(RATE * total))
    start = int(RATE * offset)
    end = min(start + len(x), len(out))
    out[start:end] += x[: end - start]
    return out


def save(name, x, peak=0.9):
    x = np.tanh(x * 1.2)                        # légère saturation, plus "punchy"
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    fade = min(int(RATE * 0.01), len(x))
    x[-fade:] *= np.linspace(1, 0, fade)
    data = (x * 32767).astype(np.int16)
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())
    print(f"  {name}.wav  ({len(x) / RATE:.2f} s)")


# ------------------------------------------------------------------ sons

def shot_shotgun():
    d = 0.6
    blast = lowpass(noise(d), 2200) * env(d, 0.001, 9)
    crack = highpass(noise(0.05), 3000) * env(0.05, 0.0005, 70) * 0.6
    boom = sine(110, d, 45) * env(d, 0.002, 11) * 0.9
    return mix(blast, crack, boom)


def shot_smg():
    d = 0.16
    body = lowpass(noise(d), 3800) * env(d, 0.0005, 32)
    crack = highpass(noise(0.03), 4000) * env(0.03, 0.0003, 120) * 0.7
    thump = sine(170, d, 80) * env(d, 0.001, 38) * 0.6
    return mix(body, crack, thump)


def shot_sniper():
    d = 1.3
    crack = highpass(noise(0.08), 2500) * env(0.08, 0.0003, 55)
    body = lowpass(noise(d), 1600) * env(d, 0.001, 6) * 0.8
    boom = sine(80, d, 35) * env(d, 0.002, 5) * 1.0
    echo = place(lowpass(noise(0.5), 900) * env(0.5, 0.02, 7) * 0.25, 0.18, d)
    return mix(crack, body, boom, echo)


def hit_marker():
    d = 0.07
    return (sine(2100, d) * 0.6 + sine(3150, d) * 0.4) * env(d, 0.001, 55)


def kill_confirm():
    d = 0.32
    a = sine(1320, d) * env(d, 0.002, 14)
    b = place(sine(1980, d) * env(d, 0.002, 12), 0.07, d + 0.07)
    return mix(a, b) * 0.8


def reload():
    def click(freq, length=0.05):
        c = highpass(noise(length), 1500) * env(length, 0.0005, 90)
        return mix(c, sine(freq, length) * env(length, 0.0005, 70) * 0.5)
    total = 0.75
    slide = lowpass(noise(0.18), 2500) * env(0.18, 0.04, 14) * 0.35
    return mix(
        place(click(900), 0.0, total),
        place(slide, 0.08, total),
        place(click(650, 0.07), 0.42, total),
        place(click(1200, 0.04), 0.58, total),
    )


def ability_shield():
    d = 0.8
    hum = (sine(140, d, 280) + sine(282, d, 560) * 0.5) * env(d, 0.08, 3.5)
    shimmer = highpass(noise(d), 5000) * env(d, 0.15, 5) * 0.15
    return mix(hum, shimmer)


def ability_dash():
    d = 0.45
    n = noise(d)
    lo = lowpass(n, 900)
    hi = lowpass(n, 4500)
    sweep = np.linspace(0, 1, len(n))
    whoosh = (lo * (1 - sweep) + hi * sweep) * np.sin(np.pi * sweep) ** 1.5
    return whoosh * 1.3


def ability_pierce():
    d = 0.55
    zap = sine(220, d, 1800) * env(d, 0.01, 4)
    buzz = np.sign(sine(60, d)) * env(d, 0.01, 6) * 0.15
    return mix(zap * 0.8, lowpass(buzz, 2000))


def spawn():
    d = 0.9
    a = sine(330, d, 660) * env(d, 0.05, 4)
    b = sine(495, d, 990) * env(d, 0.12, 4) * 0.5
    air = lowpass(noise(d), 3000) * env(d, 0.2, 5) * 0.12
    return mix(a, b, air) * 0.7


def deflect():
    d = 0.35
    ping = (sine(1700, d) + sine(2550, d) * 0.6 + sine(4100, d) * 0.3) * env(d, 0.001, 16)
    return ping * 0.7


def ui_click():
    d = 0.05
    return mix(sine(1500, d, 900) * env(d, 0.001, 70), highpass(noise(0.01), 3000) * 0.3) * 0.8


def ui_open():
    d = 0.22
    return sine(500, d, 900) * env(d, 0.005, 16) * 0.7


def ui_close():
    d = 0.22
    return sine(900, d, 500) * env(d, 0.005, 16) * 0.7


SOUNDS = {
    "shot_shotgun": shot_shotgun,
    "shot_smg": shot_smg,
    "shot_sniper": shot_sniper,
    "hit": hit_marker,
    "kill": kill_confirm,
    "reload": reload,
    "ability_shield": ability_shield,
    "ability_dash": ability_dash,
    "ability_pierce": ability_pierce,
    "spawn": spawn,
    "deflect": deflect,
    "ui_click": ui_click,
    "ui_open": ui_open,
    "ui_close": ui_close,
}

if __name__ == "__main__":
    print(f"Sons générés dans {OUT} :")
    for name, fn in SOUNDS.items():
        save(name, fn())
