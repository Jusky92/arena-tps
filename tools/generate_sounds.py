"""Génère les effets sonores du jeu (WAV mono 16 bits, 44,1 kHz) par synthèse.

Aucun son externe : tout est calculé (bruit filtré, oscillateurs, enveloppes,
petite réverbération), ce qui évite toute question de licence. Les sons sont
pensés « jeu d'action » (Call of Duty, Fortnite) : une attaque très sèche pour
le punch, un corps grave, une queue courte. Les sons joués souvent (tirs, pas,
impacts) existent en plusieurs variantes (`_2`, `_3`…) que le jeu tire au hasard.

Pour remplacer un son par un vrai enregistrement libre de droits (CC0), voir
front/assets/sounds/LISEZMOI.md (dossier custom/, aucun code à changer).

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


def bandpass(x, low, high):
    return highpass(lowpass(x, high), low)


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


def saw(freq, duration, sweep_to=None):
    """Dent de scie adoucie (somme de quelques harmoniques)."""
    return sum(sine(freq * k, duration, None if sweep_to is None else sweep_to * k) / k for k in range(1, 7))


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


def room(x, size=0.06, decay=0.45, wet=0.22, tail=0.5):
    """Petite réverbération : quelques échos rapprochés et étouffés (ruelle, béton)."""
    out = pad(x, len(x) / RATE + tail)
    dry = out.copy()
    for i, delay in enumerate([size, size * 1.37, size * 1.91, size * 2.63]):
        echo = lowpass(place(dry, delay, len(dry) / RATE), 3500 - i * 600)
        out += echo * wet * (decay ** i)
    return out


def metallic(freqs, duration, decay):
    """Partiels inharmoniques : cloche, tôle, lame."""
    return sum(sine(f, duration) * env(duration, 0.0005, decay * (1 + i * 0.35)) / (1 + i * 0.5)
               for i, f in enumerate(freqs))


def save(name, x, peak=0.9):
    x = np.tanh(x * 1.3)                        # saturation douce : plus de « punch »
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


# ------------------------------------------------------------------ tirs
# Recette commune : claquement très court (aigus), corps (bruit filtré), coup
# grave (sinus qui descend), mécanique, puis une queue qui résonne.

def gunshot(v, body_cut, body_decay, punch_hz, punch_decay, tail, crack=1.0, mech=0.3):
    pitch = 1.0 + (v - 1) * 0.06
    d = tail
    click = highpass(noise(0.004), 4000) * 1.4
    snap = highpass(noise(0.04), 3000 * pitch) * env(0.04, 0.0002, 140) * crack
    body = lowpass(noise(d), body_cut * pitch) * env(d, 0.0005, body_decay)
    punch = sine(punch_hz * pitch, d, punch_hz * 0.35) * env(d, 0.001, punch_decay) * 1.2
    clack = bandpass(noise(0.03), 1800, 5200) * env(0.03, 0.0005, 160) * mech
    return room(mix(click, snap, body, punch, place(clack, 0.012, d)), size=0.05, wet=0.18, tail=0.35)


def shot_smg(v=1):
    return gunshot(v, 4200, 30, 190, 40, 0.18, crack=0.9, mech=0.35)


def shot_rifle(v=1):
    """Fusil d'assaut : entre la mitraillette et le fusil de précision, claquement plus grave."""
    return gunshot(v, 3200, 18, 140, 22, 0.35, crack=1.1, mech=0.3)


def shot_shotgun(v=1):
    blast = gunshot(v, 2400, 9, 120, 12, 0.6, crack=1.2, mech=0.2)
    pump = place(mix(bandpass(noise(0.05), 900, 3000) * env(0.05, 0.001, 80),
                     place(bandpass(noise(0.05), 700, 2500) * env(0.05, 0.001, 80), 0.09, 0.15)) * 0.25, 0.4, 0.9)
    return mix(blast, pump)


def shot_sniper(v=1):
    shot = gunshot(v, 1800, 6, 85, 5, 1.2, crack=1.4, mech=0.2)
    echo = place(lowpass(noise(0.6), 900) * env(0.6, 0.03, 6) * 0.3, 0.22, 1.6)
    return mix(shot, echo)


def shot_rocket(v=1):
    d = 0.9
    thump = sine(95, d, 40) * env(d, 0.002, 9) * 1.2
    ignite = highpass(noise(0.08), 2500) * env(0.08, 0.001, 50)
    n = noise(d)
    sweep = np.linspace(0, 1, len(n))
    whoosh = (lowpass(n, 700) * (1 - sweep) + lowpass(n, 3500) * sweep) * np.sin(np.pi * sweep) ** 0.8 * 0.9
    return room(mix(thump, ignite, whoosh), size=0.07, wet=0.2, tail=0.4)


def shot_flame(v=1):
    """Bouffée de flammes : souffle grave et crépitements."""
    d = 0.35
    roar = lowpass(noise(d), 900 + v * 80) * env(d, 0.03, 6)
    crackle = np.zeros(int(RATE * d))
    for _ in range(14):
        pos = rng.integers(0, len(crackle) - 400)
        crackle[pos:pos + 300] += highpass(noise(300 / RATE), 2500) * env(300 / RATE, 0.0002, 600) * rng.uniform(0.3, 1.0)
    return mix(roar * 1.1, crackle * 0.6)


def shot_laser(v=1):
    """« Piou » laser : descente de fréquence, harmoniques et petit souffle."""
    d = 0.28
    f0 = 1900 + v * 120
    zap = (sine(f0, d, 260) + sine(f0 * 1.5, d, 390) * 0.4) * env(d, 0.001, 14)
    buzz = np.sign(sine(f0 / 4, d, 120)) * env(d, 0.001, 22) * 0.15
    air = highpass(noise(0.05), 5000) * env(0.05, 0.0005, 90) * 0.4
    return room(mix(zap, lowpass(buzz, 4000), air), size=0.04, wet=0.25, tail=0.25)


def katana_swing(v=1):
    """Coup de katana : souffle qui balaie + léger chant de la lame."""
    d = 0.3
    n = noise(d)
    sweep = np.linspace(0, 1, len(n))
    whoosh = (lowpass(n, 600) * (1 - sweep) + lowpass(n, 5000 + v * 400) * sweep) * np.sin(np.pi * sweep) ** 2
    shing = place(metallic([3100 + v * 90, 4650, 6900], 0.25, 18) * 0.25, 0.08, d)
    return mix(whoosh * 1.4, shing)


def katana_hit(v=1):
    d = 0.3
    slash = bandpass(noise(0.12), 1200, 6000) * env(0.12, 0.001, 40)
    thud = sine(130, d, 60) * env(d, 0.001, 22) * 0.9
    ring = metallic([2700, 4300, 6100], d, 14) * 0.3
    return mix(slash, thud, ring)


def poop_launch(v=1):
    """Lance-caca : « ploup » cartoon (bulle qui éclate), pas de bruit sale."""
    d = 0.3
    wobble = 1 + 0.08 * np.sin(2 * np.pi * 24 * t_axis(d))
    bloop = np.sin(2 * np.pi * np.cumsum(np.geomspace(380 + v * 20, 130, int(RATE * d)) * wobble) / RATE) * env(d, 0.003, 12)
    pop = highpass(noise(0.015), 2000) * env(0.015, 0.0003, 200) * 0.5
    return mix(bloop, pop)


def poop_splat(v=1):
    """« Splotch » cartoon : bulles graves qui rebondissent et petit gloup."""
    d = 0.5
    wob = 1 + 0.25 * np.sin(2 * np.pi * 18 * t_axis(d))
    squish = np.sin(2 * np.pi * np.cumsum(np.geomspace(220, 90, int(RATE * d)) * wob) / RATE) * env(d, 0.002, 8)
    mud = lowpass(noise(d), 700) * env(d, 0.002, 14) * 0.7
    blips = mix(*(place(sine(f, 0.06, f * 0.7) * env(0.06, 0.002, 50) * 0.35, o, d)
                  for f, o in [(520, 0.12), (430, 0.2), (610, 0.27)]))
    return mix(squish, mud, blips)


# ------------------------------------------------------------------ grenade et explosions

def grenade_throw(v=1):
    d = 0.25
    n = noise(d)
    s = np.linspace(0, 1, len(n))
    return lowpass(n, 2500) * np.sin(np.pi * s) ** 2 * 1.2


def grenade_bounce(v=1):
    d = 0.18
    clink = metallic([1150 + v * 70, 2650, 4100], d, 30)
    knock = lowpass(noise(0.02), 1200) * env(0.02, 0.0005, 150)
    return mix(clink * 0.8, knock)


def explosion(v=1):
    """Grosse explosion : claquement, boum grave, grondement et débris."""
    d = 2.0
    crack = highpass(noise(0.05), 2000) * env(0.05, 0.0003, 60) * 1.2
    boom = sine(70 - v * 5, d, 26) * env(d, 0.003, 3.2) * 1.4
    rumble = lowpass(noise(d), 260) * env(d, 0.01, 2.2) * 1.4
    blast = lowpass(noise(0.6), 2200) * env(0.6, 0.001, 7) * 0.9
    debris = np.zeros(int(RATE * d))
    for _ in range(40):
        pos = rng.integers(int(RATE * 0.15), len(debris) - 800)
        debris[pos:pos + 600] += bandpass(noise(600 / RATE), 1500, 6000) * env(600 / RATE, 0.0003, 300) \
            * rng.uniform(0.05, 0.3) * np.exp(-pos / RATE * 2)
    return room(mix(crack, boom, rumble, blast, debris), size=0.09, wet=0.3, tail=0.6)


# ------------------------------------------------------------------ retours de tir

def hit_marker(v=1):
    """« Tic » de touche, très sec (façon Call of Duty)."""
    d = 0.06
    tick = bandpass(noise(0.012), 2500, 7000) * env(0.012, 0.0002, 300)
    tone = (sine(2600, d) * 0.5 + sine(3900, d) * 0.3) * env(d, 0.0005, 70)
    return mix(tick, tone)


def headshot(v=1):
    """Tir à la tête : « ting » métallique brillant + craquement (façon Fortnite)."""
    d = 0.55
    ting = metallic([2850, 4280, 6650, 8800], d, 7) * 1.0
    crunch = bandpass(noise(0.05), 1500, 6000) * env(0.05, 0.0005, 70) * 0.6
    low = sine(240, 0.12, 120) * env(0.12, 0.001, 35) * 0.5
    return room(mix(ting, crunch, low), size=0.03, wet=0.2, tail=0.3)


def kill_confirm(v=1):
    """Élimination : deux notes qui montent et un souffle."""
    d = 0.42
    a = sine(1180, d) * env(d, 0.002, 12)
    b = place((sine(1770, d) + sine(3540, d) * 0.2) * env(d, 0.002, 10), 0.075, d + 0.075)
    whoosh = lowpass(noise(0.25), 3000) * np.sin(np.pi * np.linspace(0, 1, int(RATE * 0.25))) * 0.25
    return mix(a, b, whoosh) * 0.85


def impact_body(v=1):
    d = 0.12
    thwack = lowpass(noise(d), 1400 + v * 150) * env(d, 0.0005, 45)
    thud = sine(150, d, 80) * env(d, 0.001, 40) * 0.8
    return mix(thwack, thud)


def impact_world(v=1):
    """Balle dans le béton : petit éclat et ricochet discret."""
    d = 0.22
    chip = bandpass(noise(0.04), 1800, 7000) * env(0.04, 0.0003, 90)
    dust = lowpass(noise(d), 1200) * env(d, 0.002, 25) * 0.4
    ric = place(sine(2200 + v * 400, 0.15, 1300) * env(0.15, 0.002, 25) * 0.18, 0.02, d) if v == 2 else np.zeros(1)
    return mix(chip, dust, ric)


def hurt(v=1):
    """Coup reçu (joueur local) : choc sourd et étouffé."""
    d = 0.25
    thump = sine(90, d, 55) * env(d, 0.002, 18)
    muffled = lowpass(noise(d), 500) * env(d, 0.002, 20) * 0.8
    return mix(thump, muffled)


def heartbeat(v=1):
    """Battement de cœur (vie basse) : deux coups graves."""
    def beat():
        return sine(62, 0.16, 45) * env(0.16, 0.004, 26)
    return mix(place(beat(), 0.0, 0.5), place(beat() * 0.7, 0.18, 0.5))


# ------------------------------------------------------------------ mouvements

def step(v=1):
    """Pas sur le béton : talon puis pointe, avec un peu de grain."""
    d = 0.14
    heel = lowpass(noise(0.05), 700 + v * 60) * env(0.05, 0.001, 70)
    toe = place(lowpass(noise(0.04), 1100) * env(0.04, 0.001, 90) * 0.5, 0.035 + v * 0.004, d)
    grit = bandpass(noise(0.06), 2500, 7000) * env(0.06, 0.001, 60) * 0.12
    return mix(heel, toe, grit)


def land(v=1):
    d = 0.3
    thump = sine(80, d, 45) * env(d, 0.002, 18) * 1.1
    dust = lowpass(noise(d), 900) * env(d, 0.002, 16) * 0.8
    return mix(thump, dust)


def weapon_switch(v=1):
    def clack(f, length=0.04):
        return mix(bandpass(noise(length), 900, 4500) * env(length, 0.0005, 110), sine(f, length) * env(length, 0.0005, 90) * 0.4)
    return mix(place(clack(700), 0.0, 0.25), place(clack(1100, 0.03), 0.12, 0.25))


def reload(v=1):
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


# ------------------------------------------------------------------ capacités, bonus

def ability_shield(v=1):
    d = 0.8
    hum = (sine(140, d, 280) + sine(282, d, 560) * 0.5) * env(d, 0.08, 3.5)
    shimmer = highpass(noise(d), 5000) * env(d, 0.15, 5) * 0.15
    return mix(hum, shimmer)


def ability_dash(v=1):
    d = 0.45
    n = noise(d)
    lo = lowpass(n, 900)
    hi = lowpass(n, 4500)
    sweep = np.linspace(0, 1, len(n))
    whoosh = (lo * (1 - sweep) + hi * sweep) * np.sin(np.pi * sweep) ** 1.5
    return whoosh * 1.3


def ability_pierce(v=1):
    d = 0.55
    zap = sine(220, d, 1800) * env(d, 0.01, 4)
    buzz = np.sign(sine(60, d)) * env(d, 0.01, 6) * 0.15
    return mix(zap * 0.8, lowpass(buzz, 2000))


def ability_charge(v=1):
    """Charge de l'Oni : grondement grave qui monte et grand souffle."""
    d = 0.7
    roar = lowpass(saw(55, d, 95), 900) * env(d, 0.03, 4) * 0.9
    n = noise(d)
    s = np.linspace(0, 1, len(n))
    whoosh = lowpass(n, 2500) * np.sin(np.pi * s) ** 1.2 * 0.9
    return mix(roar, whoosh)


def pickup(v=1):
    """Ramassage d'un bonus : petit arpège brillant."""
    notes = [880, 1108.7, 1318.5, 1760]
    total = 0.45
    parts = [place((sine(f, 0.22) + sine(f * 2, 0.22) * 0.25) * env(0.22, 0.002, 14), i * 0.055, total)
             for i, f in enumerate(notes)]
    sparkle = highpass(noise(total), 6000) * env(total, 0.05, 8) * 0.12
    return mix(*parts, sparkle) * 0.8


def powerup(v=1):
    """Super-pouvoir activé : accord qui monte en balayage."""
    d = 0.9
    chord = sum(sine(f, d, f * 2) * env(d, 0.05, 3) for f in [220, 277.2, 329.6])
    air = highpass(noise(d), 4000) * env(d, 0.3, 4) * 0.15
    return mix(chord * 0.6, air)


def spawn(v=1):
    d = 0.9
    a = sine(330, d, 660) * env(d, 0.05, 4)
    b = sine(495, d, 990) * env(d, 0.12, 4) * 0.5
    air = lowpass(noise(d), 3000) * env(d, 0.2, 5) * 0.12
    return mix(a, b, air) * 0.7


def deflect(v=1):
    d = 0.35
    ping = (sine(1700, d) + sine(2550, d) * 0.6 + sine(4100, d) * 0.3) * env(d, 0.001, 16)
    return ping * 0.7


# ------------------------------------------------------------------ interface et ambiance

def ui_click(v=1):
    d = 0.05
    return mix(sine(1500, d, 900) * env(d, 0.001, 70), highpass(noise(0.01), 3000) * 0.3) * 0.8


def ui_open(v=1):
    d = 0.22
    return sine(500, d, 900) * env(d, 0.005, 16) * 0.7


def ui_close(v=1):
    d = 0.22
    return sine(900, d, 500) * env(d, 0.005, 16) * 0.7


def ambience(v=1):
    """Fond sonore de NEO-EDO (boucle de 12 s) : rumeur de la ville, vent, bourdonnement
    des néons. Très discret ; le début et la fin se raccordent pour boucler sans clic."""
    d = 12.0
    t = t_axis(d)
    city = lowpass(noise(d), 220) * (0.8 + 0.2 * np.sin(2 * np.pi * t / 6.0))
    wind = bandpass(noise(d), 300, 1400) * (0.35 + 0.3 * np.sin(2 * np.pi * t / 4.0 + 1.0) ** 2) * 0.6
    neon = (sine(120, d) * 0.06 + sine(240, d) * 0.03) * (0.7 + 0.3 * np.sin(2 * np.pi * t / 3.0))
    x = mix(city, wind, neon)
    fade = int(RATE * 1.5)                 # raccord : la fin se fond dans le début
    x[:fade] = x[:fade] * np.linspace(0, 1, fade) + x[-fade:] * np.linspace(1, 0, fade)
    return x[:-fade]


# nom -> (fonction, nombre de variantes). Variante 1 = « nom.wav », les suivantes « nom_2.wav »…
SOUNDS = {
    "shot_smg": (shot_smg, 3),
    "shot_shotgun": (shot_shotgun, 2),
    "shot_sniper": (shot_sniper, 2),
    "shot_rocket": (shot_rocket, 1),
    "shot_flame": (shot_flame, 3),
    "shot_laser": (shot_laser, 2),
    "katana_swing": (katana_swing, 2),
    "katana_hit": (katana_hit, 1),
    "poop_launch": (poop_launch, 1),
    "poop_splat": (poop_splat, 1),
    "grenade_throw": (grenade_throw, 1),
    "grenade_bounce": (grenade_bounce, 2),
    "explosion": (explosion, 2),
    "hit": (hit_marker, 1),
    "headshot": (headshot, 1),
    "kill": (kill_confirm, 1),
    "impact_body": (impact_body, 2),
    "impact_world": (impact_world, 3),
    "hurt": (hurt, 1),
    "heartbeat": (heartbeat, 1),
    "step": (step, 4),
    "land": (land, 1),
    "switch": (weapon_switch, 1),
    "reload": (reload, 1),
    "ability_shield": (ability_shield, 1),
    "ability_dash": (ability_dash, 1),
    "ability_pierce": (ability_pierce, 1),
    "ability_charge": (ability_charge, 1),
    "pickup": (pickup, 1),
    "powerup": (powerup, 1),
    "spawn": (spawn, 1),
    "deflect": (deflect, 1),
    "ui_click": (ui_click, 1),
    "ui_open": (ui_open, 1),
    "ui_close": (ui_close, 1),
    "ambience": (ambience, 1),
    # Ajoutés en fin de liste : les sons déjà générés restent identiques (même tirage).
    "shot_rifle": (shot_rifle, 3),
}

if __name__ == "__main__":
    print(f"Sons générés dans {OUT} :")
    for name, (fn, variants) in SOUNDS.items():
        for v in range(1, variants + 1):
            save(name if v == 1 else f"{name}_{v}", fn(v), peak=0.5 if name == "ambience" else 0.9)
