#!/usr/bin/env python3
"""Makes a bank of samples for songs: audio/<ID>.bank, the instruments a MIDI file (audio/<song>.mid) is played with, as the
PlayStation's VAB was. Each sample is kept as ADPCM (a third of PCM16's memory), each instrument says which keys it serves, the
note it was recorded at, its loop and its envelope.

    uv run tools/mkbank.py MANIFEST.json GAME ID
    uv run tools/mkbank.py --sf2 SOUNDFONT.sf2 GAME ID --programs 0,4,24,33,48,56,73 [--drums] [--kb 1500]

The manifest (paths are relative to it):

  {"samples": {"PIANO": {"file": "piano.wav", "loop": [4000, 12000]}, "KICK": {"file": "kick.wav"}},
   "programs": {"0": [{"sample": "PIANO", "root": 60, "keys": [0, 127], "attack": 0.003, "decay": 0.4, "sustain": 0.5,
                       "release": 0.3, "pan": 0, "volume": 1.0, "fine": 0, "vel": [0, 127]}]},
   "drums": [{"sample": "KICK", "keys": [36, 36], "root": 36, "release": 0.05}]}

"programs" are MIDI programs 0 to 127 (General MIDI's numbers); a program may have several regions (a piano's low, middle
and high samples, a layer of two). "drums" is channel 10's kit: one region a key. A sample's "loop" is [from, to] in samples (rounded
down to a block of 28): the part a held note goes round, without which it plays once and stops. root: the MIDI note the sample was
recorded at (default 60); fine in cents; pan -1 to 1; volume 0 to 1; sustain 0 to 1 (the level after the decay); times in seconds.

--sf2 takes the instruments from a SoundFont (any General MIDI one, of the many free ones): the programs you list (General MIDI's numbers:
0 piano, 24 nylon guitar, 33 fingered bass, 48 strings, 56 trumpet, 73 flute...) and, with --drums, the drum kit, each sample cut
to its note range, resampled to 22050 Hz, its loop and envelope kept, and all of it as ADPCM. --kb stops adding samples past that
size. A SoundFont is free to use or not by its own licence: the bank is made from it, so it carries it.
"""
from __future__ import annotations

import argparse
import json
import os
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from wav2vag import BLOCK, RATE, encode, read_wav  # noqa: E402

REGION = 24
SAMPLE = 16


def build(manifest: dict, base: Path) -> bytes:
    names = list(manifest["samples"])
    index = {n: i for i, n in enumerate(names)}
    data = bytearray()
    table = []
    for n in names:
        spec = manifest["samples"][n]
        pcm = spec["pcm"] if "pcm" in spec else read_wav(str(base / spec["file"]))
        if not pcm:
            sys.exit(f"{n}: {spec['file']} has no samples")
        loop = spec.get("loop")
        lf, lt = 0, 0
        if loop:
            lf, lt = int(loop[0]) // BLOCK * BLOCK, int(loop[1])
            if not 0 <= lf < lt <= len(pcm):
                sys.exit(f"{n}: loop {loop} is not inside the sample ({len(pcm)} samples)")
        blocks = encode(pcm, (lf, lt) if loop else None)
        table.append((len(data), len(pcm), lf, lt))
        data += blocks
    regions: list[bytes] = []
    programs = [(0, 0)] * 129

    def add(group: list[dict]) -> tuple[int, int]:
        first = len(regions)
        for r in group:
            if r["sample"] not in index:
                sys.exit(f"a region names the sample {r['sample']!r}, which is not in \"samples\"")
            keys, vel = r.get("keys", [0, 127]), r.get("vel", [0, 127])
            ms = lambda k, d: max(0, min(65535, int(round(float(r.get(k, d)) * 1000))))  # noqa: E731
            regions.append(struct.pack(
                "<BBBBBBBBHHHHh6x", keys[0], keys[1], vel[0], vel[1], int(r.get("root", 60)),
                max(0, min(127, int(round(64 + float(r.get("pan", 0)) * 63)))), max(0, min(255, int(round(float(r.get("sustain", 1)) * 255)))),
                max(0, min(255, int(round(float(r.get("volume", 1)) * 255)))), index[r["sample"]], ms("attack", 0), ms("decay", 0),
                ms("release", 0.2), int(r.get("fine", 0))))
        return first, len(group)

    for prog, group in manifest.get("programs", {}).items():
        if not 0 <= int(prog) <= 127:
            sys.exit(f"program {prog}: 0 to 127")
        programs[int(prog)] = add(group)
    if manifest.get("drums"):
        programs[128] = add(manifest["drums"])
    out = bytearray(b"SBNK" + struct.pack("<HHHH", 1, len(names), len(regions), 0))
    for first, count in programs:
        out += struct.pack("<HH", first, count)
    for off, n, lf, lt in table:
        out += struct.pack("<IIII", off, n, lf, lt)
    for r in regions:
        out += r
    return bytes(out + data)


# ------------------------------------------------------------------ SoundFont 2

def _chunks(blob: bytes, start: int, end: int):
    i = start
    while i + 8 <= end:
        tag, size = blob[i:i + 4], struct.unpack_from("<I", blob, i + 4)[0]
        yield tag, i + 8, size
        i += 8 + size + (size & 1)


def read_sf2(path: Path):
    """-> (samples, presets, instruments): the SoundFont's records as tuples, its sample data as 16-bit numbers."""
    blob = path.read_bytes()
    if blob[:4] != b"RIFF" or blob[8:12] != b"sfbk":
        sys.exit(f"{path}: not a SoundFont 2 (sfbk)")
    smpl = b""
    pdta = {}
    for tag, at, size in _chunks(blob, 12, len(blob)):
        if tag != b"LIST":
            continue
        kind = blob[at:at + 4]
        for t2, a2, s2 in _chunks(blob, at + 4, at + size):
            if kind == b"sdta" and t2 == b"smpl":
                smpl = blob[a2:a2 + s2]
            elif kind == b"pdta":
                pdta[t2.decode("latin-1")] = blob[a2:a2 + s2]
    for need in ("phdr", "pbag", "pgen", "inst", "ibag", "igen", "shdr"):
        if need not in pdta:
            sys.exit(f"{path}: no {need} chunk")
    data = struct.unpack("<%dh" % (len(smpl) // 2), smpl)

    def records(name: str, fmt: str):
        size = struct.calcsize(fmt)
        return [struct.unpack_from(fmt, pdta[name], i * size) for i in range(len(pdta[name]) // size)]

    phdr = records("phdr", "<20sHHHIII")
    pbag, pgen = records("pbag", "<HH"), records("pgen", "<HH")
    inst, ibag, igen = records("inst", "<20sH"), records("ibag", "<HH"), records("igen", "<HH")
    shdr = records("shdr", "<20sIIIIIBbHH")
    return data, phdr, pbag, pgen, inst, ibag, igen, shdr


def _zone_gens(gens, bags, first_bag, last_bag):
    """The zones of a preset or instrument from bag first to last: [(generators as {oper: amount})], the first possibly global."""
    zones = []
    for b in range(first_bag, last_bag):
        g0 = bags[b][0]
        g1 = bags[b + 1][0]
        zones.append({op: amt for op, amt in gens[g0:g1]})
    return zones


def _range(amt: int) -> tuple[int, int]:
    return amt & 0xFF, amt >> 8 & 0xFF


def _signed(amt: int) -> int:
    return amt - 65536 if amt >= 32768 else amt


def _seconds(tc: int) -> float:
    return 2.0 ** (_signed(tc) / 1200.0) if _signed(tc) > -12000 else 0.0


def sf2_manifest(path: Path, programs: list[int], drums: bool, kb: int | None):
    """A bank manifest (with the samples as numbers) from a SoundFont's programs and drum kit."""
    data, phdr, pbag, pgen, inst, ibag, igen, shdr = read_sf2(path)
    samples: dict[str, dict] = {}
    out_programs: dict[str, list] = {}
    out_drums: list = []
    budget = [kb * 1024 if kb else None]
    used = [0]

    def sample_of(sid: int):
        name = f"S{sid}"
        if name in samples:
            return name
        _, start, end, ls, le, rate, root, corr, _, _ = shdr[sid]
        raw = [float(v) for v in data[start:end]]
        if not raw:
            return None
        k = RATE / rate if rate else 1.0
        n = max(1, int(len(raw) * k))
        if budget[0] is not None and used[0] + n * 16 // 28 > budget[0]:  # (its ADPCM: 16 bytes each 28 samples)
            return None
        pcm = [raw[min(len(raw) - 1, int(i / k))] + (raw[min(len(raw) - 1, int(i / k) + 1)] - raw[min(len(raw) - 1, int(i / k))]) * ((i / k) % 1) for i in range(n)]
        spec = {"pcm": pcm}
        if le > ls and le - start <= len(raw) and ls >= start:
            spec["loop"] = [int((ls - start) * k), int((le - start) * k)]
        samples[name] = spec
        used[0] += n * 16 // 28
        return name

    def regions_of(bank_no: int, prog: int):
        found = [i for i, h in enumerate(phdr[:-1]) if h[1] == prog and h[2] == bank_no]
        if not found:
            return []
        i = found[0]
        out = []
        pzones = _zone_gens(pgen, pbag, phdr[i][3], phdr[i + 1][3])
        pglobal = pzones[0] if pzones and 41 not in pzones[0] else {}
        for pz in pzones:
            if 41 not in pz:
                continue
            ii = pz[41]
            izones = _zone_gens(igen, ibag, inst[ii][1], inst[ii + 1][1])
            iglobal = izones[0] if izones and 53 not in izones[0] else {}
            for iz in izones:
                if 53 not in iz:
                    continue
                g = {**iglobal, **iz}
                pg = {**pglobal, **{k: v for k, v in pz.items() if k != 41}}
                name = sample_of(g[53])
                if name is None:
                    continue
                shd = shdr[g[53]]
                keys = _range(g[43]) if 43 in g else (0, 127)
                if 43 in pg:
                    lo, hi = _range(pg[43])
                    keys = (max(keys[0], lo), min(keys[1], hi))
                vel = _range(g[44]) if 44 in g else (0, 127)
                root = _signed(g[58]) if 58 in g and _signed(g[58]) >= 0 else shd[6]
                cents = _signed(g.get(52, 0)) + _signed(g.get(51, 0)) * 100 + shd[7] + _signed(pg.get(52, 0)) + _signed(pg.get(51, 0)) * 100
                sust_cb = _signed(g.get(37, 0)) + _signed(pg.get(37, 0))
                reg = {"sample": name, "keys": list(keys), "vel": list(vel), "root": root, "fine": cents,
                       "attack": _seconds(g.get(34, 0xE890)), "decay": _seconds(g.get(36, 0xE890)),
                       "sustain": max(0.0, min(1.0, 10 ** (-max(0, sust_cb) / 200.0))), "release": _seconds(g.get(38, 0xE890)) or 0.05,
                       "pan": max(-1.0, min(1.0, _signed(g.get(17, 0)) / 500.0)),
                       "volume": max(0.0, min(1.0, 10 ** (-max(0, _signed(g.get(48, 0)) + _signed(pg.get(48, 0))) / 200.0)))}
                if "loop" in samples[name] and g.get(54, 0) & 1 == 0:
                    reg["_noloop"] = True
                out.append(reg)
        return out

    for prog in programs:
        regs = regions_of(0, prog)
        if not regs:
            print(f"program {prog}: not in {path.name}", file=sys.stderr)
        out_programs[str(prog)] = regs
    if drums:
        out_drums = regions_of(128, 0)
    for spec_name, spec in samples.items():  # a sample whose every use does not loop is kept without its loop
        uses = [r for rs in [*out_programs.values(), out_drums] for r in rs if r["sample"] == spec_name]
        if uses and all(r.get("_noloop") for r in uses):
            spec.pop("loop", None)
    for rs in [*out_programs.values(), out_drums]:
        for r in rs:
            r.pop("_noloop", None)
    return {"samples": samples, "programs": out_programs, "drums": out_drums}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("manifest", type=Path, nargs="?")
    ap.add_argument("game", type=Path, nargs="?")
    ap.add_argument("id", nargs="?")
    ap.add_argument("--sf2", type=Path, help="a SoundFont to take the instruments from (then: GAME ID, no manifest)")
    ap.add_argument("--programs", help="--sf2: the General MIDI programs to take, 0 to 127, comma separated")
    ap.add_argument("--drums", action="store_true", help="--sf2: the drum kit too")
    ap.add_argument("--kb", type=int, help="--sf2: stop adding samples past about this many KB")
    a = ap.parse_args()
    if a.sf2:
        if a.manifest is None or a.game is None:
            ap.error("--sf2 SOUNDFONT.sf2 GAME ID")
        game, bank_id = a.manifest, str(a.game)  # (without a manifest the first two positionals are GAME and ID)
        manifest = sf2_manifest(a.sf2, [int(p) for p in (a.programs or "0").split(",")], a.drums, a.kb)
        blob = build(manifest, a.sf2.parent)
    else:
        if not a.manifest or not a.game or not a.id:
            ap.error("MANIFEST.json GAME ID")
        game, bank_id = a.game, a.id
        manifest = json.loads(a.manifest.read_text())
        blob = build(manifest, a.manifest.parent)
    out = game / "audio"
    out.mkdir(parents=True, exist_ok=True)
    path = out / f"{bank_id}.bank"
    path.write_bytes(blob)
    print(f"{path}: {len(manifest['samples'])} samples, {len(blob) // 1024} KB")


if __name__ == "__main__":
    main()
