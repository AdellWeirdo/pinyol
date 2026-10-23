#!/usr/bin/env python3
"""Paella de Combate's music: every song and jingle as a Standard MIDI File (audio/<name>.mid) played by the game's bank of samples
(audio/BANK.bank): music("puerto", 0, {bank = "BANK"}). A Mediterranean action soundtrack for a Neo Geo run-and-gun: pasodoble
brass, rumba and flamenco guitars, accordion, palmas, castanets and cajón, over rock drums and punchy FM bass.

    python3 gen/songs.py               the bank (if it is missing) and every song, and a table of them
    python3 gen/songs.py puerto jefe   only those songs
    python3 gen/songs.py --bank        the bank again (gen/music_bank.py: the instruments)
    python3 gen/songs.py --wavs DIR    the bank's samples as WAVs and a manifest for tools/mkbank.py
    python3 gen/songs.py --check DIR   every song played by the engine (build/pinyol_headless) in a scratch game in DIR, and its
                                       numbers: level, peak, the loop's seam, the silence after a jingle, the tuning (gen/music_check.py);
                                       DIR/<song>.wav is what the engine played, to listen to

The notation is gen/music_seq.py's (botin's, extended): a sixteenth note is the unit, `C5:4` a quarter note, `|` a bar line
(checked). A song is parts (bars and a voice for each track) played in a form: an intro once, then a body that loops (the markers
loopStart and loopEnd). A jingle plays once and then goes round a stretch of silence, so it ends whether the game loops it or not.
Tracks with `strum` spread their chords like a guitarist's hand (down on the beat, up off it).
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from music_seq import Song, arp, bassline, chord, comp, midi_of, name_of, transpose, write_smf  # noqa: E402

GAME = HERE.parent
SONGS: dict = {}


def song(fn):
    SONGS[fn.__name__] = fn
    return fn


def bars(*b: str) -> str:
    return " | ".join(b) + " |"


def rep(grid: str, n: int, last: str | None = None) -> str:
    """A drum bar n times (the last one replaced by `last`, a fill)."""
    g = [grid] * n
    if last:
        g[-1] = last
    return "|".join(g) + "|"


def rest(n: int, bar16: int = 16) -> str:
    return " | ".join([f"r:{bar16}"] * n) + " |"


NOTE_RE = re.compile(r"(?<![A-Za-z@~])([A-G][#b]?-?\d)")


def remap(text: str, moves: dict[str, int], flats: bool = False) -> str:
    """The same voice in another mode: each note whose pitch class is a key of `moves` moved that many semitones
    (D minor to D major: {"F": 1, "Bb": 1})."""
    pcs = {midi_of(k + "4") % 12: v for k, v in moves.items()}
    return NOTE_RE.sub(lambda m: name_of(midi_of(m.group(1)) + pcs.get(midi_of(m.group(1)) % 12, 0), flats), text)


def timeline_of(prog: list[tuple[str, float]]) -> list[str]:
    t = []
    for name, n in prog:
        t += [name] * int(n)
    return t


def second_voice(text: str, prog: list[tuple[str, float]], scale: list[int], flats: bool = True) -> str:
    """A second trumpet under the tune, as a pasodoble's band writes it: each note's partner is the nearest tone of the chord
    sounding a third or a sixth under it (a fourth or fifth if neither is there); a short passing note (not of the chord) takes the scale's note a third under instead."""
    tl = timeline_of(prog)
    out, pos, prev, prev_gap = [], 0.0, None, None
    for tok in text.replace("|", " | ").split():
        m = re.fullmatch(r"([A-G][#b]?-?\d)(?::([\d/]+))?(.*)", tok)
        if tok == "|" or not m:
            out.append(tok)
            if tok.startswith("r:") or tok.startswith("-:"):
                pos += eval(tok[2:].rstrip(".'_>"))
            continue
        key = midi_of(m.group(1))
        ln = eval(m.group(2)) if m.group(2) else 4
        root, iv, _ = chord(tl[min(int(pos), len(tl) - 1)])
        pcs = {(root + i) % 12 for i in iv}
        cands = [(d, key - d) for d in (3, 4, 8, 9) if (key - d) % 12 in pcs] or \
            [(d, key - d) for d in (5, 7) if (key - d) % 12 in pcs]  # thirds and sixths, as a band writes; else a fourth or fifth
        if key % 12 not in pcs and ln <= 2 or not cands:
            sixth = prev_gap is not None and prev_gap >= 7  # a passing note keeps the interval before it: a third or a sixth
            deg = [p for p in (range(key - 10, key - 7) if sixth else range(key - 5, key - 2)) if p % 12 in scale]
            low = deg[-1] if deg else key - (8 if sixth else 3)
        else:  # the one nearest the note before (smooth), a third rather than a sixth when it is as near
            low = min(cands, key=lambda c: abs(c[1] - prev) + (0 if c[0] in (3, 4) else 2) if prev else c[0])[1]
        prev, prev_gap = low, key - low
        out.append(f"{name_of(low, flats)}" + (f":{m.group(2)}" if m.group(2) else "") + m.group(3))
        pos += ln
    return " ".join(out)


def tremolo(text: str, unit: str = "1/2") -> str:
    """Every note picked again and again, `unit` sixteenths a stroke (a surf guitar's tremolo picking)."""
    u = eval(unit)
    out = []
    for tok in text.replace("|", " | ").split():
        m = re.fullmatch(r"([A-G][#b]?-?\d)(?::([\d/]+))?(.*)", tok)
        if not m:
            out.append(tok)
            continue
        n = eval(m.group(2)) if m.group(2) else 4
        out += [f"{m.group(1)}:{unit}"] * int(round(n / u))
    return " ".join(out)


SCALE_DM = [2, 4, 5, 7, 9, 10, 1]          # D harmonic minor
SCALE_F = [5, 7, 9, 10, 0, 2, 4]           # F major
SCALE_D = [2, 4, 6, 7, 9, 11, 1]           # D major
SCALE_G = [7, 9, 11, 0, 2, 4, 6]
SCALE_BB = [10, 0, 2, 3, 5, 7, 9]
SCALE_AM = [9, 11, 0, 2, 4, 5, 7, 8]       # A minor with its raised seventh


# ------------------------------------------------------------------ the theme of the game (title, ending, fanfares)

TEMA_PA = [("Dm", 16), ("A7", 16), ("A7b9", 16), ("Dm", 16), ("Dm", 16), ("Gm", 16), ("A7b9", 16), ("Dm", 16)]
TEMA_A = bars("D5:6 A4:2 D5:2 E5:2 F5:2 G5:2", "A5:6 G5:1 F5:1 E5:4 C#5:4",
              "C#5:2 E5:2 G5:2 Bb5:2 A5:4 G5:2 E5:2", "F5:6 E5:2 D5:8",
              "D5:6 A4:2 D5:2 E5:2 F5:2 A5:2", "Bb5:6 A5:1 G5:1 D6:4 Bb5:4",
              "A5:2 Bb5:2 A5:2 G5:2 F5:2 E5:2 C#5:2 E5:2", "D5:12 r:4")
TEMA_PB = [("F", 16), ("C7", 16), ("C7", 16), ("F", 16), ("F7", 16), ("Bb", 16), ("C7", 16), ("F", 8), ("A7", 8)]
TEMA_B = bars("A5:6 C6:2 A5:4 F5:4", "G5:6 Bb5:2 G5:4 E5:4", "C5:2 D5:2 E5:2 F5:2 G5:4 Bb5:4", "A5:10 r:2 F5:2 A5:2",
              "C6:6 A5:2 Eb6:4 C6:4", "D6:6 C6:2 Bb5:4 F5:4", "E5:2 F5:2 G5:2 A5:2 Bb5:2 C6:2 D6:2 E6:2",
              "F6:8 A5:2 G5:2 E5:2 C#5:2")
TO_MAJOR = {"F": 1, "Bb": 1}  # D minor's tune in D major


@song
def titulo():
    """D minor to F major, 132 BPM: the theme, a pasodoble played by a rock band. An intro on the Andalusian cadence (Dm C Bb A),
    orchestra hits and timpani, the trumpets calling; then the tune in D minor on two trumpets in thirds, as a village band plays a
    pasodoble, with the band's oom-pah (bass on the beat, brass chords off it) over rock drums and chugging guitars, castanets;
    the trio in F major, heroic, the distorted guitar doubling the trumpets, strings and a held power chord, back to D minor."""
    s = Song("titulo", 132, "D minor / F major", about="title")
    s.track("tp1", 0, 56, 106, -0.1, 30).track("tp2", 1, 56, 84, 0.15, 30).track("brass", 2, 61, 78, 0.3, 20)
    s.track("bass", 3, 38, 112, 0).track("chug", 4, 28, 112, -0.35).track("power", 5, 29, 92, -0.3, 20)
    s.track("lead", 6, 30, 70, 0.35, 30).track("strings", 7, 48, 62, 0.25, 40).track("orch", 8, 55, 88, 0, 30)
    s.track("timp", 10, 47, 100, 0, 20).track("kit", 9, 0, 100).track("perc", 9, 0, 100)
    intro_p = [("Dm", 16), ("C", 16), ("Bb", 16), ("A7", 16)]
    fan = bars("D5:3 D5:1 D5:4 F5:4 A5:4", "G5:3 G5:1 G5:4 E5:4 C5:4", "F5:3 F5:1 F5:4 D5:4 Bb4:4", "E5:3 E5:1 E5:2 F5:2 E5:2 D5:2 C#5:4")
    s.part("intro", 4, tp1=fan, tp2=second_voice(fan, intro_p, SCALE_DM),
           orch="D4:4> r:12 | C4:4> r:12 | Bb3:4> r:12 | A3:2> r:2 A3:2> r:2 A3:2> r:2 A3:2> A3:2> |",
           power="D2:16 | C2:16 | Bb1:16 | A1:4 r:4 A1:2 A1:2 A1:2 A1:2 |",
           timp="D2:4 r:12 | C2:4 r:12 | Bb1:4 r:12 | " + " ".join(["A1:2"] * 8) + " |",
           strings=comp(intro_p, "x---------------", "A3", "D5"),
           kit="K...........f.f.|K...........f.f.|K.........m.m.M.|k.k.k.k.ssssSSSS|",
           perc="c...............|................|................|nnnnnnnnNNNNNNNN|")
    oom = "R:4 5d:4 R:4 5d:4"
    s.part("A", 8, tp1=TEMA_A, tp2=second_voice(TEMA_A, TEMA_PA, SCALE_DM),
           brass=comp(TEMA_PA, "..x...x...x...x.", "A3", "D5"), bass=bassline(TEMA_PA, oom, "A1"),
           chug="v118 " + bassline(TEMA_PA, "R:2 R:2 R:2 R:2 R:2 R:2 R:2 R:2", "A1"),
           kit=rep("k...s...k.k.s...", 8, "k...s...k.s.s.ss"), perc="c" + rep("h.h.h.h.h.h.h.hn", 8)[1:])
    s.part("B", 8, tp1=TEMA_B, tp2=second_voice(TEMA_B, TEMA_PB, SCALE_F), lead=transpose(TEMA_B, -12),
           power=bassline(TEMA_PB, "R:8 R:8", "A1"), strings=comp(TEMA_PB, "x---------------", "A3", "C5"),
           bass=bassline(TEMA_PB, "R:4 5d:4 R:4 5d:4", "A1"), orch=bars("F4:2> r:14", *["r:16"] * 6, "r:8 A3:2> r:2 A3:2> A3:2>"),
           kit=rep("k...s..kk...s...", 8, "k...s..kk.s.SSSS"), perc="c" + rep("r.r.E.r.r.r.E.r.", 8)[1:])
    return s.form(["intro"], ["A", "B"])


# ------------------------------------------------------------------ the character select

@song
def seleccion():
    """A phrygian (Am G F E, the Andalusian cadence), 112 BPM: choosing a cook. A cajón and palmas groove, a rumba strum on the
    nylon guitar, the upright bass; a guitar falseta over it in sixteenths, the second time an octave up with a flamenco run
    down to E."""
    s = Song("seleccion", 112, "A phrygian", about="character select")
    s.track("falseta", 0, 24, 112, 0.2, 30).track("strum", 1, 24, 72, -0.3, 20, strum=3).track("bass", 2, 32, 118, 0)
    s.track("cajon", 9, 0, 100).track("palmas", 9, 0, 100)
    p = [("Am", 16), ("G", 16), ("F", 16), ("E", 16)] * 2
    fal = bars("A4:2 C5:1 B4:1 A4:2 E5:2 r:2 E5:1 F5:1 E5:2 C5:2", "D5:2 B4:1 A4:1 G4:2 D5:2 r:2 D5:1 E5:1 D5:2 B4:2",
               "C5:2 A4:1 G4:1 F4:2 C5:2 r:2 C5:1 D5:1 C5:2 A4:2", "B4:1 C5:1 B4:1 A4:1 G#4:2 F4:2 E4:4 r:4",
               "E5:2 A5:2 C6:2 B5:1 A5:1 G#5:2 A5:2 E5:4", "D5:2 G5:2 B5:2 A5:1 G5:1 F#5:2 G5:2 D5:4",
               "C5:2 F5:2 A5:2 G5:1 F5:1 E5:2 F5:2 A5:2 G5:2", "F5:1 E5:1 D5:1 C5:1 B4:1 A4:1 G#4:1 F4:1 E4:8")
    rumba = "X..xX.x.X..xX.x."
    cajon = "y.v.Y.vyy.v.Y.vv"
    s.part("intro", 2, cajon=rep(cajon, 2, "y.v.Y.vyY.YvYYYY"), palmas=rep("....P.l.....P.l.", 2),
           strum="r:16 | " + comp([("E", 16)], "X..xX.x.X.x.X---", "E3", "E4", 4) + " |", bass="r:16 | E2:4 r:4 E2:4 E2:2 G#2:2 |")
    s.part("A", 8, falseta=fal, strum=comp(p, rumba, "E3", "E4", 4), bass=bassline(p, "R:4 r:2 5d:2 R:4 5d:2 R:2", "E1"),
           cajon=rep(cajon, 8, "y.v.Y.vyY.YvYYYY"), palmas=rep("....P.l.....P.l.", 8, "..l.P.l...l.P.PP"))
    return s.form(["intro"], ["A"])


# ------------------------------------------------------------------ zone 1: the harbour at dawn

@song
def puerto():
    """G major, 126 BPM: the harbour at dawn, a jaunty rumba. The accordion sings a dotted tune over a strummed nylon guitar,
    upright bass, a light kit with tambourine and palmas; a minor chorus (Em Am D7 G B7) on the trumpet, the accordion answering;
    a break where the guitar plays a falseta in sixteenths over Em C Am B7, back to G through D7."""
    s = Song("puerto", 126, "G major", about="zone 1, harbour")
    s.track("acc", 0, 21, 122, -0.15, 30).track("tp", 1, 56, 100, 0.15, 30).track("strum", 2, 24, 74, 0.3, 20, strum=3)
    s.track("bass", 3, 32, 120, 0).track("gtr", 4, 24, 112, -0.25, 30).track("accomp", 5, 21, 66, 0.35, 20)
    s.track("kit", 9, 0, 96).track("perc", 9, 0, 96)
    pa = [("G", 16), ("G", 16), ("C", 16), ("D7", 16), ("G", 16), ("Em", 16), ("Am7", 8), ("D7", 8), ("G", 16)]
    pb = [("Em", 16), ("Em", 16), ("Am", 16), ("Am", 16), ("D", 16), ("D7", 16), ("G", 16), ("B7", 16)]
    pc = [("Em", 16), ("C", 16), ("Am", 16), ("B7", 16), ("Em", 16), ("C", 16), ("Am", 16), ("D7", 16)]
    acc_a = bars("D5:3 G5:1 G5:2 A5:2 B5:3 A5:1 G5:2 D5:2", "E5:2 D5:2 B4:2 D5:2 G5:6 r:2", "E5:3 G5:1 G5:2 A5:2 C6:3 B5:1 A5:2 G5:2",
                 "F#5:2 E5:2 D5:2 C5:2 A5:6 r:2", "D5:3 G5:1 G5:2 A5:2 B5:3 C6:1 D6:2 B5:2", "E6:4 D6:2 B5:2 G5:4 E5:4",
                 "C6:3 B5:1 A5:2 G5:2 F#5:2 A5:2 D6:2 C6:2", "B5:4 G5:2 A5:2 G5:4 r:4")
    tp_b = bars("B5:6 A5:1 G5:1 F#5:4 E5:4", "G5:2 F#5:2 E5:2 D#5:2 E5:8", "C6:6 B5:1 A5:1 G5:4 E5:4", "A5:2 G5:2 F#5:2 E5:2 A5:8",
                "A5:6 G5:1 F#5:1 E5:4 D5:4", "F#5:2 G5:2 A5:2 C6:2 B5:4 A5:4", "G5:6 A5:2 B5:4 D6:4", "D#6:4 C6:2 B5:2 A5:2 F#5:2 D#5:4")
    acc_b = bars("r:8 E5:2 G5:2 B5:4", "r:16", "r:8 A4:2 C5:2 E5:4", "r:16", "r:8 F#5:2 A5:2 D6:4", "r:16", "r:8 B4:2 D5:2 G5:4", "r:16")
    gtr_c = bars("E5:1 F#5:1 G5:1 B5:1 E6:2 D6:1 B5:1 C6:1 B5:1 A5:1 G5:1 F#5:2 E5:2", "G5:1 A5:1 B5:1 C6:1 E6:2 C6:2 G5:2 E5:2 C5:4",
                 "A5:1 B5:1 C6:1 E6:1 A6:2 G6:1 E6:1 F6:1 E6:1 D6:1 C6:1 B5:2 A5:2", "D#6:1 E6:1 F#6:1 A6:1 B6:4 A6:1 F#6:1 D#6:1 C6:1 B5:4",
                 "B5:2 G5:1 E5:1 B4:2 E5:2 G5:2 B5:2 E6:4", "C6:2 G5:1 E5:1 C5:2 E5:2 G5:2 C6:2 E6:4",
                 "E6:1 D6:1 C6:1 B5:1 A5:1 G5:1 F#5:1 E5:1 A5:4 C6:4", "D6:2 C6:2 A5:2 F#5:2 D5:2 E5:1 F#5:1 A5:2 C6:2")
    rumba = "X.xxX.x.X.xxX.x."
    walk = "R:3 R:1 r:2 5d:2 R:4 5d:2 O:2"
    kit = "k...x..kk...x..."
    perc = "e.e.E.e.e.e.E.e."
    s.part("intro", 2, acc="r:16 | r:8 D5:2 E5:2 F#5:2 A5:2 |", strum=comp([("G", 16), ("D7", 16)], rumba, "D3", "D4", 4),
           bass="G1:4 r:4 G1:4 r:4 | D2:4 r:4 D2:2 E2:2 F#2:2 A2:2 |", kit=rep("k.......k.......", 2, "k.......k...xxxx"),
           perc=rep("e.e.E.e.e.e.E.e.", 2))
    s.part("A", 8, acc=acc_a, strum=comp(pa, rumba, "D3", "D4", 4), bass=bassline(pa, walk, "E1"), kit=rep(kit, 8),
           perc=rep(perc, 8, "e.e.E.e.P.P.P.PP"))
    s.part("B", 8, tp=tp_b, accomp=acc_b, strum=comp(pb, rumba, "D3", "D4", 4), bass=bassline(pb, walk, "E1"),
           kit=rep("k...s..kk...s...", 8, "k...s..kk.s.s.ss"), perc="c" + rep("e.e.E.e.e.e.E.e.", 8)[1:])
    s.part("C", 8, gtr=gtr_c, accomp=comp(pc, "..x...x...x...x.", "G4", "E5"), bass=bassline(pc, "R:4 r:4 5d:4 r:2 R:2", "E1"),
           kit=rep("k.......k.......", 8, "k.......k.x.xxxx"), perc=rep("....P.l.....P.l.", 8, "P.P.P.P.P.P.PPPP"))
    return s.form(["intro"], ["A", "B", "C"])


# ------------------------------------------------------------------ zone 2: the main street at noon

@song
def calle():
    """E phrygian, 150 BPM: the main street at noon, flamenco-rock. A palm-muted riff on E with power-chord stabs on F and G (the
    phrygian's half step), FM bass doubling it, driving drums and castanets; the trumpet and the distorted guitar in octaves sing a
    phrygian-dominant tune; an Andalusian-cadence chorus (Am G F E) with brass stabs; a break of palmas and cajón with a nylon falseta,
    then the band climbing E F G A under orchestra hits; and the riff with the brass to round it off."""
    s = Song("calle", 150, "E phrygian", about="zone 2, main street")
    s.track("tp", 0, 56, 104, 0.1, 30).track("lead", 1, 30, 72, -0.2, 30).track("brass", 2, 61, 86, 0.3, 20)
    s.track("bass", 3, 38, 108, 0).track("chug", 4, 28, 112, -0.4).track("power", 5, 29, 92, 0.4, 15)
    s.track("gtr", 6, 24, 110, 0.15, 30).track("orch", 7, 55, 86, 0, 30).track("kit", 9, 0, 100).track("perc", 9, 0, 100)
    chug1 = "E2:1 E2:1 E2:1 r:1 E2:1 E2:1 r:2 E2:1 E2:1 E2:1 r:1 r:4"
    pow1, pow2 = "r:6 F2:2 r:4 G2:2 F2:2", "r:6 F2:2 r:2 G2:2 A2:2 G2:1 F2:1"
    bass1, bass2 = "E1:1 E1:1 E1:1 r:1 E1:1 E1:1 F1:2 E1:1 E1:1 E1:1 r:1 G1:2 F1:2", "E1:1 E1:1 E1:1 r:1 E1:1 E1:1 F1:2 E1:1 E1:1 G1:2 A1:2 G1:1 F1:1"
    riff_chug = "v118 " + bars(chug1, chug1)
    riff_pow = bars(pow1, pow2)
    riff_bass = bars(bass1, bass2)
    tune_a = bars("E5:4 F5:2 G#5:2 A5:4 G#5:2 F5:2", "G#5:2 F5:2 E5:6 r:2 E5:2 F5:2", "G#5:4 A5:2 B5:2 C6:4 B5:2 A5:2",
                  "B5:2 A5:2 G#5:2 F5:2 E5:8", "E6:4 D6:2 C6:2 B5:4 A5:2 G#5:2", "A5:2 B5:2 C6:2 B5:2 A5:2 G#5:2 F5:4",
                  "G5:3 A5:3 B5:2 A5:3 G5:3 F5:2", "E5:12 r:4")
    pb = [("Am", 16), ("G", 16), ("F", 16), ("E", 16), ("Am", 16), ("G", 16), ("F", 16), ("E7b9", 16)]
    tune_b = bars("A5:4 C6:4 E6:6 D6:2", "D6:4 B5:4 G5:6 A5:2", "C6:4 A5:4 F5:6 G5:2", "G#5:4 B5:4 E6:8",
                  "E6:2 D6:2 C6:2 E6:2 A6:8", "G6:2 F6:2 E6:2 D6:2 B5:8", "C6:2 D6:2 E6:2 F6:2 E6:2 D6:2 C6:2 A5:2", "G#5:4 F5:4 E5:8")
    fal = bars("E5:1 F5:1 G#5:1 A5:1 B5:2 A5:1 G#5:1 F5:1 E5:1 F5:1 E5:1 D5:2 C5:2", "C5:1 D5:1 E5:1 F5:1 A5:2 G5:1 F5:1 E5:1 D5:1 C5:1 B4:1 C5:2 A4:2",
               "B4:1 C5:1 D5:1 G5:1 B5:2 A5:1 G5:1 F5:1 E5:1 D5:1 C5:1 B4:2 G4:2", "A4:1 B4:1 C5:1 D5:1 E5:2 D5:1 C5:1 B4:1 A4:1 G#4:1 F4:1 E4:4")
    kit = "k.k.s..kk.k.s..."
    hats = "h.n.h.n.h.n.h.nN"
    stab_b = "X..X..X...X.X..."
    s.part("intro", 2, chug=riff_chug, bass=riff_bass, perc=rep("n.n.n.n.n.n.nnnn", 2), kit=rep("k.......k.......", 2, "k.......s.s.SSSS"))
    s.part("A", 8, tp=tune_a, lead=transpose(tune_a, -12), chug=riff_chug * 4, power=riff_pow * 4, bass=riff_bass * 4,
           kit=rep(kit, 8, "k.k.s..kk.s.s.ss"), perc="c" + rep(hats, 8)[1:])
    s.part("B", 8, tp=tune_b, brass=comp(pb, stab_b, "A3", "D5"), power=bassline(pb, "R:3 R:3 R:2 R:4 R:4", "A1"),
           bass=bassline(pb, "R:3 R:3 R:2 O:2 R:2 5d:2 R:2", "E1"), orch=bars(*["r:16"] * 7, "E4:2> r:2 F4:2> r:2 E4:2> r:6"),
           kit=rep("k..ks..kk..ks...", 8, "k..ks..ks.s.SSSS"), perc="c" + rep("o.h.o.h.o.h.o.h.", 8)[1:])
    climb = [("E", 16), ("F", 16), ("G", 16), ("A", 16)]
    s.part("C", 8, gtr=fal + " " + rest(4), bass=bars("E1:16", "F1:16", "G1:16", "E1:8 r:8") + " " + bassline(climb, "R:2 R:2 R:2 R:2 R:2 R:2 R:2 R:2", "E1"),
           power=rest(4) + " " + bars("E2:16", "F2:16", "G2:16", "A2:16"),
           lead=rest(4) + " " + bars("B4:16", "C5:16", "D5:16", "E5:8 F5:4 G#5:4"),
           orch=rest(4) + " " + bars("E4:2> r:14", "F4:2> r:14", "G4:2> r:14", "A4:2> r:2 A4:2> r:2 A4:2> A4:2> A4:2> A4:2>"),
           kit=rep("P.......P.....P.", 4) + rep("k...s...k...s...", 4, "k.k.s.s.SSSSSSSS"),
           perc=rep("y.v.Y.vyy.v.Y.vv", 4) + "c" + rep("h.h.h.h.h.h.h.h.", 4)[1:])
    s.part("D", 4, tp=bars("E6:2 D6:2 C6:2 B5:2 C6:4 B5:4", "A5:2 G#5:2 F5:2 G#5:2 E5:8") * 2, brass=comp([("E5", 16)] * 4, "X..X..X...X.X...", "B3", "E5"),
           chug=riff_chug * 2, power=riff_pow * 2, bass=riff_bass * 2, kit=rep(kit, 4, "k.k.s.s.SSSSSSSS"), perc="c" + rep(hats, 4)[1:])
    return s.form(["intro"], ["A", "B", "C", "D"])


# ------------------------------------------------------------------ the tractor: a chase

@song
def tractor():
    """B flat major, 168 BPM: the tractor chase, a village charanga (brass band) at full tilt. Oom-pah: a tuba (the trombone, low)
    on the beat, brass chords off it, a marching snare and the bass drum with cymbals; the trumpets race up and down the chords; a
    G minor trio for the trombone, comic and pompous, the trumpets stabbing; a break on F7 with ¡olé! hits and a chromatic climb."""
    s = Song("tractor", 168, "B flat major", about="tractor chase")
    s.track("tp1", 0, 56, 106, -0.1, 25).track("tp2", 1, 56, 84, 0.2, 25).track("bone", 2, 57, 108, 0.1, 25)
    s.track("tuba", 3, 57, 104, 0, 10).track("brass", 4, 61, 80, 0.35, 20).track("bass", 5, 38, 80, 0)
    s.track("kit", 9, 0, 100).track("perc", 9, 0, 100)
    pa = [("Bb", 16), ("Eb", 16), ("F7", 16), ("Bb", 16), ("Bb", 16), ("Eb", 16), ("F7", 16), ("Bb", 16)]
    pb = [("Gm", 16), ("Cm", 16), ("F7", 16), ("Bb", 16), ("Gm", 16), ("Cm", 16), ("D7", 16), ("F7", 16)]
    tune_a = bars("F5:2 Bb5:2 D6:2 Bb5:2 F5:2 Bb5:2 D6:4", "Eb6:2 D6:2 C6:2 Bb5:2 G5:4 Eb5:4", "F5:2 A5:2 C6:2 Eb6:2 D6:2 C6:2 A5:4",
                  "Bb5:4 F5:2 D5:2 Bb4:4 r:4", "D5:2 F5:2 Bb5:2 D6:2 F6:4 D6:4", "Eb6:2 G6:2 F6:2 Eb6:2 C6:4 G5:4",
                  "A5:2 C6:2 F6:2 Eb6:2 C6:2 A5:2 F5:4", "Bb5:4 D6:2 Bb5:2 F5:4 r:4")
    bone_b = bars("G3:2 A3:2 Bb3:2 D4:2 G4:4 D4:4", "Eb4:2 D4:2 C4:2 Bb3:2 G3:4 C4:4", "F3:2 A3:2 C4:2 Eb4:2 D4:2 C4:2 A3:4",
                  "Bb3:4 D4:4 F4:8", "G4:2 F4:2 D4:2 Bb3:2 G3:4 Bb3:4", "C4:2 Eb4:2 G4:2 Eb4:2 C4:8",
                  "D4:2 F#4:2 A4:2 F#4:2 D4:4 A3:4", "F4:4 Eb4:4 C4:4 A3:4")
    oom = "R:4 5d:4 R:4 5d:4"
    pah = "..x...x...x...x."
    march = "k.s.s.ssk.s.s.s."
    cym = "..j...j...j...j."
    s.part("intro", 1, tp1="F5:2 r:2 F5:2 r:2 F5:4/3 F5:4/3 F5:4/3 E5:2 Eb5:2 |", brass="A3+C4+Eb4:2> r:2 A3+C4+Eb4:2> r:2 A3+C4+Eb4:4> r:4 |",
           tuba="F2:2 r:2 F2:2 r:2 F2:4 r:4 |", kit="ssssssssSSSSSSSS|", perc="c...............|")
    s.part("A", 8, tp1=tune_a, tp2=second_voice(tune_a, pa, SCALE_BB), tuba=bassline(pa, oom, "Bb1"), bass=bassline(pa, oom, "Bb1"),
           brass=comp(pa, pah, "D4", "F5"), kit=rep(march, 8, "k.s.s.ssk.s.SSSS"), perc="c" + rep(cym, 8)[1:])
    s.part("B", 8, bone=bone_b, tp1=bars("r:16", "r:12 G5:2 Bb5:2", "C6:4 r:12", "r:8 D6:2 C6:2 Bb5:2 F5:2",
                                                "r:16", "r:12 G5:2 C6:2", "D6:4 r:4 F#5:2 A5:2 C6:2 D6:2", "Eb6:4 C6:4 A5:4 F5:4"),
           tuba=bassline(pb, oom, "Bb1"), bass=bassline(pb, oom, "Bb1"), brass=comp(pb, "..x...x...x.x.x.", "D4", "F5"),
           kit=rep("k.s.s.ssk.s.s.ss", 8, "k.s.s.ssk.SSSSSS"), perc="c" + rep("..j...j...j.j.j.", 8)[1:])
    s.part("C", 4, brass=comp([("F7", 16)] * 4, "X..X..X.....X.X.", "C4", "Eb5"), tuba=bars("F2:2 r:4 F2:2 r:4 F2:4", "F2:2 r:4 F2:2 r:4 F2:4", "F2:2 r:4 F2:2 r:4 F2:4", "C2:4 D2:4 Eb2:4 E2:4"),
           tp1=bars("r:16", "r:16", "A5:2 C6:2 Eb6:2 F6:2 Eb6:2 C6:2 A5:2 F5:2", "C5:4 D5:4 Eb5:4 E5:4"),
           tp2=bars("r:16", "r:16", "F5:2 A5:2 C6:2 Eb6:2 C6:2 A5:2 F5:2 Eb5:2", "A4:4 Bb4:4 C5:4 C#5:4"),
           kit=rep("K..K..K.....s.s.", 3, "k.k.k.k.ssssSSSS"), perc=rep("c..c..c.....P.P.", 3, "................"))
    return s.form(["intro"], ["A", "B", "C"])


# ------------------------------------------------------------------ zone 3: the beach at sunset

@song
def playa():
    """E phrygian dominant (E F G F E, the Arabic-Andalusian colour), 116 BPM: the beach at sunset, a surf-rumba. Laid back first:
    nylon guitar broken chords, an accordion's long-breathed tune, cajón and tambourine; then urgent: the distorted guitar tremolo
    picking a surf line, tom-heavy drums, the brass hitting; a calm bridge of strings and castanets back to the start."""
    s = Song("playa", 116, "E phrygian dominant", about="zone 3, beach")
    s.track("acc", 0, 21, 120, -0.15, 40).track("arp", 1, 24, 92, 0.3, 30).track("bass", 2, 32, 118, 0)
    s.track("surf", 3, 30, 66, -0.25, 40).track("brass", 4, 61, 80, 0.3, 20).track("strings", 5, 48, 60, 0.15, 40)
    s.track("power", 6, 29, 64, 0.4, 20).track("kit", 9, 0, 96).track("perc", 9, 0, 96)
    p = [("E", 16), ("F", 16), ("E", 16), ("F", 16), ("G", 16), ("F", 16), ("E", 16), ("E", 16)]
    acc_a = bars("E5:6 F5:2 G#5:4 B5:4", "C6:6 B5:2 A5:4 F5:4", "G#5:6 F5:2 E5:8", "F5:2 G#5:2 A5:2 C6:2 A5:4 F5:4",
                 "G5:6 A5:2 B5:4 D6:4", "C6:6 A5:2 F5:4 A5:4", "G#5:4 F5:2 E5:2 F5:2 E5:2 D5:2 C5:2", "B4:16")
    surf = bars("E5:2 F5:2 G#5:2 A5:2 B5:4 A5:2 G#5:2", "A5:2 G#5:2 F5:2 E5:2 F5:8", "E5:2 F5:2 G#5:2 A5:2 B5:4 C6:2 B5:2",
                "C6:2 B5:2 A5:2 G#5:2 A5:8", "B5:2 C6:2 D6:2 C6:2 B5:4 A5:2 G5:2", "A5:2 B5:2 C6:2 B5:2 A5:4 G#5:2 F5:2",
                "G#5:2 F5:2 E5:2 F5:2 G#5:2 A5:2 B5:4", "E6:8 r:8")
    order = [0, 1, 2, 3, 2, 1, 2, 1]
    s.part("intro", 2, strings=comp([("E", 16), ("F", 16)], "x---------------", "G#3", "C5"), arp=arp([("E", 16), ("F", 16)], order, "E3", "E4", 2, 4),
           perc=rep("....e.......e...", 2, "....e...n.n.nnNN"), bass="E1:16 | F1:16 |")
    s.part("A", 8, acc=acc_a, arp=arp(p, order, "E3", "E4", 2, 4), bass=bassline(p, "R:6 5d:2 R:4 5d:4", "E1"),
           kit=rep("y.....v.y.y...v.", 8).replace("y", "y"), perc=rep("....e.......e.e.", 8, "....e...n.n.nnNN"))
    s.part("B", 8, surf=tremolo(surf), power=bassline(p, "R:3 R:3 R:2 R:3 R:3 R:2", "A1"), brass=comp(p, "X..X..X.........", "G#3", "C5"),
           bass=bassline(p, "R:2 R:2 O:2 R:2 R:2 R:2 O:2 R:2", "E1"),
           kit=rep("k.f.s.ffk.f.s.f.", 8, "k.f.s.fft.t.m.M."), perc="c" + rep("E.e.E.e.E.e.E.e.", 8)[1:])
    s.part("C", 4, strings=comp([("F", 16), ("E", 16), ("F", 16), ("E", 16)], "x---------------", "G#3", "C5"),
           arp=arp([("F", 16), ("E", 16), ("F", 16), ("E", 16)], [3, 2, 1, 0, 1, 2, 3, 2], "E3", "E4", 2, 4),
           bass=bars("F1:16", "E1:16", "F1:16", "E1:8 r:8"), perc=rep("n.......n.n.....", 4, "n.n.n.n.nnnnNNNN"))
    return s.form(["intro"], ["A", "B", "C"])


# ------------------------------------------------------------------ the boss

@song
def jefe():
    """E phrygian dominant to A minor, 168 BPM: El Gran Gaviotrón, flamenco-metal. Orchestra hits swinging E to F over timpani and a
    castanet roll; galloping palm-muted chugs on E with stabs on G, F and the tritone; a distorted lead in the phrygian dominant;
    a minor chorus on the trumpet down the circle (Am Dm G C F Dm E) with orchestra hits on every bar and double kicks; a break of
    timpani, strings sawing E F G# F and castanet rolls in sixteenth triplets, then everything at once climbing back."""
    s = Song("jefe", 168, "E phrygian / A minor", about="boss")
    s.track("lead", 0, 30, 76, -0.15, 30).track("tp", 1, 56, 104, 0.15, 30).track("brass", 2, 61, 84, 0.35, 20)
    s.track("bass", 3, 38, 110, 0).track("chug", 4, 28, 112, -0.4).track("power", 5, 29, 92, 0.4, 15)
    s.track("ost", 6, 49, 84, 0.25, 20).track("orch", 7, 55, 90, 0, 30).track("timp", 8, 47, 100, 0, 20)
    s.track("kit", 9, 0, 104).track("perc", 9, 0, 104)
    OST_E, OST_F = " ".join(["E4:1 F4:1 G#4:1 F4:1"] * 4), " ".join(["F4:1 G#4:1 A4:1 G#4:1"] * 4)
    gallop = "E2:2 E2:1 E2:1 E2:2 E2:1 E2:1 E2:2 E2:1 E2:1 r:4"
    s.part("intro", 4, orch="E4:2> r:2 E4:2> r:2 E4:2> r:6 | F4:2> r:2 F4:2> r:2 F4:2> r:6 | E4:2> r:2 E4:2> r:2 E4:2> r:6 | F4:2> r:2 F4:2> r:2 G#4:2> G#4:2> A4:2> B4:2> |",
           timp="E2:2 r:2 E2:2 r:2 E2:2 r:6 | F2:2 r:2 F2:2 r:2 F2:2 r:6 | E2:2 r:2 E2:2 r:2 E2:2 r:6 | " + " ".join(["E2:1"] * 16) + " |",
           ost=bars(*[OST_E] * 4), power="E2:16 | F2:16 | E2:16 | F2:8 r:8 |",
           perc="c...............|c...............|c...............|nnnnnnnnnnnnnnnnnnnnNNNN|",
           kit="K...............|K...............|K...............|DDDDDDDDssssSSSS|")
    riff = bars(gallop, gallop)
    pa_chug = bars(gallop, gallop, gallop, gallop, transpose(gallop, 1), transpose(gallop, 1), gallop, gallop)
    pa_pow = bars("r:12 G2:2 F2:2", "r:12 Bb2:2 A2:2", "r:12 G2:2 F2:2", "r:12 G#2:2 A2:2", "r:12 G#2:2 G2:2", "r:12 Bb2:2 A2:2",
                  "r:12 G2:2 F2:2", "r:8 F2:2 F2:2 E2:4")
    lead_a = bars("E5:4 F5:2 G#5:2 B5:4 A5:2 G#5:2", "F5:2 G#5:2 F5:2 E5:2 B4:8", "E5:4 F5:2 G#5:2 C6:4 B5:2 A5:2", "G#5:2 A5:2 G#5:2 F5:2 E5:8",
                  "F5:4 G#5:2 A5:2 C6:4 B5:2 A5:2", "G#5:2 A5:2 B5:2 C6:2 D6:4 C6:4", "E6:4 D6:2 C6:2 B5:2 A5:2 G#5:2 F5:2", "E5:8 r:8")
    pb = [("Am", 16), ("Dm", 16), ("G", 16), ("C", 16), ("F", 16), ("Dm", 16), ("E", 16), ("E7b9", 16)]
    tune_b = bars("A5:6 B5:2 C6:4 E6:4", "F6:6 E6:2 D6:4 A5:4", "B5:6 C6:2 D6:4 G6:4", "E6:6 D6:2 C6:4 G5:4", "A5:6 G5:2 C6:4 F6:4",
                  "F6:4 E6:2 D6:2 A5:4 D6:4", "G#6:4 F6:2 E6:2 D6:2 C6:2 B5:2 G#5:2", "E6:12 r:4")
    kit_a = "k.k.s.k.k.k.s.kk"
    s.part("A", 8, lead=lead_a, chug="v118 " + pa_chug, power=pa_pow, bass=pa_chug.replace("E2", "E1").replace("F2", "F1"),
           kit=rep(kit_a, 8, "k.k.s.k.s.s.SSSS"), perc="c" + rep("h.h.h.h.h.h.h.h.", 7)[1:] + "nnnnnnnnnnnnnnnnnnnnNNNN|")
    s.part("B", 8, tp=tune_b, lead=transpose(tune_b, -12), brass=comp(pb, "X-......X-......", "A3", "D5"),
           chug="v118 " + bassline(pb, "R:2 R:2 R:2 R:2 R:2 R:2 R:2 R:2", "A1"), bass=bassline(pb, "R:2 R:2 R:2 R:2 R:2 R:2 R:2 R:2", "E1"),
           orch=bassline(pb, "R.:2 r:14", "A3"), kit=rep("DDs.DDs.DDs.DDs.", 8, "DDs.DDs.s.s.SSSS"), perc="c" + rep("r.r.r.r.r.r.r.r.", 8)[1:])
    pc = [("E", 16), ("F", 16), ("E", 16), ("F", 16), ("E", 16), ("F", 16), ("G", 16), ("F", 16)]
    s.part("C", 8, ost=bars(OST_E, OST_F, OST_E, OST_F, OST_E, OST_F, OST_E, OST_F),
           timp=bars("E2:4 r:12", "F2:4 r:12", "E2:4 r:12", "F2:4 r:4 F2:2 F2:2 F2:2 F2:2") + " " + rest(4),
           orch=bars("r:16", "F4:2> r:14", "r:16", "F4:2> r:6 F4:2> r:6", "E4:2> r:14", "F4:2> r:14", "G4:2> r:14", "F4:2> r:2 F4:2> r:2 G#4:2> G#4:2> A4:2> B4:2>"),
           power=rest(4) + " " + bars("E2:16", "F2:16", "G2:16", "F2:16"), lead=rest(4) + " " + bars("B5:16", "C6:16", "D6:16", "C6:8 B5:8"),
           bass=rest(4) + " " + bassline(pc[4:], "R:2 R:2 R:2 R:2 R:2 R:2 R:2 R:2", "E1"),
           perc=rep("nnn.nnn.nnn.nnnnnnNNNNNN", 4) + "c" + rep("r.r.r.r.r.r.r.r.", 4)[1:],
           kit=rep("P.....P.....P.P.", 4) + rep("DDDDs.DDDDDDs.DD", 4, "DDDDs.s.SSSSSSSS"))
    return s.form(["intro"], ["A", "B", "C"])


# ------------------------------------------------------------------ the ending

@song
def fin():
    """D major, 100 BPM: the ending, the title's theme come home warm. The tune in D major on the accordion over nylon guitar
    broken chords, strings and a soft rumba of rim, shaker-like tambourine and cajón; the trio in G major (the title's F major one, a
    step up) on the trumpet with a glockenspiel over it; back to the start."""
    s = Song("fin", 100, "D major", about="ending")
    s.track("acc", 0, 21, 120, -0.15, 40).track("tp", 1, 56, 96, 0.1, 40).track("glock", 2, 9, 64, 0.4, 50)
    s.track("arp", 3, 24, 90, 0.3, 30).track("strings", 4, 48, 60, 0.0, 50).track("bass", 5, 32, 116, 0)
    s.track("tp2", 6, 56, 74, -0.2, 40).track("kit", 9, 0, 84).track("perc", 9, 0, 84)
    pa = [("D", 16), ("A7", 16), ("A7", 16), ("D", 16), ("D", 16), ("G", 16), ("A7", 16), ("D", 16)]
    pb = [("G", 16), ("D7", 16), ("D7", 16), ("G", 16), ("G7", 16), ("C", 16), ("D7", 16), ("G", 8), ("B7", 8)]
    tune_a = remap(TEMA_A, TO_MAJOR)
    tune_b = transpose(TEMA_B, 2).rsplit("|", 2)[0] + "| G6:8 E5:2 F#5:2 G5:2 C#5:2 |"
    order = [0, 1, 2, 3, 2, 1, 2, 1]
    s.part("intro", 2, arp=arp([("D", 16), ("A7", 16)], order, "D3", "D4", 2, 4), strings=comp([("D", 16), ("A7", 16)], "x---------------", "F#3", "A4"),
           bass="D2:16 | A1:16 |")
    s.part("A", 8, acc=tune_a, arp=arp(pa, order, "D3", "D4", 2, 4), strings=comp(pa, "x---------------", "F#3", "A4"),
           bass=bassline(pa, "R:6 5d:2 R:4 5d:4", "E1"), kit=rep("y.....x.y.y...x.", 8), perc=rep("e.e.E.e.e.e.E.e.", 8))
    pb_last = pb[:-2] + [("G", 8), ("A7", 8)]
    s.part("B", 8, tp=tune_b, tp2=second_voice(tune_b, pb_last, SCALE_G),
           glock=transpose(tune_b, 0).rsplit("|", 2)[0] + "| G6:8 r:8 |", arp=arp(pb_last, order, "D3", "D4", 2, 4),
           strings=comp(pb_last, "x-------x-------", "G3", "B4"), bass=bassline(pb_last, "R:6 5d:2 R:4 5d:4", "E1"),
           kit=rep("y.....x.y.y...x.", 8, "y.....x.y.x.x.xx"), perc=rep("e.e.E.e.e.e.E.e.", 8))
    return s.form(["intro"], ["A", "B"])


# ------------------------------------------------------------------ the continue countdown

@song
def continue_():
    """D minor, 120 BPM, an 8-second loop: the continue countdown. A clock (rim and castanet, tick and tock), the timpani's heartbeat,
    short strings pulsing in eighths over Dm Bb Gm A7b9 with a held line climbing D Eb F G# A, the bass on D underneath."""
    s = Song("continue", 120, "D minor", about="continue countdown")
    s.track("ost", 0, 49, 92, 0.25, 20).track("pad", 1, 48, 66, -0.2, 40).track("timp", 2, 47, 104, 0, 20)
    s.track("bass", 3, 38, 96, 0).track("bone", 4, 57, 80, -0.3, 30).track("kit", 9, 0, 127)
    p = [("Dm", 16), ("Bb", 16), ("Gm", 16), ("A7b9", 16)]
    s.part("A", 4, ost=arp(p, [0, 1, 2, 1], "D4", "D5", 2, 3), pad=bars("D5:16", "D5:8 Eb5:8", "F5:16", "G#5:8 A5:8"),
           bone=bars("D3:16", "F3:16", "G3:16", "A3:12 r:4"),
           timp=bars("D2:4 r:4 D2:4 r:4", "D2:4 r:4 D2:4 r:4", "D2:4 r:4 D2:4 r:4", "A1:4 r:4 A1:2 A1:2 A1:2 A1:2"),
           bass=bars("D2:2 r:6 D2:2 r:6", "Bb1:2 r:6 Bb1:2 r:6", "G1:2 r:6 G1:2 r:6", "A1:2 r:6 A1:2 r:2 A1:2 C#2:2"),
           kit=rep("x...n...x...n...", 4, "x...n...x.n.nnnN"))
    return s.form([], ["A"])


SONGS["continue"] = SONGS.pop("continue_")


# ------------------------------------------------------------------ jingles (played once)

def jingle(name: str, bpm: float, key: str, beats: int = 4, about: str = "") -> Song:
    return Song(name, bpm, key, beats=beats, jingle=True, about=about)


@song
def victoria():
    """D major, 132 BPM, 6 s: mission complete. The theme's opening as a fanfare in D major (D A D E F# G | A G F# E C#), the second
    trumpet a third under, castanets, the band hitting the chords, timpani, and a held D chord with a crash and a strummed guitar."""
    s = jingle("victoria", 132, "D major", about="mission complete")
    s.track("tp1", 0, 56, 106, -0.1, 30).track("tp2", 1, 56, 86, 0.15, 30).track("brass", 2, 61, 84, 0.3, 30)
    s.track("bass", 3, 38, 104, 0).track("strum", 4, 24, 84, -0.3, 30, strum=4).track("timp", 5, 47, 100, 0, 20)
    s.track("orch", 6, 55, 80, 0, 30).track("glock", 7, 9, 70, 0.4, 40).track("kit", 9, 0, 100).track("perc", 9, 0, 100)
    p = [("D", 16), ("A7", 16), ("D", 16)]
    tune = "D5:3 A4:1 D5:2 E5:2 F#5:2 G5:2 A5:4 | B5:3 A5:1 G5:2 F#5:2 E5:2 C#5:2 A4:4 | D6:12 r:4 |"
    s.part("a", 3, tp1=tune, tp2=second_voice(tune, p, SCALE_D), brass="r:16 | r:16 | D4+F#4+A4:12> r:4 |",
           bass="D2:4 A1:4 D2:4 A1:4 | A1:4 E2:4 A1:4 C#2:4 | D2:12 r:4 |", strum="r:16 | r:16 | D3+A3+F#4:12 r:4 |",
           timp="D2:4 r:4 A1:4 r:4 | A1:4 r:4 A1:2 A1:2 A1:2 A1:2 | D2:4 r:12 |", orch="r:16 | r:16 | D4:4> r:12 |",
           glock="r:16 | r:16 | r:1 D7:1 F#7:1 A7:4 r:9 |",
           kit="k...s...k...s...|k...s...k.s.ssss|K...............|", perc="..n...n...n...n.|..n...n...nnnnNN|c...............|")
    return s.form(["a"], [])


@song
def rescate():
    """G major, 150 BPM, 1.6 s: an abuela freed. The accordion skips up and back (D G B D C A F# A) to a G, castanets and palmas
    clapping along, a staccato brass chord and the bass going oom-pah: a little ¡olé!"""
    s = jingle("rescate", 150, "G major", about="abuela freed")
    s.track("acc", 0, 21, 106, 0, 30).track("brass", 1, 61, 84, 0.3, 30).track("bass", 2, 32, 116, 0)
    s.track("perc", 9, 0, 100)
    s.part("a", 1, acc="D5:1 G5:1 B5:1 D6:1 C6:1 A5:1 F#5:1 A5:1 G5:4 r:4 |", brass="r:8 B3+D4+G4:2.> r:2 B3+D4+G4:2.> r:2 |",
           bass="G1:2 D2:2 G1:2 D2:2 G1:4 r:4 |", perc="n.nNn.n.P...P...|")
    return s.form(["a"], [])


@song
def arma():
    """D major, 150 BPM, a 2/4 bar (0.8 s): a weapon picked up. The trumpets shoot up D F# A to a high D with the brass and an
    orchestra hit, the glockenspiel glinting, a crash."""
    s = jingle("arma", 150, "D major", beats=2, about="weapon get")
    s.track("tp1", 0, 56, 106, 0, 30).track("tp2", 1, 56, 86, 0.2, 30).track("brass", 2, 61, 86, -0.3, 30)
    s.track("orch", 3, 55, 84, 0, 30).track("glock", 4, 9, 76, 0.4, 40).track("kit", 9, 0, 100)
    s.part("a", 1, tp1="D5:1 F#5:1 A5:1 D6:5 |", tp2="A4:1 D5:1 F#5:1 A5:5 |", brass="r:3 D4+F#4+A4+D5:5> |", orch="r:3 D4:5> |",
           glock="r:3 D7:1 F#7:1 A7:3 |", kit="...C....|")
    return s.form(["a"], [])


@song
def muerte():
    """C minor, 120 BPM, 2 s: a cook down, comic. A slide whistle (the flute) tumbling down twelve semitones, then the trombone's
    ¡bwomp! sagging two semitones over a low C and a tom."""
    s = jingle("muerte", 120, "C minor", about="player death")
    s.track("whistle", 0, 73, 100, 0, 30).track("bone", 1, 57, 112, 0, 30).track("bass", 2, 32, 112, 0).track("kit", 9, 0, 100)
    s.part("a", 1, whistle="G6:1_ F#6:1_ F6:1_ E6:1_ Eb6:1_ D6:1_ C#6:1_ C6:1_ B5:1_ Bb5:1_ A5:1_ Ab5:1_ G5:1' r:3 |",
           bone="r:12 ~0 C3:1 ~0>-2:3 -:3 |", bass="r:12 C2:4 |", kit="............F...|")
    return s.form(["a"], [])


@song
def game_over():
    """G minor, 3/4 at 96 BPM, 3.8 s: game over, sad and funny. The trombone's wah-wah-wah-waaah (G F# F, then E wobbling as a
    plunger mute would), a tuba-low bass falling with it, a sighing accordion chord."""
    s = jingle("game_over", 96, "G minor", beats=3, about="game over")
    s.track("bone", 0, 57, 112, 0, 30).track("acc", 1, 21, 62, 0.3, 40).track("bass", 2, 32, 112, 0).track("kit", 9, 0, 90)
    wobble = " ".join(f"~0>-0.6:1 -:1 ~-0.6>0:1 -:1" for _ in range(4))
    s.part("a", 2, bone="G3:4 F#3:4 F3:4 | E3:2 " + wobble + " ~0>-1.5:2 -:2 |",
           acc="Bb3+D4+G4:4 A3+C#4+F#4:4 A3+C4+F4:4 | G3+Bb3+E4:12 |", bass="G2:4 F#2:4 F2:4 | E2:8 r:4 |",
           kit="F...F...F...|............|")
    return s.form(["a"], [])


# ------------------------------------------------------------------ main

# each song's master trim (its channels' volume times this), from the --check loudness numbers (K-weighted): the songs at about
# -16, the jingles a dB over them (the continue cue, tense and sparse, at -17)
LEVELS: dict[str, float] = {
    "titulo": 0.87, "seleccion": 1.01, "puerto": 1.02, "calle": 0.94, "tractor": 0.85, "playa": 1.19, "jefe": 0.85, "fin": 0.94,
    "continue": 1.41, "victoria": 0.97, "rescate": 1.38, "arma": 0.92, "muerte": 1.72, "game_over": 1.35,
}


def make(name: str) -> Song:
    s = SONGS[name]()
    s.master = LEVELS.get(name, 1.0)
    return s


def main(argv: list[str]) -> None:
    if "--wavs" in argv:
        from music_bank import write_wavs
        print(write_wavs(Path(argv[argv.index("--wavs") + 1])))
        return
    if "--check" in argv:
        from music_check import check_all
        i = argv.index("--check")
        check_all(Path(argv[i + 1]), [a for a in argv[i + 2:] if not a.startswith("-")] or list(SONGS), make)
        return
    audio = GAME / "audio"
    audio.mkdir(exist_ok=True)
    if "--bank" in argv or not (audio / "BANK.bank").exists():
        from music_bank import build_bank
        path, size = build_bank()
        print(f"{path}: {size // 1024} KB")
    names = [a for a in argv if not a.startswith("-")] or list(SONGS)
    print(f"{'song':10} {'key':22} {'meter':5} {'BPM':>4} {'intro s':>7} {'loop s':>7} {'bytes':>6}  about")
    for name in names:
        s = make(name)
        info = write_smf(s, audio / f"{name}.mid")
        size = (audio / f"{name}.mid").stat().st_size
        intro = s.seconds(info["loop_start"]) if not s.jingle else s.seconds(info["music_end"])
        body = s.seconds(info["loop_end"] - info["loop_start"]) if not s.jingle else 0.0
        print(f"{name:10} {s.key:22} {s.beats}/4   {s.bpm:4.0f} {intro:7.1f} {body:7.1f} {size:6}  {s.about}")


if __name__ == "__main__":
    main(sys.argv[1:])
