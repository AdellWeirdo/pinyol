"""Checks of Botín's music, by ear's stand-ins: every song played by the engine itself (build/pinyol_headless --audio, in a scratch
game that only calls music()), and measured.

  level     loudness of the loop (or of the jingle), K-weighted as BS.1770 does (the ear's: bass counts less, presence more): the
            mean power of 400 ms windows louder than -50 dB, about LUFS
  peak      the highest sample (1.0 is full scale); `knee` the share of samples where the mixer's soft limiter (above 0.70) acts
  repeat    the second time round the loop against the first, after its first second (where the first pass's intro tails and
            the second pass's own differ): how far below the music the difference is. A loop that is a whole number of the
            headless player's mix blocks (735 samples) repeats bit for bit (about -150 dB); any other comes back with its pitched
            notes starting at another sub-sample phase of the resampler, some -25 to -40 dB: the same notes at the same times
  seam      the biggest step between two samples within 50 ms of the loop's jump, against the biggest anywhere else in the loop
  tail      a jingle: seconds from its last note until it is below -60 dBFS, and the level of the last half second played
  voices    the most notes sounding at once (the engine has 16 for songs), and the share of the time more than 16 would
  clashes   two notes a semitone apart (minor second or ninth) sounding together an eighth or more
  missing   a program and key, or a drum, with no region in the bank
Then the bank's tuning: each instrument playing A4, its pitch measured (cents off 440 Hz).
"""
from __future__ import annotations

import math
import shutil
import subprocess
from pathlib import Path

import numpy as np

from music_bank import KIT, PROGRAMS, RATE, coverage, manifest_and_pcm
from music_seq import Song, check_coverage, harmony_clashes, polyphony, write_smf

HERE = Path(__file__).resolve().parent
GAME = HERE.parent
ENGINE = GAME.parents[1]
HEADLESS = ENGINE / "build" / "pinyol_headless"


def scratch_game(folder: Path) -> Path:
    g = folder / "game"
    (g / "audio").mkdir(parents=True, exist_ok=True)
    fonts = g / "fonts"
    if not fonts.exists():
        shutil.copytree(GAME / "fonts", fonts)
    (g / "game.json").write_text('{"id": "musiccheck", "title": "Music check", "engine": "pinyol@2", "main": "main.lua"}')
    shutil.copy(GAME / "audio" / "BANK.bank", g / "audio" / "BANK.bank")
    return g


def render(g: Path, song_id: str, loop: bool, seconds: float, out: Path) -> np.ndarray:
    (g / "main.lua").write_text(
        "n = 0\nfunction _init() show(0) end\nfunction _draw() end\nfunction _update()\n  n = n + 1\n"
        f'  if n == 1 then music("{song_id}", 0, {{bank = "BANK", loop = {"true" if loop else "false"}}}) end\nend\n')
    script = out.with_suffix(".script")
    script.write_text(f"new\ntick {int(seconds * 60) + 1}\n")
    r = subprocess.run([str(HEADLESS), "--game", str(g), "--saves", str(out.parent / "saves"), "--fresh", "--script", str(script),
                        "--audio", str(out)], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"{song_id}: {r.stdout}{r.stderr}")
    return np.fromfile(out, dtype="<i2").astype(np.float64) / 32768.0


def k_weight(x: np.ndarray) -> np.ndarray:
    """BS.1770's K-weighting at 22050 Hz: a high shelf (+4 dB over about 1.5 kHz, as the head hears) and a high-pass at 38 Hz."""
    from scipy.signal import lfilter
    a_db, f0, q = 3.99984385397, 1681.97445095, 0.7071752369554193
    k = math.tan(math.pi * f0 / RATE)
    vh, vb = 10 ** (a_db / 20), 10 ** (a_db / 20) ** 0.4996667741545416
    a0 = 1 + k / q + k * k
    b = [(vh + vb * k / q + k * k) / a0, 2 * (k * k - vh) / a0, (vh - vb * k / q + k * k) / a0]
    a = [1, 2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0]
    x = lfilter(b, a, x)
    f0, q = 38.13547087613982, 0.5003270373253953
    k = math.tan(math.pi * f0 / RATE)
    a0 = 1 + k / q + k * k
    return lfilter([1, -2, 1], [1, 2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0], x)


def loudness(x: np.ndarray) -> float:
    """Loudness as BS.1770 measures it, simplified: K-weighted, the mean power of 400 ms windows over -50 dB (in dB, near LUFS)."""
    w = int(0.4 * RATE)
    if len(x) < w:
        return -120.0
    x = k_weight(x)
    ms = np.array([np.mean(x[i:i + w] ** 2) for i in range(0, len(x) - w + 1, w // 2)])
    ms = ms[ms > 10 ** (-50 / 10)]
    return 10 * math.log10(np.mean(ms)) if len(ms) else -120.0


def db(v: float) -> float:
    return 20 * math.log10(max(v, 1e-9))


def release_and_length():
    manifest, _ = manifest_and_pcm()
    lengths = {n: len(s["pcm"]) / RATE for n, s in manifest["samples"].items()}
    loops = {n for n, s in manifest["samples"].items() if s.get("loop")}

    def rel(prog, key, drum):
        if drum:
            return next((r[4] for r in KIT if r[1] <= key <= r[2]), 0.3)
        return PROGRAMS[prog][6] if prog in PROGRAMS else 0.2

    def length(prog, key, drum):
        if drum:
            smp, root = next(((r[0], r[3]) for r in KIT if r[1] <= key <= r[2]), (None, key))
        else:
            smp, root = PROGRAMS[prog][0], None
        if smp is None or smp in loops:
            return None
        ratio = 2 ** ((key - root) / 12) if root is not None else 1.0
        return lengths[smp] / ratio if drum else lengths[smp]

    return rel, length


def check_song(g: Path, folder: Path, s: Song) -> dict:
    info = write_smf(s, GAME / "audio" / f"{s.name}.mid")
    shutil.copy(GAME / "audio" / f"{s.name}.mid", g / "audio" / f"{s.name}.mid")
    sec = s.seconds
    res = {"name": s.name}
    if s.jingle:
        music_end = sec(info["music_end"])
        x = render(g, s.name, False, music_end + 3.0, folder / f"{s.name}.pcm")
        body = x[: int((music_end + 1.0) * RATE)]
        res["length"] = music_end
        res["level"] = loudness(body)
        env = np.array([np.sqrt(np.mean(x[i:i + 441] ** 2)) for i in range(0, len(x) - 441, 441)])
        quiet = np.where(env[int(music_end * 50):] < 10 ** (-60 / 20))[0]
        res["tail"] = quiet[0] / 50 if len(quiet) else float("inf")
        res["end_db"] = db(np.sqrt(np.mean(x[-int(0.5 * RATE):] ** 2)))
    else:
        a, b = sec(info["loop_start"]), sec(info["loop_end"])
        body_s = b - a
        x = render(g, s.name, True, a + 2 * body_s + 2.0, folder / f"{s.name}.pcm")
        i0 = int(a * RATE)  # (the engine truncates times to samples)
        n = int(b * RATE) - i0
        p1, p2 = x[i0:i0 + n], x[i0 + n:i0 + 2 * n]
        res["length"] = a + body_s
        res["intro"], res["loop"] = a, body_s
        res["level"] = loudness(p1)
        k = int(1.0 * RATE)
        m = min(len(p1), len(p2))
        best = min(np.mean((x[i0 + n + k + lag:i0 + n + m + lag] - p1[k:m]) ** 2) for lag in range(-2, 3) if i0 + n + m + lag <= len(x))
        res["repeat_db"] = db(np.sqrt(best)) - db(np.sqrt(np.mean(p1[k:m] ** 2)))
        steps = np.abs(np.diff(x[i0:i0 + 2 * n]))
        w = int(0.05 * RATE)
        near = steps[max(0, n - w):n + w]
        rest = np.concatenate([steps[w:n - w], steps[n + w:]])
        res["seam"] = float(near.max() / max(rest.max(), 1e-9))
    res["peak"] = float(np.max(np.abs(x)))
    res["knee"] = float(np.mean(np.abs(x) > 23000 / 32768))
    res["clip"] = int(np.sum(np.abs(x) >= 32766 / 32768))
    rel, length = release_and_length()
    res["voices"], res["voices_at"], res["over16"] = polyphony(s, rel, length)
    progs, keys = coverage()
    res["missing"] = check_coverage(s, progs, keys)
    res["clashes"] = harmony_clashes(s)
    return res


def check_tuning(g: Path, folder: Path) -> list[tuple[int, str, float]]:
    """Each melodic program plays A4 for 0.7 s, one after another; its pitch is measured from the engine's own output."""
    progs = sorted(PROGRAMS)
    s = Song("tune", 60, "A", jingle=True)
    s.track("p", 0, progs[0], 110, 0, 0)
    bars_n = math.ceil(len(progs) / 4)
    text = " ".join(f"@{p} A4:3 r:1" for p in progs) + " r:4" * (bars_n * 4 - len(progs))
    s.part("a", bars_n, p=text)
    s.form(["a"], [])
    write_smf(s, g / "audio" / "tune.mid")
    x = render(g, "tune", False, len(progs) * 1.0 + 1.0, folder / "tune.pcm")
    out = []
    for i, p in enumerate(progs):
        a = int((i * 1.0 + 0.06) * RATE)
        seg = x[a:a + int(0.4 * RATE)]
        seg = seg * np.hanning(len(seg))
        spec = np.abs(np.fft.rfft(seg, 1 << 17))
        freqs = np.fft.rfftfreq(1 << 17, 1 / RATE)
        band = (freqs > 300) & (freqs < 600)
        j = int(np.argmax(np.where(band, spec, 0)))
        y0, y1, y2 = np.log(spec[j - 1:j + 2] + 1e-12)
        dj = 0.5 * (y0 - y2) / (y0 - 2 * y1 + y2)
        f = (j + dj) * RATE / (1 << 17)
        out.append((p, PROGRAMS[p][0], 1200 * math.log2(f / 440.0)))
    return out


def check_all(folder: Path, names: list[str], make) -> None:
    folder.mkdir(parents=True, exist_ok=True)
    g = scratch_game(folder)
    rows = []
    for name in names:
        r = check_song(g, folder, make(name))
        rows.append(r)
    print(f"{'song':10} {'length':>6} {'level':>6} {'peak':>5} {'knee%':>5} {'clip':>4} {'repeat':>7} {'seam':>5} {'tail':>5} "
          f"{'end dB':>6} {'voices':>6} {'>16':>5}")
    for r in rows:
        rep = f"{r['repeat_db']:7.1f}" if "repeat_db" in r else "      -"
        seam = f"{r['seam']:5.2f}" if "seam" in r else "    -"
        tail = f"{r['tail']:5.2f}" if "tail" in r else "    -"
        end = f"{r['end_db']:6.0f}" if "end_db" in r else "     -"
        print(f"{r['name']:10} {r['length']:6.1f} {r['level']:6.1f} {r['peak']:5.2f} {100 * r['knee']:5.2f} {r['clip']:4} {rep} {seam} "
              f"{tail} {end} {r['voices']:6} {100 * r['over16']:4.1f}%")
    for r in rows:
        if r["missing"]:
            print(f"{r['name']}: MISSING in the bank: {', '.join(r['missing'])}")
        if r["clashes"]:
            print(f"{r['name']}: {len(r['clashes'])} semitone clash(es): " + "; ".join(r["clashes"][:12]))
    if not names or len(names) > 1 or "tune" in names:
        print("tuning (A4 played, cents off 440 Hz):")
        print("  " + "  ".join(f"{p}:{smp.lower()} {c:+.0f}" for p, smp, c in check_tuning(g, folder)))
