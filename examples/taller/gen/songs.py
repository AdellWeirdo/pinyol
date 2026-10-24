#!/usr/bin/env python3
"""Taller de los Autómatas' music: every song and jingle as a Standard MIDI File (audio/<name>.mid) played by the game's bank of
samples (audio/BANK.bank): music("calle", 0, {bank = "BANK"}). A clockwork arcade soundtrack for a CPS2-style beat 'em up in a
Victorian city of clockmakers: music box, glockenspiel and clock bells, accordion, brass band, pizzicato strings, steam organ,
wood blocks, ticks, ratchets and anvils, over a march or waltz-rock beat. Songs: titulo seleccion calle fabrica torre jefe fin
(loops) victoria game_over (jingles) continue (a 10 second countdown loop). Adapted from examples/paella/gen/songs.py.

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
    SONGS[fn.__name__.rstrip("_")] = fn  # (continue_: `continue` is a keyword)
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




# ------------------------------------------------------------------ title

TEMA_A = bars("A4:2 D5:2 F5:2 A5:2 G5:4 F5:4", "E5:2 F5:2 G5:2 E5:2 D5:8", "D5:2 F5:2 Bb5:2 A5:2 G5:4 F5:4",
              "E5:2 G5:2 A5:2 G5:2 E5:4 C#5:4", "A4:2 D5:2 F5:2 A5:2 D6:4 A5:4", "Bb5:4 A5:2 G5:2 F5:4 D5:4",
              "E5:2 F5:2 G5:2 A5:2 G5:2 F5:2 E5:2 C#5:2", "D5:12 r:4")
TEMA_PA = [("Dm", 16), ("Dm", 16), ("Bb", 16), ("A7", 16), ("Dm", 16), ("Gm", 16), ("A7", 16), ("Dm", 16)]
TEMA_B = bars("C5:2 F5:2 A5:2 C6:2 A5:4 F5:4", "G5:2 E5:2 C5:2 E5:2 G5:8", "D5:2 F5:2 Bb5:2 D6:2 C6:4 Bb5:4", "A5:6 G5:2 F5:8",
              "F5:2 A5:2 D6:2 C6:2 A5:4 F5:4", "G5:2 Bb5:2 D6:2 Bb5:2 A5:4 G5:4", "E5:2 G5:2 Bb5:2 G5:2 E5:2 G5:2 C6:4", "F5:12 r:4")
TEMA_PB = [("F", 16), ("C", 16), ("Bb", 16), ("F", 16), ("Dm", 16), ("Gm", 16), ("C7", 16), ("F", 16)]


@song
def titulo():
    """D minor to F major, 138 BPM: the title. Clock bells and a music-box arpeggio over ticking wood blocks and timpani, a ratchet
    winding up; then the tune on two trumpets in thirds over an accordion's off-beat chords and an oom-pah FM bass, rock drums
    and wood blocks; the bridge in F major with the music box an octave over the trumpets and pizzicato strings."""
    s = Song("titulo", 138, "D minor / F major", about="title")
    s.track("tp1", 0, 56, 104, -0.1, 30).track("tp2", 1, 56, 84, 0.15, 30).track("acc", 2, 21, 76, 0.3, 20)
    s.track("bass", 3, 38, 112, 0).track("bell", 4, 14, 84, -0.2, 40).track("mb", 5, 10, 86, 0.25, 40)
    s.track("timp", 6, 47, 98, 0, 20).track("pizz", 7, 45, 84, -0.3, 20).track("kit", 9, 0, 100).track("perc", 9, 0, 100)
    ip = [("Dm", 16), ("Dm", 16), ("Bb", 16), ("A7", 16)]
    s.part("intro", 4, bell="D5:16 | r:16 | Bb4:16 | A4:16 |", mb=arp(ip, [0, 1, 2, 1], "A4", "F6", 2, 3),
           timp="D2:4 r:12 | r:16 | Bb1:4 r:12 | " + " ".join(["A1:2"] * 8) + " |",
           kit="K...............|................|K.......k.......|k.k.s.s.ssssSSSS|",
           perc=rep("z...z...z...z...", 3, "zzzzzzzzZZZZZZZZ") + "")
    s.part("A", 8, tp1=TEMA_A, tp2=second_voice(TEMA_A, TEMA_PA, SCALE_DM), acc=comp(TEMA_PA, "..x...x...x...x.", "A3", "D5"),
           bass=bassline(TEMA_PA, "R:4 5d:4 R:4 5d:4", "A1"), kit=rep("k...s...k.k.s...", 8, "k...s...k.s.s.ss"),
           perc=rep("z.w.z.w.z.w.z.W.", 8), bell="D4:16 | r:16 | Bb3:16 | A3:16 | D4:16 | r:16 | A3:16 | D4:16 |")
    s.part("B", 8, tp1=TEMA_B, tp2=second_voice(TEMA_B, TEMA_PB, SCALE_F), mb=transpose(TEMA_B, 12),
           pizz=comp(TEMA_PB, "..x...x...x...x.", "A3", "C5"), bass=bassline(TEMA_PB, "R:4 5d:4 R:4 5d:4", "A1"),
           kit=rep("k...s..kk...s...", 8, "k...s..kk.s.SSSS"), perc=rep("z.z.z.z.z.z.z.z.", 8), timp=rep("r:16", 7)[:-1] + " | D2:2 D2:2 D2:2 D2:2 F2:2 F2:2 A2:2 A2:2 |")
    return s.form(["intro"], ["A", "B"])


# ------------------------------------------------------------------ the character select: a music-box waltz

@song
def seleccion():
    """G minor to B flat major, 3/4, 126 BPM: choosing a clockmaker. A music-box waltz: the tune on the music box, an accordion
    holding the chords, a pizzicato oom-pah-pah and a ticking wood block; the second half in B flat with a glockenspiel over it."""
    s = Song("seleccion", 126, "G minor / B flat major", beats=3, about="character select")
    s.track("mb", 0, 10, 100, -0.15, 40).track("glock", 1, 9, 72, 0.3, 40).track("acc", 2, 21, 62, 0.25, 20)
    s.track("pizz", 3, 45, 86, -0.3, 20).track("bass", 4, 32, 112, 0).track("kit", 9, 0, 100)
    pa = [("Gm", 12), ("Gm", 12), ("Cm", 12), ("D7", 12), ("Gm", 12), ("Eb", 12), ("D7", 12), ("Gm", 12)]
    ma = bars("G5:4 Bb5:4 D6:4", "C6:4 Bb5:2 A5:2 G5:4", "Eb5:4 G5:4 C6:4", "A5:6 F#5:2 D5:4",
              "G5:4 Bb5:4 D6:4", "Eb6:4 D6:2 C6:2 Bb5:4", "A5:4 C6:4 F#5:4", "G5:8 r:4")
    pb = [("Bb", 12), ("Bb", 12), ("F", 12), ("F", 12), ("Eb", 12), ("Cm", 12), ("D7", 12), ("D7", 12)]
    mbb = bars("D6:4 C6:2 Bb5:2 F5:4", "D6:4 F6:4 D6:4", "C6:4 A5:2 C6:2 F6:4", "C6:6 A5:2 F5:4",
               "G5:4 Bb5:4 Eb6:4", "C6:4 Eb6:4 G6:4", "F#5:4 A5:4 D6:4", "C6:6 A5:2 F#5:4")
    s.part("intro", 2, mb="D5:4 G5:4 Bb5:4 | A5:12 |", acc=comp(pa[:2], "x-----", "G3", "D5", 3, 12),
           kit="z..z..z..z..|z..z..zzzzzz|")
    wal = "k.....w...w."
    s.part("A", 8, mb=ma, acc=comp(pa, "x-----", "G3", "D5", 3, 12), pizz=comp(pa, "..x.x.", "G3", "D5", 2, 12),
           bass=bassline(pa, "R:4 r:4 r:4", "G1"), kit=rep(wal, 8))
    s.part("B", 8, mb=mbb, glock=transpose(mbb, 12), acc=comp(pb, "x-----", "Bb3", "F5", 3, 12), pizz=comp(pb, "..x.x.", "Bb3", "F5", 2, 12),
           bass=bassline(pb, "R:4 r:4 r:4", "Bb1"), kit=rep(wal, 8, "k.....w.w.ww"))
    return s.form(["intro"], ["A", "B"])


# ------------------------------------------------------------------ stage 1: a street at night

@song
def calle():
    """E minor to G major, 128 BPM: the foggy streets at night. A walking pizzicato-bass march, an accordion singing a minor tune,
    brass stabs on the off beats, clock-tick wood blocks; the second half in G major with the brass carrying the tune."""
    s = Song("calle", 128, "E minor / G major", about="stage 1, a street at night")
    s.track("acc", 0, 21, 100, -0.1, 25).track("brass", 1, 61, 80, 0.3, 20).track("bass", 2, 32, 116, 0).track("pizz", 3, 45, 84, -0.3, 20)
    s.track("bell", 4, 14, 76, 0.2, 40).track("mb", 5, 10, 70, 0.35, 40).track("kit", 9, 0, 100).track("perc", 9, 0, 100)
    pa = [("Em", 16), ("Em", 16), ("C", 16), ("B7", 16), ("Em", 16), ("Am", 16), ("B7", 16), ("Em", 16)]
    ma = bars("B4:2 E5:2 G5:4 F#5:2 E5:2 B4:4", "G5:2 A5:2 B5:4 G5:4 E5:4", "E5:2 G5:2 C6:4 B5:2 G5:2 E5:4",
              "D#5:2 F#5:2 B5:4 A5:2 F#5:2 D#5:4", "B4:2 E5:2 G5:4 B5:4 E6:4", "A5:4 C6:4 B5:2 A5:2 E5:4",
              "F#5:2 A5:2 B5:2 A5:2 F#5:2 D#5:2 F#5:4", "E5:12 r:4")
    pb = [("G", 16), ("D", 16), ("Em", 16), ("C", 16), ("G", 16), ("D", 16), ("C", 16), ("B7", 16)]
    mb_ = bars("B5:2 D6:2 G6:4 F#6:2 D6:2 B5:4", "A5:2 D6:2 F#6:4 E6:2 D6:2 A5:4", "G5:2 B5:2 E6:4 D6:2 B5:2 G5:4",
               "E5:2 G5:2 C6:4 B5:2 G5:2 E5:4", "B5:2 D6:2 G6:4 E6:4 D6:4", "F#6:4 E6:2 D6:2 A5:4 F#5:4",
               "E6:4 D6:2 C6:2 G5:4 E5:4", "D#5:2 F#5:2 B5:4 A5:2 F#5:2 D#5:4")
    s.part("intro", 2, bell="E5:16 | B4:16 |", mb="r:16 | " + arp([("B7", 16)], [0, 1, 2, 3], "B3", "F#5", 4, 4),
           perc="z...z...z...z...|z...z...z...zzzz|", kit="K...............|k...k...k.k.s.s.|")
    s.part("A", 8, acc=ma, brass=comp(pa, "..x...x...x...x.", "E3", "B4"), bass=bassline(pa, "R:4 5:4 3:4 5:4", "E1"),
           pizz=comp(pa, "x.x.x.x.x.x.x.x.", "E3", "G4", 2), kit=rep("k...s...k.k.s...", 8, "k...s...k.s.s.ss"),
           perc=rep("w.z.W.z.w.z.W.z.", 8))
    s.part("B", 8, brass=mb_, acc=comp(pb, "x---x---x---x---", "G3", "D5"), bass=bassline(pb, "R:4 5:4 3:4 5:4", "G1"),
           pizz=comp(pb, "..x...x...x...x.", "G3", "D5", 2), mb=transpose(mb_, 12),
           kit=rep("k...s...k.k.s...", 8, "k.k.s.s.s.s.ssss"), perc=rep("z.z.z.z.z.z.z.z.", 8))
    return s.form(["intro"], ["A", "B"])


# ------------------------------------------------------------------ stage 2: the factory

@song
def fabrica():
    """C minor to A flat major, 146 BPM: a roaring factory. Anvil blows on the off beats, a gear ratchet, a slap-bass chug in
    eighths, a trombone riff with the trumpet on top, a steam organ holding the chords; the second half goes up to A flat
    major with the trumpet singing over timpani."""
    s = Song("fabrica", 146, "C minor / A flat major", about="stage 2, the factory")
    s.track("tb", 0, 57, 100, -0.15, 20).track("tp", 1, 56, 86, 0.2, 20).track("bass", 2, 36, 118, 0).track("organ", 3, 19, 62, 0.3, 30)
    s.track("strings", 4, 49, 70, -0.3, 30).track("timp", 5, 47, 96, 0, 20).track("bell", 6, 14, 70, 0.3, 40)
    s.track("kit", 9, 0, 100).track("perc", 9, 0, 100)
    pa = [("Cm", 16), ("Cm", 16), ("Ab", 16), ("Bb", 16), ("Cm", 16), ("Cm", 16), ("Fm", 16), ("G7", 16)]
    riff = bars("C5:3 C5:1 Eb5:2 G5:2 C6:4 Bb5:4", "C5:3 C5:1 Eb5:2 G5:2 Bb5:2 G5:2 Eb5:4", "Ab4:3 Ab4:1 C5:2 Eb5:2 Ab5:4 Eb5:4",
                "Bb4:3 Bb4:1 D5:2 F5:2 Bb5:4 F5:4", "C5:3 C5:1 Eb5:2 G5:2 C6:4 Bb5:4", "G5:2 Eb5:2 C5:2 Eb5:2 G5:4 C6:4",
                "F5:3 F5:1 Ab5:2 C6:2 F6:4 C6:4", "G5:2 B5:2 D6:2 F6:2 D6:2 B5:2 G5:4")
    pb = [("Ab", 16), ("Eb", 16), ("Fm", 16), ("Cm", 16), ("Ab", 16), ("Eb", 16), ("Bb", 16), ("G7", 16)]
    melb = bars("Eb6:4 C6:4 Ab5:4 C6:4", "Eb6:4 G6:4 Bb5:4 G5:4", "F6:4 Ab5:4 C6:4 F6:4", "G5:4 C6:4 Eb6:4 G6:4",
                "Eb6:2 F6:2 Eb6:2 C6:2 Ab5:4 C6:4", "G5:4 Bb5:4 Eb6:8", "D6:4 F6:4 Bb6:4 F6:4", "B5:2 D6:2 F6:2 D6:2 B5:2 G5:2 B5:4")
    s.part("intro", 2, perc="A...Z...A...Z...|A.A.Z.Z.AAAAZZZZ|", kit="k...............|k...k...k.k.s.s.|",
           bass=" ".join(["C2:2"] * 8) + " | " + " ".join(["C2:2"] * 8) + " |", timp="C2:4 r:12 | C2:2 C2:2 C2:2 C2:2 G1:2 G1:2 G1:2 G1:2 |")
    s.part("A", 8, tb=riff, tp=transpose(riff, 12), bass=bassline(pa, "R:2 R:2 R:2 R:2 R:2 R:2 5:2 R:2", "C1"),
           organ=comp(pa, "x---------------", "C3", "G4"), kit=rep("k.k.s...k.k.s...", 8, "k.k.s.k.s.s.ssss"),
           perc=rep("z.A.z.A.z.A.z.A.", 8, "z.A.z.AZZZZZZZZZ"))
    s.part("B", 8, tp=melb, strings=comp(pb, "x---x---x---x---", "Ab3", "Eb5"), tb=transpose(melb, -12), bass=bassline(pb, "R:4 R:4 R:4 5:4", "Ab1"),
           timp=bassline(pb, "R:4 r:4 R:4 r:4", "Ab1"), bell="Ab4:16 | Eb5:16 | F4:16 | C5:16 | Ab4:16 | Eb5:16 | Bb4:16 | G4:16 |",
           kit=rep("k...s...k...s...", 8, "k...s...k.s.s.SS"), perc=rep("A.z.z.z.A.z.z.z.", 8))
    return s.form(["intro"], ["A", "B"])


# ------------------------------------------------------------------ stage 3: inside the great clock tower

@song
def torre():
    """A minor to C major, 3/4, 138 BPM: inside the clock tower. A steam organ and strings holding the dread, a music box
    running arpeggios over a tick on every beat and a bell on every bar, the tune on organ and glockenspiel; the relief in C
    major, then back down the stairs to A minor."""
    s = Song("torre", 138, "A minor / C major", beats=3, about="stage 3, the clock tower")
    s.track("organ", 0, 19, 84, 0, 30).track("glock", 1, 9, 74, 0.3, 40).track("strings", 2, 48, 66, -0.25, 40)
    s.track("pizz", 3, 45, 84, -0.3, 20).track("bass", 4, 38, 108, 0).track("bell", 5, 14, 76, 0.2, 40)
    s.track("mb", 6, 10, 76, 0.35, 40).track("timp", 7, 47, 92, 0, 20).track("kit", 9, 0, 100)
    pa = [("Am", 12), ("F", 12), ("Dm", 12), ("E7", 12), ("Am", 12), ("F", 12), ("E7", 12), ("E7", 12)]
    ma = bars("A4:4 C5:4 E5:4", "F5:6 E5:2 C5:4", "D5:4 F5:4 A5:4", "G#5:6 B5:2 E5:4",
              "C6:4 B5:4 A5:4", "A5:4 C6:4 F6:4", "E6:4 D6:2 B5:2 G#5:4", "G#5:8 B5:4")
    pb = [("C", 12), ("G", 12), ("Am", 12), ("F", 12), ("C", 12), ("G", 12), ("F", 12), ("E7", 12)]
    mbb = bars("E5:4 G5:4 C6:4", "B5:4 D6:4 G5:4", "C6:4 E6:4 A5:4", "A5:6 G5:2 F5:4",
               "E6:4 G6:4 E6:4", "D6:6 B5:2 G5:4", "A5:4 C6:4 F6:4", "E6:4 B5:4 G#5:4")
    tick = "z..z..z..z..".replace("z", "z")
    s.part("intro", 2, bell="A4:12 | E5:12 |", mb=arp([("Am", 12), ("E7", 12)], [0, 1, 2, 1, 2, 1], "A3", "E5", 2, 3), kit=rep(tick, 2))
    s.part("A", 8, organ=ma, glock=transpose(ma, 12), strings=comp(pa, "x-----", "A3", "E5", 3, 12),
           mb=arp(pa, [0, 1, 2, 1, 2, 1], "A3", "E5", 2, 3), bass=bassline(pa, "R:6 5:3 5:3", "A1"),
           bell="A4:12 | F4:12 | D4:12 | E4:12 | A4:12 | F4:12 | E4:12 | E4:12 |", timp="A1:4 r:8 | " + " | ".join(["r:12"] * 7) + " |",
           kit=rep("z..z..z..z..", 8, "z..z..z.zzzz"))
    s.part("B", 8, organ=mbb, glock=transpose(mbb, 12), strings=comp(pb, "x-----", "C3", "G4", 3, 12),
           pizz=comp(pb, "..x.x.", "C4", "G5", 2, 12), mb=arp(pb, [0, 1, 2, 1, 2, 1], "C4", "G5", 2, 3), bass=bassline(pb, "R:6 5:3 5:3", "C1"),
           bell="C5:12 | G4:12 | A4:12 | F4:12 | C5:12 | G4:12 | F4:12 | E4:12 |", kit=rep("k..z..z..z..", 8, "k..z..z.zzzz"))
    return s.form(["intro"], ["A", "B"])


# ------------------------------------------------------------------ the boss

@song
def jefe():
    """D minor, 150 BPM: the grandfather-clock golem. A gallop of slap bass, trumpet and trombone on a driving riff, orchestra hits
    and timpani on the changes, bell strokes like a clock striking, a ratchet in the fills; then a heavy section of long
    brass over a steam organ and tremolo strings, ending on the dominant."""
    s = Song("jefe", 150, "D minor", about="boss")
    s.track("tp", 0, 56, 102, -0.15, 20).track("tb", 1, 57, 96, 0.15, 20).track("orch", 2, 55, 84, 0, 30).track("timp", 3, 47, 100, 0, 20)
    s.track("bass", 4, 36, 118, 0).track("organ", 5, 19, 64, 0.3, 30).track("strings", 6, 48, 68, -0.3, 30).track("bell", 7, 14, 80, 0.25, 40)
    s.track("kit", 9, 0, 100).track("perc", 9, 0, 100)
    pa = [("Dm", 16), ("Dm", 16), ("Bb", 16), ("C", 16), ("Dm", 16), ("Dm", 16), ("Gm", 16), ("A7", 16)]
    riff = bars("D5:2 D5:2 A5:2 D5:2 F5:2 D5:2 A5:2 D6:2", "D5:2 D5:2 A5:2 D5:2 F5:2 A5:2 G5:2 F5:2",
                "Bb4:2 Bb4:2 F5:2 Bb4:2 D5:2 Bb4:2 F5:2 Bb5:2", "C5:2 C5:2 G5:2 C5:2 E5:2 C5:2 G5:2 C6:2",
                "D5:2 D5:2 A5:2 D5:2 F5:2 D5:2 A5:2 D6:2", "D6:4 C6:2 Bb5:2 A5:4 F5:4",
                "G5:2 G5:2 D6:2 G5:2 Bb5:2 G5:2 D6:2 G6:2", "A5:2 A5:2 E6:2 A5:2 C#6:2 A5:2 E6:4")
    pb = [("Dm", 16), ("Bb", 16), ("Gm", 16), ("A7", 16), ("Dm", 16), ("Bb", 16), ("A7", 16), ("A7", 16)]
    melb = bars("A5:6 D6:2 F6:4 D6:4", "D6:6 Bb5:2 F6:4 D6:4", "G5:6 Bb5:2 D6:4 G6:4", "E6:6 C#6:2 A5:4 E5:4",
                "A5:6 D6:2 F6:4 A6:4", "F6:4 D6:4 Bb5:4 F5:4", "C#6:2 E6:2 A6:4 G6:2 E6:2 C#6:4", "A5:12 r:4")
    s.part("intro", 2, orch="D3+A3:2> r:6 D3+A3:2> r:6 | D3+A3:2> r:2 D3+A3:2> r:2 D3+A3:4> r:4 |", timp="D2:4 r:4 D2:4 r:4 | " + " ".join(["D2:2"] * 8) + " |",
           bell="D5:16 | A4:16 |", perc="Z...Z...Z...Z...|ZZZZZZZZZZZZZZZZ|", kit="K.......K.......|k.k.s.s.ssssSSSS|")
    s.part("A", 8, tp=riff, tb=transpose(riff, -12), bass=bassline(pa, "R:2 R:2 R:2 R:2 R:2 R:2 R:2 R:2", "D1"),
           orch=comp(pa, "x...............", "D3", "A4", 2), timp=bassline(pa, "R:4 r:4 R:4 r:4", "D1"),
           kit=rep("k.k.s.k.k.k.s...", 8, "k.k.s.k.sssSSSSS"), perc=rep("c.h.h.h.h.h.h.h.", 8),
           bell="r:16 | r:16 | r:16 | r:16 | r:16 | r:16 | r:16 | A4:2 A4:2 A4:2 A4:2 A4:2 A4:2 A4:2 A4:2 |")
    s.part("B", 8, tp=melb, tb=transpose(melb, -12), organ=comp(pb, "x---------------", "D3", "A4"), strings=tremolo(
           " ".join(f"{n}:16" for n in ["A4", "Bb4", "G4", "E4", "A4", "Bb4", "E4", "E4"]).replace(" ", " | ").replace(":16", ":16"), "1"),
           bass=bassline(pb, "R:4 R:4 R:4 5:4", "D1"), timp=bassline(pb, "R:2 R:2 r:12", "D1"),
           bell="D5:16 | Bb4:16 | G4:16 | A4:16 | D5:16 | Bb4:16 | A4:16 | A4:16 |",
           kit=rep("k...s...k...s...", 8, "k...s...k.s.SSSS"), perc=rep("c.o.h.h.o.h.h.h.", 8))
    return s.form(["intro"], ["A", "B"])


# ------------------------------------------------------------------ the ending

@song
def fin():
    """C major, 126 BPM: the ending. Bells and timpani open it; the tune on two trumpets in thirds over an accordion, a
    marching bass and a glockenspiel, then the second half climbs with the music box and strings to a full band cadence
    that turns round into the first."""
    s = Song("fin", 126, "C major", about="ending")
    s.track("tp1", 0, 56, 102, -0.1, 30).track("tp2", 1, 56, 84, 0.15, 30).track("glock", 2, 9, 72, 0.35, 40).track("mb", 3, 10, 70, 0.25, 40)
    s.track("strings", 4, 48, 70, -0.3, 40).track("bass", 5, 38, 112, 0).track("timp", 6, 47, 98, 0, 20).track("acc", 7, 21, 72, 0.3, 20)
    s.track("bell", 8, 14, 84, -0.2, 40).track("kit", 9, 0, 100).track("perc", 9, 0, 100)
    pa = [("C", 16), ("G", 16), ("Am", 16), ("Em", 16), ("F", 16), ("C", 16), ("Dm", 16), ("G", 16)]
    ma = bars("G4:4 C5:4 E5:4 G5:4", "B5:4 A5:2 G5:2 D5:8", "C6:4 B5:2 A5:2 E5:4 A5:4", "G5:4 E5:4 B5:4 G5:4",
              "A5:4 C6:4 F6:4 C6:4", "E6:4 D6:2 C6:2 G5:4 E5:4", "F5:4 A5:4 D6:4 F6:4", "D6:8 B5:4 G5:4")
    pb = [("F", 16), ("G", 16), ("Em", 16), ("Am", 16), ("F", 16), ("G", 16), ("C", 16), ("C", 16)]
    mbb = bars("C6:6 A5:2 F5:4 A5:4", "D6:6 B5:2 G5:4 B5:4", "E6:6 B5:2 G5:4 B5:4", "C6:6 E6:2 A6:4 E6:4",
               "F6:4 A5:4 C6:4 F6:4", "G6:4 D6:4 B5:4 D6:4", "C6:4 E6:4 G6:8", "C6:12 r:4")
    s.part("intro", 2, bell="C5:16 | G4:16 |", timp="C2:4 r:12 | " + " ".join(["G1:2"] * 8) + " |", mb=arp([("C", 16), ("G", 16)], [0, 1, 2, 1], "C4", "G5", 2, 3),
           kit="K...............|k...k...k.k.s.s.|", perc="r...............|ccccZZZZ........"[:16] + "")
    s.part("A", 8, tp1=ma, tp2=second_voice(ma, pa, [0, 2, 4, 5, 7, 9, 11]), acc=comp(pa, "..x...x...x...x.", "C3", "G4"),
           bass=bassline(pa, "R:4 5:4 R:4 5:4", "C1"), glock=transpose(ma, 12), kit=rep("k...s...k...s...", 8, "k...s...k.k.sssS"),
           perc=rep("z.w.z.w.z.w.z.W.", 8), timp=bassline(pa, "R:4 r:12", "C1"))
    s.part("B", 8, tp1=mbb, tp2=second_voice(mbb, pb, [0, 2, 4, 5, 7, 9, 11]), mb=transpose(mbb, 12),
           strings=comp(pb, "x---------------", "C3", "G4"), bass=bassline(pb, "R:4 5:4 R:4 5:4", "C1"),
           timp=bassline(pb, "R:4 r:4 R:4 r:4", "C1"), bell="F5:16 | G5:16 | E5:16 | A4:16 | F5:16 | G5:16 | C5:16 | C5:16 |",
           kit=rep("k...s..kk...s...", 8, "k...s..kk.s.SSSS"), perc=rep("c.h.h.h.h.h.h.h.", 8))
    return s.form(["intro"], ["A", "B"])


# ------------------------------------------------------------------ jingles

def jingle(name: str, bpm: float, key: str, beats: int = 4, about: str = "") -> Song:
    return Song(name, bpm, key, beats=beats, jingle=True, about=about)


@song
def victoria():
    """C major, 132 BPM, 5 s: stage clear. A brass fanfare in thirds, glockenspiel bells, timpani and a held C chord with a crash."""
    s = jingle("victoria", 132, "C major", about="victory")
    s.track("tp1", 0, 56, 104, -0.1, 30).track("tp2", 1, 56, 84, 0.15, 30).track("glock", 2, 9, 74, 0.35, 40).track("timp", 3, 47, 98, 0, 20)
    s.track("orch", 4, 55, 80, 0, 30).track("bass", 5, 38, 104, 0).track("kit", 9, 0, 100)
    p = [("C", 16), ("F", 16), ("C", 16)]
    tune = "G4:3 G4:1 C5:4 E5:4 G5:4 | A5:3 G5:1 E5:4 G5:8 | C6:12 r:4 |"
    s.part("a", 3, tp1=tune, tp2=second_voice(tune, p, [0, 2, 4, 5, 7, 9, 11]), glock=transpose(tune, 12),
           orch="C4:2> r:14 | r:16 | C3+G3:12> r:4 |", timp="C2:4 r:12 | F2:4 r:12 | C2:8 r:8 |",
           bass="C2:4 G1:4 C2:4 G1:4 | F2:4 C2:4 F2:4 C2:4 | C2:12 r:4 |",
           kit="K.......K.k.s.S.|K.......K.k.s.S.|c...............|")
    return s.form(["a"], [])


@song
def game_over():
    """C minor, 66 BPM, 7 s: game over. A music box falling in minor, low strings, a tolling bell and a clock ticking slower."""
    s = jingle("game_over", 66, "C minor", about="game over")
    s.track("mb", 0, 10, 100, -0.1, 40).track("strings", 1, 48, 66, -0.3, 40).track("bell", 2, 14, 88, 0.2, 40).track("kit", 9, 0, 100)
    s.part("a", 3, mb="G5:6 Eb5:2 D5:4 C5:4 | Ab4:6 F4:2 C4:4 Eb4:4 | C4:12 r:4 |",
           strings=comp([("Cm", 16), ("Fm", 16), ("Cm", 16)], "x---------------", "G2", "Eb4"),
           bell="C4:16 | F4:16 | C3:16 |", kit="z...z.......z...|z...........z...|z...............|")
    return s.form(["a"], [])


# ------------------------------------------------------------------ the continue countdown

@song
def continue_():
    """A minor, 120 BPM, a loop of exactly 10 s (five bars): the continue countdown. A bell strikes every second, ten times, over
    a ticking wood block, a heartbeat of timpani, a pizzicato bass and strings that hold a dissonant chord and tighten."""
    s = Song("continue", 120, "A minor", about="continue countdown")
    s.track("bell", 0, 14, 90, 0.1, 40).track("strings", 1, 48, 62, -0.3, 40).track("bass", 2, 45, 100, 0).track("timp", 3, 47, 96, 0, 20)
    s.track("kit", 9, 0, 100)
    p = [("Am", 16), ("Am", 16), ("F", 16), ("E", 16), ("E", 16)]
    s.part("A", 5, bell="A4:8 A4:8 | A4:8 A4:8 | A4:8 A4:8 | G#4:8 G#4:8 | G#4:8 G#4:8 |",
           strings=comp(p, "x---------------", "A2", "E4"), bass=bassline(p, "R:2 r:2 R:2 r:2 R:2 r:2 R:2 R:2", "A1"),
           timp=" | ".join(["A1:2 A1:2 r:12"] * 5) + " |", kit=rep("z...z...z...z...", 5, "z.z.z.z.zzzzzzzz"))
    return s.form([], ["A"])


# ------------------------------------------------------------------ main

# each song's master trim (its channels' volume times this), from the --check loudness numbers (K-weighted): the songs at about
# -16, the jingles a dB over them (the continue cue, tense and sparse, at -17)
LEVELS: dict[str, float] = {
    "titulo": 0.8, "seleccion": 1.0, "calle": 0.91, "fabrica": 0.69, "torre": 0.93, "jefe": 0.71, "fin": 0.79, "victoria": 0.95, "game_over": 2.04, "continue": 1.57,
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
