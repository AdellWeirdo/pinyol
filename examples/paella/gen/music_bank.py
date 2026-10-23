"""Paella de Combate's instruments: a bank of samples in the spirit of a Neo Geo cartridge (the YM2610: punchy FM voices and crisp
ADPCM drums), made with numpy and turned into audio/BANK.bank by tools/mkbank.py (`build_bank()`; `write_wavs()` writes the WAVs and a
manifest for the command line). Adapted from examples/botin/gen/music_bank.py, without its Game Boy crunch: full 16-bit samples
(the bank stores them as ADPCM anyway, as the Neo Geo did), FM synthesis where the YM2610 would have used it, plucked strings by
additive synthesis, distorted guitars made exactly periodic (distortion and the cabinet worked on one period, in the frequency
domain) so that their loops are seamless.

Held notes loop: a looped sample is an attack and then a stretch that is exactly periodic (a whole number of cycles of every partial,
the vibrato's and the reeds' beating too, in a loop whose length is a multiple of 28, the ADPCM block). The note it sounds at is
worked out from its period: `root` the nearest MIDI note and `fine` the cents that correct it.

Programs (General MIDI numbers):
   9 glockenspiel        21 accordion (musette, three reeds)       24 nylon guitar (three samples)   28 palm-muted power chord
  29 overdriven power chord (root, fifth, octave: one key plays the chord)   30 distortion lead guitar
  32 upright bass (plucked)   36 slap bass (FM)   38 FM bass   47 timpani   48 strings   49 strings, short   55 orchestra hit
  56 trumpet   57 trombone   61 brass section   73 flute (and slide whistle)
Drums (channel 10): 35/36 kick, 37 rim, 38/40 snare, 39 palmas (a group's handclaps), 41-50 toms, 42/44/46 hats, 49/57 crash,
  51/53 ride and its bell, 54 tambourine, 55 splash, 60/61 bongos, 62-64 congas, 85 castanets, 86 cajón (bass), 87 cajón (slap).
"""
from __future__ import annotations

import json
import math
import sys
import wave
from pathlib import Path

import numpy as np

RATE = 22050
BLOCK = 28
HERE = Path(__file__).resolve().parent
GAME = HERE.parent
TOOLS = GAME.parents[1] / "tools"


# ------------------------------------------------------------------ helpers

def norm(x: np.ndarray, peak: float = 0.9) -> np.ndarray:
    m = float(np.max(np.abs(x))) or 1.0
    return x * (peak / m)


def root_fine(hz: float) -> tuple[int, int]:
    """The MIDI note nearest a frequency, and the cents that bring the sample to it."""
    m = 69 + 12 * math.log2(hz / 440.0)
    root = int(round(m))
    nominal = 440.0 * 2 ** ((root - 69) / 12)
    return root, int(round(1200 * math.log2(nominal / hz)))


def up28(n: float) -> int:
    return int(math.ceil(n / BLOCK)) * BLOCK


def env_exp(n: int, tau: float, attack: float = 0.0) -> np.ndarray:
    t = np.arange(n) / RATE
    e = np.exp(-t / tau)
    if attack:
        e *= np.clip(t / attack, 0, 1)
    k = min(n, int(0.01 * RATE))
    e[-k:] *= np.linspace(1, 0, k)
    return e


def band(x: np.ndarray, lo: float, hi: float, order: int = 2) -> np.ndarray:
    from scipy.signal import butter, lfilter
    if lo <= 0:
        b, a = butter(order, hi / (RATE / 2), "low")
    elif hi >= RATE / 2:
        b, a = butter(order, lo / (RATE / 2), "high")
    else:
        b, a = butter(order, [lo / (RATE / 2), hi / (RATE / 2)], "band")
    return lfilter(b, a, x)


def saw_harm(k: int, roll: float = 1.0, lp: float = 99.0) -> list[float]:
    """Harmonic amplitudes of a sawtooth (1/k), rolled off a little more by `roll` and above harmonic `lp`."""
    return [(1 / h ** roll) / (1 + (h / lp) ** 2) for h in range(1, k + 1)]


def tail_fade(x: np.ndarray, s: float = 0.02) -> np.ndarray:
    k = min(len(x), int(s * RATE))
    y = x.copy()
    y[-k:] *= np.linspace(1, 0, k)
    return y


# ------------------------------------------------------------------ held (looped) instruments

def looped(target_hz: float, loop_len: int, steady, *, attack_s: float = 0.0, start=None, voices=(0,), vib_cents: float = 0.0,
           noise: float = 0.0, attack_noise: float = 0.0, seed: int = 1, voice_gain: float = 0.6, full_voices: bool = False):
    """A held instrument (botin's, clean): an attack of `attack_s` and then a loop of `loop_len` samples (a multiple of 28) that is
    exactly periodic. `steady` and `start` are harmonic amplitudes: the loop's, and the attack's first, which turn into the loop's.
    `voices` are detunes in whole cycles a loop (an ensemble, or an accordion's reeds); `vib_cents` a vibrato of one cycle a loop."""
    assert loop_len % BLOCK == 0
    a = up28(attack_s * RATE)
    n_total = a + loop_len
    t = np.arange(n_total, dtype=np.float64)
    ramp = np.clip(t / a, 0, 1) if a else np.ones(n_total)
    n0 = int(round(target_hz * loop_len / RATE))
    f0 = n0 * RATE / loop_len
    steady = np.asarray(steady, dtype=np.float64)
    first = np.asarray(start if start is not None else steady, dtype=np.float64)
    k_max = max(len(steady), len(first))
    steady = np.pad(steady, (0, k_max - len(steady)))
    first = np.pad(first, (0, k_max - len(first)))
    shape = ramp ** 0.7
    out = np.zeros(n_total)
    for dv in voices:
        n = n0 + dv
        f = n * RATE / loop_len
        beta = f * (2 ** (vib_cents / 1200) - 1) / (RATE / loop_len) if vib_cents else 0.0
        phase = 2 * np.pi * n * t / loop_len + beta * ramp * np.sin(2 * np.pi * t / loop_len)
        for k in range(1 if (dv == 0 or full_voices) else 3, k_max + 1):
            if k * f > RATE * 0.45:
                break
            amp = (first[k - 1] + (steady[k - 1] - first[k - 1]) * shape) * (1.0 if dv == 0 else voice_gain)
            out += amp * np.sin(k * phase + 0.7 * k * dv)
    rng = np.random.default_rng(seed)
    if noise:
        cyc = rng.standard_normal(loop_len)
        out += noise * np.std(out) * np.resize(np.roll(cyc, -a % loop_len), n_total)
    if attack_noise and a:
        out += attack_noise * np.std(out) * rng.standard_normal(n_total) * np.clip(1 - t / a, 0, 1) ** 2
    return norm(out), (a, n_total), f0


def fm_loop(target_hz: float, loop_len: int, *, ratio: int = 1, idx_start: float = 4.0, idx_steady: float = 1.5,
            attack_s: float = 0.1, sub: float = 0.0, click: float = 0.0, feedback_h: int = 0, seed: int = 3):
    """A two-operator FM voice as the YM2610 made them: a sine carrier bent by a sine `ratio` times higher, the depth falling from
    `idx_start` to `idx_steady` over the attack (then held: the loop is exactly periodic). `sub` adds a sine an octave down
    (needs an even number of cycles); `click` a burst of noise at the start (a slap's thumb)."""
    assert loop_len % BLOCK == 0
    a = up28(attack_s * RATE)
    n_total = a + loop_len
    t = np.arange(n_total, dtype=np.float64)
    n0 = int(round(target_hz * loop_len / RATE))
    if sub and n0 % 2:
        n0 += 1
    f0 = n0 * RATE / loop_len
    ramp = np.clip(t / a, 0, 1) if a else np.ones(n_total)
    idx = idx_steady + (idx_start - idx_steady) * (1 - ramp) ** 2
    pc = 2 * np.pi * n0 * t / loop_len
    x = np.sin(pc + idx * np.sin(ratio * pc))
    if sub:
        x += sub * np.sin(pc / 2)
    if click and a:
        rng = np.random.default_rng(seed)
        x += click * band(rng.standard_normal(n_total), 800, 6000) * np.exp(-t / (0.006 * RATE))
    return norm(x), (a, n_total), f0


def periodic_shape(one: np.ndarray, drive: float, lp: float, hp: float = 70.0, presence: tuple = (2200.0, 1.6, 900.0)):
    """A distorted guitar through its cabinet, worked on exactly one period so the result is still exactly periodic: tanh
    distortion, then the speaker (a high-pass, a steep low-pass, a presence bump) as a filter on the period's spectrum."""
    y = np.tanh(drive * one / (np.std(one) or 1.0))
    L = len(y)
    Y = np.fft.rfft(y)
    f = np.fft.rfftfreq(L, 1 / RATE)
    pf, pg, pw = presence
    H = 1 / np.sqrt(1 + (f / lp) ** 8) * (1 / np.sqrt(1 + (hp / np.maximum(f, 1)) ** 4)) * (1 + (pg - 1) * np.exp(-((f - pf) / pw) ** 2))
    H[0] = 0
    return np.fft.irfft(Y * H, L)


def guitar_loop(target_hz: float, loop_len: int, *, chord: tuple = (1.0,), drive: float = 6.0, lp: float = 3800.0,
                vib_cents: float = 0.0, attack_s: float = 0.03, pick: float = 0.6, seed: int = 4):
    """An electric guitar through a hot amplifier, held: strings at `chord` ratios of the root (1, 1.5, 2: a power chord; their
    cycles are whole numbers in the loop), distorted and filtered one loop at a time, tiled; a pick's scrape over the attack."""
    assert loop_len % BLOCK == 0
    n0 = int(round(target_hz * loop_len / RATE))
    while any(abs(r * n0 - round(r * n0)) > 1e-9 for r in chord):
        n0 += 1
    f0 = n0 * RATE / loop_len
    t = np.arange(loop_len, dtype=np.float64)
    one = np.zeros(loop_len)
    for j, r in enumerate(chord):
        n = int(round(r * n0))
        beta = n * RATE / loop_len * (2 ** (vib_cents / 1200) - 1) / (RATE / loop_len) if vib_cents else 0.0
        ph = 2 * np.pi * n * t / loop_len + beta * np.sin(2 * np.pi * t / loop_len) + 1.3 * j
        for k in range(1, 40):
            if k * n * RATE / loop_len > RATE * 0.45:
                break
            one += (1.0 / k) * np.sin(k * ph + 0.4 * k * j) * (1.0 if j == 0 else 0.8)
    one = periodic_shape(one, drive, lp)
    a = up28(attack_s * RATE)
    reps = int(math.ceil((a + loop_len) / loop_len)) + 1
    tiled = np.tile(one, reps)
    x = tiled[(-a) % loop_len:(-a) % loop_len + a + loop_len]
    if pick and a:
        rng = np.random.default_rng(seed)
        tt = np.arange(a + loop_len)
        x = x + pick * np.std(one) * band(rng.standard_normal(len(x)), 1500, 7000) * np.exp(-tt / (0.008 * RATE))
    return norm(x), (a, a + loop_len), f0


# ------------------------------------------------------------------ struck and plucked (one shots)

def pluck(f: float, seconds: float, *, pos: float = 0.18, tau: float = 1.0, damp: float = 0.25, stretch: float = 1e-5,
          noise: float = 0.15, body: float = 0.25, seed: int = 6) -> np.ndarray:
    """A plucked string by its partials: each as loud as the plucking point lets it be (sin(pi k pos)/k), each dying the faster the
    higher it is; a little stiffness stretching them; the pluck's noise and a hollow body's thump."""
    n = int(seconds * RATE)
    t = np.arange(n) / RATE
    x = np.zeros(n)
    for k in range(1, 80):
        fk = k * f * math.sqrt(1 + stretch * k * k)
        if fk > RATE * 0.45:
            break
        amp = abs(math.sin(math.pi * k * pos)) / k
        x += amp * np.sin(2 * np.pi * fk * t + 0.3 * k) * np.exp(-t * (1 + damp * (k - 1) ** 1.3) / tau)
    rng = np.random.default_rng(seed)
    if noise:
        x += noise * band(rng.standard_normal(n), 1200, 8000) * np.exp(-t / 0.004)
    if body:
        x += body * np.sin(2 * np.pi * 105 * t) * np.exp(-t / 0.05) * (1 - np.exp(-t / 0.002))
    x *= 1 - np.exp(-t / 0.0007)
    return tail_fade(norm(x), 0.05)


def decaying(f: float, seconds: float, partials, *, click: float = 0.0, seed: int = 2) -> np.ndarray:
    """A struck instrument: partials (ratio, amplitude, decay seconds to 1/e) of `f`, a click of noise at the start; one shot."""
    n = int(seconds * RATE)
    t = np.arange(n) / RATE
    x = np.zeros(n)
    for ratio, amp, dec in partials:
        if ratio * f >= RATE * 0.45:
            continue
        x += amp * np.sin(2 * np.pi * ratio * f * t) * np.exp(-t / dec)
    if click:
        rng = np.random.default_rng(seed)
        x += click * rng.standard_normal(n) * np.exp(-t / 0.004)
    return tail_fade(norm(x))


def orch_hit(f: float) -> np.ndarray:
    """The era's orchestra hit: a stack of octaves and fifths of bright saws (strings and brass at once), a burst of noise."""
    n = int(0.75 * RATE)
    t = np.arange(n) / RATE
    x = np.zeros(n)
    for ratio, amp in ((0.5, 0.9), (1, 1.0), (1.5, 0.6), (2, 0.6), (3, 0.25)):
        for h in range(1, 40):
            if h * f * ratio > RATE * 0.45:
                break
            x += amp / h * np.sin(2 * np.pi * h * f * ratio * t * (1 + 0.004 * (h % 3 - 1)) + h)
    rng = np.random.default_rng(5)
    x = x * env_exp(n, 0.2, 0.002) + 1.0 * np.std(x) * band(rng.standard_normal(n), 300, 6000) * env_exp(n, 0.03)
    x += 0.6 * np.std(x) * np.sin(2 * np.pi * f / 2 * t) * env_exp(n, 0.25)
    return tail_fade(norm(np.tanh(1.4 * x / np.max(np.abs(x)))))


def timpani(f: float) -> np.ndarray:
    n = int(2.0 * RATE)
    t = np.arange(n) / RATE
    fb = f * (1 + 0.04 * np.exp(-t / 0.05))  # the head's pitch settles after the stroke
    ph = 2 * np.pi * np.cumsum(fb) / RATE
    x = np.sin(ph) * np.exp(-t / 0.9)
    for r, a, d in ((1.5, 0.5, 0.5), (1.98, 0.35, 0.4), (2.44, 0.2, 0.3), (2.94, 0.12, 0.2)):
        x += a * np.sin(r * ph) * np.exp(-t / d)
    rng = np.random.default_rng(12)
    x += 0.5 * band(rng.standard_normal(n), 100, 1500) * np.exp(-t / 0.015)
    return tail_fade(norm(x), 0.1)


# ------------------------------------------------------------------ the instruments

def melodic() -> dict[str, dict]:
    """name -> {pcm (floats -1..1), loop, hz (the sample's own pitch)}"""
    s: dict[str, dict] = {}

    def put(name, x, loop=None, hz=None):
        s[name] = {"pcm": x, "loop": loop, "hz": hz}

    # nylon guitar: three plucks, so no note is stretched far
    for name, f, tau, sec in (("NYLON_L", 164.81, 1.4, 1.7), ("NYLON_M", 329.63, 1.0, 1.3), ("NYLON_H", 659.26, 0.7, 0.9)):
        put(name, pluck(f, sec, pos=0.17, tau=tau, damp=0.22, noise=0.12, body=0.35 if f < 300 else 0.15), None, f)
    # upright bass: a low pluck, dull and woody, the finger's thump
    put("UPRIGHT", pluck(55.0, 1.6, pos=0.28, tau=0.9, damp=0.55, stretch=2e-5, noise=0.05, body=0.5), None, 55.0)

    # FM basses: the Neo Geo's punch
    put("FMBASS", *fm_loop(65.41, BLOCK * 100, ratio=1, idx_start=5.0, idx_steady=1.4, attack_s=0.16, sub=0.6))
    put("SLAP", *fm_loop(65.41, BLOCK * 100, ratio=2, idx_start=7.0, idx_steady=1.1, attack_s=0.10, sub=0.4, click=1.2))

    # electric guitars: a power chord on one key, and a singing lead with vibrato
    put("POWER", *guitar_loop(82.41, BLOCK * 197, chord=(1.0, 1.5, 2.0), drive=7.0, lp=3600.0, attack_s=0.04, pick=0.8))
    put("DIST", *guitar_loop(164.81, BLOCK * 157, chord=(1.0,), drive=9.0, lp=4200.0, vib_cents=12, attack_s=0.03, pick=0.5))

    # accordion: three reeds, the outer two a few cents either side (the musette's wobble), a reedy spectrum
    reed = [(1 / h ** 0.75) * (1.0 if h % 2 else 0.7) / (1 + (h / 14) ** 2) * (1 + 0.8 * math.exp(-((h - 4) / 2.0) ** 2))
            for h in range(1, 40)]
    put("ACCORDION", *looped(440.0, BLOCK * 131, reed, attack_s=0.04, start=[a * (0.5 if h > 3 else 1) for h, a in enumerate(reed, 1)],
                             voices=(0, 1, -1), voice_gain=0.75, full_voices=True, noise=0.02))

    # brass: a section, a trumpet, a trombone
    blare = [a * (1.0 if h < 3 else 0.3) for h, a in enumerate(saw_harm(40, 1.0, 24), 1)]
    put("BRASS", *looped(261.6, BLOCK * 394, saw_harm(40, 0.95, 16), attack_s=0.05, start=blare, voices=(0, 1, -1)))
    trumpet = [a * (1.0 + 1.1 * math.exp(-((h - 5) / 2.4) ** 2)) for h, a in enumerate(saw_harm(34, 0.95, 14), 1)]
    put("TRUMPET", *looped(392.0, BLOCK * 143, trumpet, attack_s=0.18, start=[a * (0.35 if h > 2 else 1) for h, a in enumerate(trumpet, 1)],
                           vib_cents=12, attack_noise=0.12))
    bone = [a * (1.0 + 1.0 * math.exp(-((h - 3.5) / 1.8) ** 2)) for h, a in enumerate(saw_harm(40, 1.05, 9), 1)]
    put("TROMBONE", *looped(130.81, BLOCK * 157, bone, attack_s=0.12, start=[a * (0.3 if h > 2 else 1) for h, a in enumerate(bone, 1)],
                            vib_cents=10, attack_noise=0.1))

    # strings, flute
    put("STRINGS", *looped(261.6, BLOCK * 394, saw_harm(40, 1.1, 9), voices=(0, 1, -1), attack_s=0.05))
    put("FLUTE", *looped(523.3, BLOCK * 143, [1.0, 0.22, 0.12, 0.04], attack_s=0.15, start=[1.0, 0.5, 0.3, 0.1],
                         vib_cents=16, attack_noise=0.5))

    # struck
    put("GLOCK", decaying(1046.5, 1.2, [(1, 1.0, 0.5), (2.76, 0.35, 0.12), (5.40, 0.12, 0.05), (8.93, 0.05, 0.02)], click=0.08), None, 1046.5)
    put("ORCHIT", orch_hit(261.63), None, 261.63)
    put("TIMPANI", timpani(73.42), None, 73.42)
    return s


def drums() -> dict[str, np.ndarray]:
    d: dict[str, np.ndarray] = {}
    rng = np.random.default_rng(9)

    def tsec(sec):
        n = int(sec * RATE)
        return n, np.arange(n) / RATE

    # kick: a sine that drops fast, a beater's click, saturated
    n, t = tsec(0.4)
    f = 48 + 140 * np.exp(-t / 0.03)
    kick = np.sin(2 * np.pi * np.cumsum(f) / RATE) * env_exp(n, 0.16) + 0.5 * band(rng.standard_normal(n), 1500, 7000) * np.exp(-t / 0.002)
    d["KICK"] = tail_fade(norm(np.tanh(2.0 * kick)))
    d["KICK2"] = tail_fade(d["KICK"][: int(0.15 * RATE)], 0.04)  # a tight one, for double-kick runs (fewer voices ringing)

    # snare: two drumhead modes and the wires
    n, t = tsec(0.35)
    body = (np.sin(2 * np.pi * np.cumsum(185 + 50 * np.exp(-t / 0.01)) / RATE) + 0.5 * np.sin(2 * np.pi * 330 * t)) * env_exp(n, 0.06)
    wires = band(rng.standard_normal(n), 1800, 9000) * env_exp(n, 0.11)
    d["SNARE"] = tail_fade(norm(np.tanh(1.5 * norm(0.8 * body + wires))))

    # palmas: four people clapping, a few milliseconds apart, each a sharp crack of bandpassed noise
    n, t = tsec(0.25)
    pal = np.zeros(n)
    for j, (at, g) in enumerate(((0.0, 1.0), (0.004, 0.8), (0.009, 0.9), (0.015, 0.6))):
        k = int(at * RATE)
        burst = band(np.random.default_rng(20 + j).standard_normal(n - k), 900 + 300 * j, 3200 + 400 * j) * np.exp(-np.arange(n - k) / RATE / 0.012)
        pal[k:] += g * burst
    pal += 0.25 * band(rng.standard_normal(n), 1000, 4000) * env_exp(n, 0.05)
    d["PALMAS"] = tail_fade(norm(pal))

    # castanets: two hard wooden shells, a hollow ring around 2.5-3.5 kHz, a click and its echo
    n, t = tsec(0.09)
    cas = np.zeros(n)
    for at, g, fr in ((0.0, 1.0, 2900), (0.007, 0.55, 3400)):
        k = int(at * RATE)
        tt = np.arange(n - k) / RATE
        cas[k:] += g * (np.sin(2 * np.pi * fr * tt) * np.exp(-tt / 0.008) + 0.6 * np.sin(2 * np.pi * fr * 1.37 * tt) * np.exp(-tt / 0.005)
                        + 0.5 * band(np.random.default_rng(31 + k).standard_normal(n - k), 2000, 8000) * np.exp(-tt / 0.002))
    d["CASTANET"] = tail_fade(norm(cas), 0.01)

    # cajón: the bass (a box's boom) and the slap (the edge, with its snares buzzing)
    n, t = tsec(0.35)
    boom = np.sin(2 * np.pi * np.cumsum(78 + 40 * np.exp(-t / 0.015)) / RATE) * env_exp(n, 0.09) \
        + 0.3 * band(rng.standard_normal(n), 200, 2000) * np.exp(-t / 0.006)
    d["CAJON_B"] = tail_fade(norm(np.tanh(1.3 * boom)))
    n, t = tsec(0.25)
    slap = 0.5 * np.sin(2 * np.pi * 260 * t) * env_exp(n, 0.03) + band(rng.standard_normal(n), 1500, 7000) * env_exp(n, 0.05) \
        + 0.6 * band(rng.standard_normal(n), 600, 2500) * np.exp(-t / 0.004)
    d["CAJON_S"] = tail_fade(norm(slap))

    # tambourine: jingles, metallic partials over a shaken hiss
    n, t = tsec(0.3)
    jing = sum(a * np.sin(2 * np.pi * fr * t + p) for fr, a, p in ((5100, 1, 0), (6350, 0.8, 1), (7420, 0.7, 2), (8900, 0.5, 3), (4300, 0.4, 4)))
    tam = (0.6 * jing * band(rng.standard_normal(n), 30, 300) + band(rng.standard_normal(n), 5000, 10500)) * env_exp(n, 0.07, 0.002)
    d["TAMB"] = tail_fade(norm(tam))

    # hats, crash, ride
    def metal(sec, tau, lo, seed, partials=()):
        n_, t_ = tsec(sec)
        r = np.random.default_rng(seed)
        x = band(r.standard_normal(n_), lo, 10800)
        for fr, a in partials:
            x += a * np.sign(np.sin(2 * np.pi * fr * t_ + fr))
        x = band(x, lo, 10800)
        return tail_fade(norm(x * env_exp(n_, tau, 0.001)))

    ring = ((3150, 0.25), (4720, 0.2), (5960, 0.18), (7300, 0.15))
    d["HAT"] = metal(0.08, 0.02, 6500, 40, ring)
    d["OHAT"] = metal(0.5, 0.17, 5500, 41, ring)
    d["CRASH"] = metal(1.6, 0.55, 3200, 42, ((2700, 0.2), (3900, 0.18), (5300, 0.15)))
    n, t = tsec(1.0)
    ride = sum(a * np.sin(2 * np.pi * fr * t) * np.exp(-t / dd) for fr, a, dd in ((3010, 1, 0.5), (4230, 0.7, 0.35), (5580, 0.5, 0.25), (7920, 0.3, 0.2)))
    ride = ride * 0.5 + band(rng.standard_normal(n), 5000, 10800) * env_exp(n, 0.25)
    d["RIDE"] = tail_fade(norm(ride * (1 - np.exp(-t / 0.0005))))

    # toms, rim, congas
    n, t = tsec(0.5)
    tom = np.sin(2 * np.pi * np.cumsum(120 + 60 * np.exp(-t / 0.05)) / RATE) * env_exp(n, 0.2) \
        + 0.3 * band(rng.standard_normal(n), 200, 3000) * np.exp(-t / 0.01)
    d["TOM"] = tail_fade(norm(np.tanh(1.3 * tom)))
    n, t = tsec(0.08)
    d["RIM"] = tail_fade(norm(np.sin(2 * np.pi * 1700 * t) * np.exp(-t / 0.012) + 0.6 * np.sin(2 * np.pi * 820 * t) * np.exp(-t / 0.02)
                              + 0.5 * band(rng.standard_normal(n), 2000, 9000) * np.exp(-t / 0.002)), 0.01)
    n, t = tsec(0.35)
    conga = np.sin(2 * np.pi * np.cumsum(330 + 90 * np.exp(-t / 0.008)) / RATE) * env_exp(n, 0.1) \
        + 0.15 * np.sin(2 * np.pi * 760 * t) * env_exp(n, 0.02) + 0.3 * rng.standard_normal(n) * env_exp(n, 0.002)
    d["CONGA"] = tail_fade(norm(conga))
    return d


# ------------------------------------------------------------------ the bank: programs and the kit

# program: [(sample, lowest key, highest key, attack, decay, sustain, release, volume, pan), ...]
PROGRAMS = {
    9: [("GLOCK", 0, 127, 0.0, 0.0, 1.0, 0.3, 0.70, 0.0)],
    21: [("ACCORDION", 0, 127, 0.02, 0.3, 0.85, 0.07, 1.0, 0.0)],
    24: [("NYLON_L", 0, 57, 0.0, 0.0, 1.0, 0.10, 0.95, 0.0), ("NYLON_M", 58, 69, 0.0, 0.0, 1.0, 0.09, 0.95, 0.0),
         ("NYLON_H", 70, 127, 0.0, 0.0, 1.0, 0.08, 0.95, 0.0)],
    28: [("POWER", 0, 127, 0.0, 0.16, 0.0, 0.04, 1.0, 0.0)],
    29: [("POWER", 0, 127, 0.002, 1.5, 0.55, 0.08, 0.9, 0.0)],
    30: [("DIST", 0, 127, 0.004, 1.2, 0.7, 0.10, 0.8, 0.0)],
    32: [("UPRIGHT", 0, 127, 0.0, 0.0, 1.0, 0.10, 1.0, 0.0)],
    36: [("SLAP", 0, 127, 0.001, 0.30, 0.55, 0.05, 0.95, 0.0)],
    38: [("FMBASS", 0, 127, 0.002, 0.8, 0.7, 0.05, 0.95, 0.0)],
    47: [("TIMPANI", 0, 127, 0.0, 0.0, 1.0, 0.3, 1.0, 0.0)],
    48: [("STRINGS", 0, 127, 0.10, 0.0, 1.0, 0.12, 0.55, 0.0)],
    49: [("STRINGS", 0, 127, 0.005, 0.22, 0.5, 0.06, 0.65, 0.0)],
    55: [("ORCHIT", 0, 127, 0.0, 0.0, 1.0, 0.25, 0.85, 0.0)],
    56: [("TRUMPET", 0, 127, 0.010, 0.6, 0.8, 0.08, 0.78, 0.0)],
    57: [("TROMBONE", 0, 127, 0.015, 0.6, 0.85, 0.10, 0.85, 0.0)],
    61: [("BRASS", 0, 127, 0.010, 0.4, 0.7, 0.08, 0.85, 0.0)],
    73: [("FLUTE", 0, 127, 0.03, 0.0, 1.0, 0.12, 0.80, 0.0)],
}

# drum key(s): (sample, first key, last key, root key, release, volume, pan)
KIT = [
    ("KICK2", 35, 35, 36, 0.1, 0.95, 0.0),
    ("KICK", 36, 36, 36, 0.5, 1.0, 0.0),
    ("RIM", 37, 37, 37, 0.2, 0.9, 0.1),
    ("SNARE", 38, 38, 38, 0.6, 0.85, 0.0),
    ("PALMAS", 39, 39, 39, 0.4, 0.80, -0.1),
    ("SNARE", 40, 40, 43, 0.6, 0.85, 0.0),
    ("TOM", 41, 41, 41, 0.8, 0.90, 0.3),
    ("HAT", 42, 42, 42, 0.3, 0.36, -0.25),
    ("TOM", 43, 43, 43, 0.8, 0.90, 0.2),
    ("HAT", 44, 44, 40, 0.3, 0.30, -0.25),
    ("TOM", 45, 45, 45, 0.8, 0.90, 0.05),
    ("OHAT", 46, 46, 46, 0.6, 0.40, -0.25),
    ("TOM", 47, 48, 47, 0.8, 0.90, -0.1),
    ("CRASH", 49, 49, 49, 3.0, 0.50, 0.3),
    ("TOM", 50, 50, 50, 0.8, 0.90, -0.25),
    ("RIDE", 51, 51, 51, 0.3, 0.38, 0.35),
    ("RIDE", 53, 53, 48, 0.5, 0.45, 0.35),
    ("TAMB", 54, 54, 54, 0.4, 0.45, 0.4),
    ("CRASH", 55, 55, 50, 1.5, 0.45, -0.3),
    ("CRASH", 57, 57, 54, 3.0, 0.50, -0.3),
    ("CONGA", 60, 60, 56, 0.4, 0.75, 0.3),
    ("CONGA", 61, 61, 58, 0.4, 0.75, 0.3),
    ("CONGA", 62, 64, 63, 0.4, 0.80, -0.3),
    ("CASTANET", 85, 85, 85, 0.2, 0.75, 0.35),
    ("CAJON_B", 86, 86, 86, 0.5, 1.0, 0.0),
    ("CAJON_S", 87, 87, 87, 0.4, 0.75, 0.0),
]


def manifest_and_pcm():
    """The bank's manifest (as tools/mkbank.py reads it), with every sample as numbers in it, and the table of tunings."""
    mel = melodic()
    kit = drums()
    samples, tune = {}, {}
    for name, spec in mel.items():
        entry = {"pcm": [float(v) for v in np.clip(spec["pcm"], -1, 1) * 32767]}
        if spec["loop"]:
            entry["loop"] = [int(spec["loop"][0]), int(spec["loop"][1])]
        samples[name] = entry
        tune[name] = root_fine(spec["hz"])
    for name, x in kit.items():
        samples[name] = {"pcm": [float(v) for v in np.clip(x, -1, 1) * 32767]}
    programs = {}
    for prog, regions in PROGRAMS.items():
        programs[str(prog)] = []
        for smp, lo, hi, att, dec, sus, rel, vol, pan in regions:
            root, fine = tune[smp]
            programs[str(prog)].append({"sample": smp, "root": root, "fine": fine, "keys": [lo, hi], "attack": att, "decay": dec,
                                        "sustain": sus, "release": rel, "volume": vol, "pan": pan})
    kit_regions = [{"sample": smp, "keys": [lo, hi], "root": root, "release": rel, "volume": vol, "pan": pan}
                   for smp, lo, hi, root, rel, vol, pan in KIT]
    return {"samples": samples, "programs": programs, "drums": kit_regions}, tune


def build_bank(out_id: str = "BANK") -> tuple[Path, int]:
    sys.path.insert(0, str(TOOLS))
    from mkbank import build  # noqa: E402  (tools/mkbank.py)
    manifest, _ = manifest_and_pcm()
    blob = build(manifest, HERE)
    path = GAME / "audio" / f"{out_id}.bank"
    path.parent.mkdir(exist_ok=True)
    path.write_bytes(blob)
    return path, len(blob)


def write_wavs(folder: Path) -> Path:
    """The samples as 16-bit WAVs and a manifest.json beside them: `uv run tools/mkbank.py folder/manifest.json examples/paella BANK`."""
    folder.mkdir(parents=True, exist_ok=True)
    manifest, _ = manifest_and_pcm()
    for name, spec in manifest["samples"].items():
        pcm = np.clip(np.round(np.asarray(spec.pop("pcm"))), -32768, 32767).astype("<i2")
        with wave.open(str(folder / f"{name.lower()}.wav"), "wb") as w:
            w.setnchannels(1), w.setsampwidth(2), w.setframerate(RATE)
            w.writeframes(pcm.tobytes())
        spec["file"] = f"{name.lower()}.wav"
    path = folder / "manifest.json"
    path.write_text(json.dumps(manifest, indent=1))
    return path


def coverage() -> tuple[dict[int, tuple[int, int]], set[int]]:
    """Which keys each program serves, and the drum keys: for checking that every note of every song has a sound."""
    keys = set()
    for _, lo, hi, *_ in KIT:
        keys.update(range(lo, hi + 1))
    return {p: (min(r[1] for r in v), max(r[2] for r in v)) for p, v in PROGRAMS.items()}, keys
