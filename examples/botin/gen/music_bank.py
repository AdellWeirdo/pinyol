"""Botín's instruments: a small bank of short, bright, low-fidelity samples, as a Game Boy Advance game's M4A ("Sappy") engine
played them: 8-bit PCM at low rates (held samples: the crunch of 11 kHz), plus the Game Boy's own voices (pulses of 12.5, 25 and
50 %, a 4-bit wave, LFSR noise). Every sample is made here with numpy; `build_bank()` turns them into audio/BANK.bank with
tools/mkbank.py (its `build`, the same code as `uv run tools/mkbank.py manifest.json GAME BANK`; `write_wavs()` writes the WAVs and
that manifest for the command line).

Held notes loop: a looped sample is an attack and then a stretch that is exactly periodic (a whole number of cycles of every partial,
the vibrato's too, in a loop whose length is a multiple of 28, the ADPCM block), so the jump back is seamless. The note it sounds
at is worked out from its period: `root` the nearest MIDI note and `fine` the cents that correct it.

Programs (General MIDI numbers where one fits):
   7 clav (funky, plucked)   8 celesta      12 marimba      16 organ (the wave channel)   33 bass (fingered)   36 slap bass
  38 synth bass             48 strings (49: short, for ostinatos)   55 orchestra hit   56 trumpet   61 brass section   73 flute
  80 square 50 %            81 square 25 %  82 square 12.5 %   114 steel drum
Drums (channel 10): 36 kick, 37 rim, 38 snare, 39 clap, 42 closed hat, 46 open hat, 49 crash, 41-50 toms, 60/61 bongos,
  62-64 congas, 67 anvil, 70 shaker, 76/77 woodblock.
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

def lofi(x: np.ndarray, hold: int = 2, bits: int = 8) -> np.ndarray:
    """The GBA's sound: each value held `hold` samples (a lower rate, unfiltered) and rounded to `bits`."""
    if hold > 1:
        x = x[(np.arange(len(x)) // hold) * hold]
    q = 2 ** (bits - 1)
    return np.round(x * q) / q


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


def looped(target_hz: float, loop_len: int, steady, *, attack_s: float = 0.0, start=None, voices=(0,), vib_cents: float = 0.0,
           noise: float = 0.0, attack_noise: float = 0.0, seed: int = 1, hold: int = 2, bits: int = 8):
    """A held instrument: an attack of `attack_s` and then a loop of `loop_len` samples (a multiple of 28) that is exactly periodic.
    `steady` and `start` are harmonic amplitudes (lists, harmonic 1 first): the loop's, and the attack's at its first sample, which
    turn into the loop's over the attack. `voices` are detunes in whole cycles a loop (an ensemble); `vib_cents` a vibrato of one
    cycle a loop, coming in over the attack. Returns (samples, (loop from, loop to), the frequency of voice 0)."""
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
        for k in range(1 if dv == 0 else 3, k_max + 1):
            if k * f > RATE * 0.45:
                break
            amp = (first[k - 1] + (steady[k - 1] - first[k - 1]) * shape) * (1.0 if dv == 0 else 0.6)
            out += amp * np.sin(k * phase + 0.7 * k * dv)
    rng = np.random.default_rng(seed)
    if noise:  # a breath in the loop: noise of the loop's own length, repeated, so it is periodic too
        cyc = rng.standard_normal(loop_len)
        out += noise * np.std(out) * np.resize(np.roll(cyc, -a % loop_len), n_total)
    if attack_noise and a:
        out += attack_noise * np.std(out) * rng.standard_normal(n_total) * np.clip(1 - t / a, 0, 1) ** 2
    out = lofi(norm(out), hold, bits)
    return out, (a, n_total), f0


def wave_loop(cycle: np.ndarray, period: int, repeats: int):
    """A single cycle (any length) stretched to `period` samples (held steps, as the Game Boy's channels play them) and repeated."""
    idx = (np.arange(period) * len(cycle)) // period
    one = np.asarray(cycle, dtype=np.float64)[idx]
    one = one - one.mean()
    reps = repeats
    while (period * reps) % BLOCK:
        reps += 1
    x = norm(np.tile(one, reps), 0.8)
    return x, (0, len(x)), RATE / period


def decaying(f: float, seconds: float, partials, *, click: float = 0.0, hold: int = 2, seed: int = 2):
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
    fade = np.ones(n)
    k = min(n, int(0.02 * RATE))
    fade[-k:] = np.linspace(1, 0, k)
    return lofi(norm(x * fade), hold)


def lfsr_noise(n: int, short: bool = False, clock_hold: int = 1, seed: int = 0x7FFF) -> np.ndarray:
    """The Game Boy's noise: a 15-bit (or 7-bit, `short`) shift register, a bit a step, each step held `clock_hold` samples."""
    reg = seed
    steps = n // clock_hold + 1
    bits = np.empty(steps)
    for i in range(steps):
        b = (reg ^ (reg >> 1)) & 1
        reg = (reg >> 1) | (b << 14)
        if short:
            reg = (reg & ~0x40) | (b << 6)
        bits[i] = 1.0 if reg & 1 else -1.0
    return np.repeat(bits, clock_hold)[:n]


def env_exp(n: int, tau: float, attack: float = 0.0) -> np.ndarray:
    t = np.arange(n) / RATE
    e = np.exp(-t / tau)
    if attack:
        e *= np.clip(t / attack, 0, 1)
    k = min(n, int(0.01 * RATE))
    e[-k:] *= np.linspace(1, 0, k)
    return e


def onepole_lp(x: np.ndarray, hz: float) -> np.ndarray:
    a = math.exp(-2 * math.pi * hz / RATE)
    y = np.empty_like(x)
    s = 0.0
    for i, v in enumerate(x):
        s = (1 - a) * v + a * s
        y[i] = s
    return y


def saw_harm(k: int, roll: float = 1.0, lp: float = 99.0) -> list[float]:
    """Harmonic amplitudes of a sawtooth (1/k), rolled off a little more by `roll` and above harmonic `lp`."""
    return [(1 / h ** roll) / (1 + (h / lp) ** 2) for h in range(1, k + 1)]


# ------------------------------------------------------------------ the instruments

def melodic() -> dict[str, dict]:
    """name -> {pcm (floats -1..1), loop, hz (the sample's own pitch: None for drums)}"""
    s: dict[str, dict] = {}

    def put(name, x, loop=None, hz=None):
        s[name] = {"pcm": x, "loop": loop, "hz": hz}

    # pulses and the wave channel: single cycles, held steps (no filtering at all, as the Game Boy)
    for name, duty in (("SQ50", 0.5), ("SQ25", 0.25), ("SQ12", 0.125)):
        cyc = np.where(np.arange(64) < 64 * duty, 1.0, -1.0)
        put(name, *wave_loop(cyc, 84, 24))           # 262.5 Hz: C4 +6 cents
    wave4 = np.array([8, 11, 13, 14, 15, 15, 14, 12, 10, 9, 9, 10, 11, 11, 10, 8,
                      6, 4, 3, 3, 4, 5, 5, 4, 3, 2, 1, 0, 0, 1, 2, 5], dtype=float)  # an organ: fundamental, 3rd and 5th harmonics
    put("WAVE", *wave_loop(wave4 / 7.5 - 1, 96, 7))  # 229.7 Hz (A#3 +25)

    # basses: a round low tone with a plucked brightness that settles (C2)
    x, loop, hz = looped(65.4, 336 * 4, saw_harm(40, 1.25, 7), attack_s=0.09, start=saw_harm(40, 0.9, 30), hold=2)
    put("BASS", x, loop, hz)
    pop = [a * (1.6 if h in (5, 6, 7, 8) else 1.0) for h, a in enumerate(saw_harm(60, 0.7, 40), 1)]
    x, loop, hz = looped(65.4, 336 * 4, saw_harm(40, 1.1, 10), attack_s=0.12, start=pop, attack_noise=0.25, hold=2)
    put("SLAP", x, loop, hz)

    # brass: a section (three detuned saws, the blare coming in over the attack) and a trumpet (one voice, a formant, vibrato)
    blare = [a * (1.0 if h < 3 else 0.25) for h, a in enumerate(saw_harm(40, 1.0, 24), 1)]
    x, loop, hz = looped(261.6, BLOCK * 394, saw_harm(40, 1.0, 14), attack_s=0.06, start=blare, voices=(0, 1, -1), hold=2)
    put("BRASS", x, loop, hz)
    trumpet = [a * (1.0 + 0.9 * math.exp(-((h - 5) / 2.2) ** 2)) for h, a in enumerate(saw_harm(30, 1.0, 12), 1)]
    x, loop, hz = looped(392.0, BLOCK * 143, trumpet, attack_s=0.25, start=[a * (0.4 if h > 2 else 1) for h, a in enumerate(trumpet, 1)],
                         vib_cents=14, attack_noise=0.15, hold=2)
    put("TRUMPET", x, loop, hz)

    # strings: three saws two cycles a second apart, softened; flute: nearly a sine, breath, vibrato
    x, loop, hz = looped(261.6, BLOCK * 394, saw_harm(40, 1.1, 8), voices=(0, 1, -1), attack_s=0.05, hold=2)
    put("STRINGS", x, loop, hz)
    x, loop, hz = looped(523.3, BLOCK * 143, [1.0, 0.22, 0.12, 0.04], attack_s=0.2, start=[1.0, 0.5, 0.3, 0.1],
                         vib_cents=16, attack_noise=0.6, hold=1)
    put("FLUTE", x, loop, hz)

    # struck and plucked: one shots at the note's own frequency
    put("MARIMBA", decaying(523.25, 0.55, [(1, 1.0, 0.16), (3.93, 0.35, 0.03), (9.2, 0.12, 0.01)], click=0.15), None, 523.25)
    put("CELESTA", decaying(1046.5, 1.1, [(1, 1.0, 0.35), (2, 0.25, 0.12), (3, 0.08, 0.05), (5.4, 0.05, 0.02)], click=0.05, hold=1),
        None, 1046.5)
    put("STEEL", decaying(523.25, 0.8, [(1, 1.0, 0.28), (2, 0.55, 0.18), (3, 0.3, 0.1), (4.6, 0.08, 0.05)], click=0.1), None, 523.25)
    put("CLAV", clav(261.63), None, 261.63)
    put("ORCHIT", orch_hit(261.63), None, 261.63)
    return s


def clav(f: float) -> np.ndarray:
    """A pulse plucked through a closing filter: each harmonic dies the faster the higher it is (a clavinet, a muted guitar)."""
    n = int(0.32 * RATE)
    t = np.arange(n) / RATE
    x = np.zeros(n)
    for h in range(1, 40):
        if h * f > RATE * 0.45:
            break
        a = math.sin(math.pi * h * 0.22) / h
        x += a * np.sin(2 * np.pi * h * f * t) * np.exp(-t * (6 + 2.2 * h))
    return lofi(norm(x * env_exp(n, 0.5)), 2)


def orch_hit(f: float) -> np.ndarray:
    """The era's orchestra hit: a stack of fifths and octaves of bright saws and a burst of noise, gone in half a second."""
    n = int(0.6 * RATE)
    t = np.arange(n) / RATE
    x = np.zeros(n)
    for ratio, amp in ((0.5, 0.8), (1, 1.0), (1.5, 0.7), (2, 0.6), (3, 0.3)):
        for h in range(1, 30):
            if h * f * ratio > RATE * 0.45:
                break
            x += amp / h * np.sin(2 * np.pi * h * f * ratio * t * (1 + 0.003 * (h % 3 - 1)))
    rng = np.random.default_rng(5)
    x = x * env_exp(n, 0.16, 0.002) + 1.2 * np.std(x) * rng.standard_normal(n) * env_exp(n, 0.03)
    return lofi(norm(x), 2)


def drums() -> dict[str, np.ndarray]:
    d: dict[str, np.ndarray] = {}
    rng = np.random.default_rng(9)

    n = int(0.32 * RATE)
    t = np.arange(n) / RATE
    f = 45 + 110 * np.exp(-t / 0.035)
    kick = np.sin(2 * np.pi * np.cumsum(f) / RATE) * env_exp(n, 0.12) + 0.4 * rng.standard_normal(n) * env_exp(n, 0.003)
    d["KICK"] = lofi(norm(np.tanh(1.6 * kick)), 2)

    n = int(0.26 * RATE)
    t = np.arange(n) / RATE
    body = np.sin(2 * np.pi * np.cumsum(190 + 60 * np.exp(-t / 0.01)) / RATE) * env_exp(n, 0.05)
    hiss = lfsr_noise(n, clock_hold=1) * env_exp(n, 0.075)
    hiss = hiss - 0.6 * onepole_lp(hiss, 1500)
    d["SNARE"] = lofi(norm(0.7 * body + hiss), 2)

    d["HAT"] = lofi(norm(lfsr_noise(int(0.07 * RATE), short=True) * env_exp(int(0.07 * RATE), 0.018)), 1)
    n = int(0.42 * RATE)
    oh = lfsr_noise(n, short=True, seed=0x5A5A)
    d["OHAT"] = lofi(norm((oh - onepole_lp(oh, 4000)) * env_exp(n, 0.13)), 1)
    n = int(1.4 * RATE)
    cr = lfsr_noise(n, seed=0x1234)
    d["CRASH"] = lofi(norm((cr - onepole_lp(cr, 2500)) * env_exp(n, 0.45, 0.002)), 2)

    n = int(0.42 * RATE)
    t = np.arange(n) / RATE
    tom = np.sin(2 * np.pi * np.cumsum(130 + 70 * np.exp(-t / 0.05)) / RATE) * env_exp(n, 0.16) \
        + 0.25 * rng.standard_normal(n) * env_exp(n, 0.01)
    d["TOM"] = lofi(norm(tom), 2)
    n = int(0.3 * RATE)
    t = np.arange(n) / RATE
    conga = np.sin(2 * np.pi * np.cumsum(330 + 90 * np.exp(-t / 0.008)) / RATE) * env_exp(n, 0.09) \
        + 0.15 * np.sin(2 * np.pi * 760 * t) * env_exp(n, 0.02) + 0.3 * rng.standard_normal(n) * env_exp(n, 0.002)
    d["CONGA"] = lofi(norm(conga), 2)
    n = int(0.22 * RATE)
    t = np.arange(n) / RATE
    burst = np.zeros(n)
    for at in (0.0, 0.011, 0.022):
        burst += np.where(t >= at, np.exp(-np.clip(t - at, 0, None) / 0.004), 0)
    cl = rng.standard_normal(n)
    cl = cl - onepole_lp(cl, 900)
    d["CLAP"] = lofi(norm(cl * (burst + 0.5 * env_exp(n, 0.06))), 2)
    n = int(0.09 * RATE)
    t = np.arange(n) / RATE
    d["WOOD"] = lofi(norm(np.sin(2 * np.pi * 820 * t) * env_exp(n, 0.02) + 0.5 * np.sin(2 * np.pi * 1930 * t) * env_exp(n, 0.01)), 2)
    n = int(0.9 * RATE)
    t = np.arange(n) / RATE
    anvil = sum(a * np.sin(2 * np.pi * 620 * r * t) * np.exp(-t / dec)
                for r, a, dec in ((1, 1.0, 0.3), (2.76, 0.7, 0.18), (5.40, 0.45, 0.09), (8.93, 0.3, 0.05)))
    d["ANVIL"] = lofi(norm(anvil + 0.6 * rng.standard_normal(n) * env_exp(n, 0.003)), 2)
    return d


# ------------------------------------------------------------------ the bank: programs and the kit

# program: (sample, lowest key, highest key, attack, decay, sustain, release, volume, pan)
PROGRAMS = {
    7: ("CLAV", 0, 127, 0.0, 0.0, 1.0, 0.08, 0.80, 0.0),
    8: ("CELESTA", 0, 127, 0.0, 0.0, 1.0, 0.45, 0.80, 0.0),
    12: ("MARIMBA", 0, 127, 0.0, 0.0, 1.0, 0.25, 0.85, 0.0),
    16: ("WAVE", 0, 127, 0.004, 0.0, 1.0, 0.06, 0.55, 0.0),
    33: ("BASS", 0, 127, 0.002, 0.5, 0.65, 0.06, 1.0, 0.0),
    36: ("SLAP", 0, 127, 0.001, 0.35, 0.6, 0.05, 1.0, 0.0),
    38: ("BASS", 0, 127, 0.002, 1.2, 0.8, 0.05, 0.95, 0.0),
    48: ("STRINGS", 0, 127, 0.12, 0.0, 1.0, 0.35, 0.60, 0.0),
    49: ("STRINGS", 0, 127, 0.006, 0.25, 0.55, 0.07, 0.70, 0.0),   # the same strings, bowed short: ostinatos
    55: ("ORCHIT", 0, 127, 0.0, 0.0, 1.0, 0.25, 0.85, 0.0),
    56: ("TRUMPET", 0, 127, 0.012, 0.6, 0.8, 0.09, 0.80, 0.0),
    61: ("BRASS", 0, 127, 0.01, 0.4, 0.7, 0.08, 0.70, 0.0),
    73: ("FLUTE", 0, 127, 0.03, 0.0, 1.0, 0.12, 0.85, 0.0),
    80: ("SQ50", 0, 127, 0.002, 0.3, 0.7, 0.05, 0.42, 0.0),
    81: ("SQ25", 0, 127, 0.002, 0.3, 0.7, 0.05, 0.45, 0.0),
    82: ("SQ12", 0, 127, 0.002, 0.3, 0.7, 0.05, 0.50, 0.0),
    114: ("STEEL", 0, 127, 0.0, 0.0, 1.0, 0.3, 0.80, 0.0),
}

# drum key(s): (sample, first key, last key, root key, release, volume, pan)
KIT = [
    ("KICK", 35, 36, 36, 0.5, 1.0, 0.0),
    ("WOOD", 37, 37, 30, 0.2, 0.55, 0.0),       # a rim click: the woodblock played low
    ("SNARE", 38, 38, 38, 0.6, 0.9, 0.0),
    ("CLAP", 39, 39, 39, 0.4, 0.8, 0.0),
    ("SNARE", 40, 40, 36, 0.6, 0.9, 0.0),       # a deeper snare
    ("TOM", 41, 41, 45, 0.8, 0.95, 0.15),
    ("HAT", 42, 42, 42, 0.3, 0.42, -0.2),
    ("TOM", 43, 43, 46, 0.8, 0.95, 0.1),
    ("HAT", 44, 44, 40, 0.3, 0.32, -0.2),
    ("TOM", 45, 45, 47, 0.8, 0.95, 0.0),
    ("OHAT", 46, 46, 46, 0.6, 0.45, -0.2),
    ("TOM", 47, 48, 47, 0.8, 0.95, -0.05),
    ("CRASH", 49, 49, 49, 3.0, 0.55, 0.25),
    ("TOM", 50, 50, 47, 0.8, 0.95, -0.15),
    ("CRASH", 57, 57, 54, 3.0, 0.55, -0.25),
    ("CONGA", 60, 60, 56, 0.4, 0.8, 0.3),       # bongos: the conga, higher
    ("CONGA", 61, 61, 58, 0.4, 0.8, 0.3),
    ("CONGA", 62, 64, 63, 0.4, 0.85, -0.3),
    ("ANVIL", 67, 67, 67, 1.5, 0.6, 0.0),
    ("HAT", 70, 70, 76, 0.3, 0.3, 0.3),         # a shaker: the hat, higher and soft
    ("WOOD", 76, 77, 76, 0.2, 0.6, 0.2),
]


def manifest_and_pcm():
    """The bank's manifest (as tools/mkbank.py reads it), with every sample as numbers in it, and the table of tunings."""
    mel = melodic()
    kit = drums()
    samples, tune = {}, {}
    for name, spec in mel.items():
        entry = {"pcm": [float(v) for v in spec["pcm"] * 32767]}
        if spec["loop"]:
            entry["loop"] = [int(spec["loop"][0]), int(spec["loop"][1])]
        samples[name] = entry
        tune[name] = root_fine(spec["hz"])
    for name, x in kit.items():
        samples[name] = {"pcm": [float(v) for v in x * 32767]}
    programs = {}
    for prog, (smp, lo, hi, att, dec, sus, rel, vol, pan) in PROGRAMS.items():
        root, fine = tune[smp]
        programs[str(prog)] = [{"sample": smp, "root": root, "fine": fine, "keys": [lo, hi], "attack": att, "decay": dec,
                                "sustain": sus, "release": rel, "volume": vol, "pan": pan}]
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
    """The samples as 16-bit WAVs and a manifest.json beside them: `uv run tools/mkbank.py folder/manifest.json examples/botin BANK`."""
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
    return {p: (v[1], v[2]) for p, v in PROGRAMS.items()}, keys
