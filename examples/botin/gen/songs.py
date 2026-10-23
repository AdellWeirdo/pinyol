#!/usr/bin/env python3
"""Botín's music: every song and jingle as a Standard MIDI File (audio/<name>.mid) played by the game's bank of samples
(audio/BANK.bank), as a Game Boy Advance game's sequences were: music("selva", 0, {bank = "BANK"}).

    python3 gen/songs.py               the bank (if it is missing) and every song, and a table of them
    python3 gen/songs.py selva jefe    only those songs
    python3 gen/songs.py --bank        the bank again (gen/music_bank.py: the instruments)
    python3 gen/songs.py --wavs DIR    the bank's samples as WAVs and a manifest for tools/mkbank.py
    python3 gen/songs.py --check DIR   every song played by the engine (build/pinyol_headless) in a scratch game in DIR, and its
                                       numbers: level, peak, the loop's seam, the silence after a jingle, the tuning (gen/music_check.py)

The notation is gen/music_seq.py's: a sixteenth note is the unit, `C5:4` a quarter note, `|` a bar line (checked). A song is parts
(bars and a voice for each track) played in a form: an intro once, then a body that loops (the markers loopStart and loopEnd). A
jingle plays once and then goes round a stretch of silence, so it ends whether the game asks it to loop or not.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from music_seq import Song, arp, bassline, comp, transpose, write_smf  # noqa: E402

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
    return " ".join([f"r:{bar16}"] * n)


# ------------------------------------------------------------------ the title: the theme of the game

TITLE_A = bars("C5:3 F5:3 A5:2 G5:4 F5:2 G5:2", "A5:6 F5:2 D5:8", "D5:3 F5:3 Bb5:2 A5:4 G5:2 F5:2", "G5:10 r:2 C5:2 E5:2",
               "F5:3 A5:3 C6:2 Bb5:4 A5:2 G5:2", "A5:6 E5:2 C5:8", "D5:2 F5:2 Bb5:4 A5:2 G5:2 E5:4", "F5:12 r:4")
TITLE_B = bars("D6:4 C6:2 Bb5:2 F5:8", "E5:2 F5:2 G5:4 C6:8", "C6:4 A5:2 G5:2 E5:8", "F5:2 G5:2 A5:4 D6:8",
               "Bb5:4 A5:2 G5:2 D5:8", "E5:2 F5:2 G5:2 Bb5:2 C6:8", "A5:4 C6:4 D6:4 F6:4", "E6:6 D6:2 C6:4 r:4")


@song
def titulo():
    """F major, 138 BPM: the theme. A trumpet tune in dotted calls up the chord (C F A, G F G) that climbs a step each time,
    a slap bass in octaves, clav on the off-beats, brass stabs answering the ends of phrases; a second half over Bb C Am Dm
    with strings, and the tune again with a square wave an octave over it."""
    s = Song("titulo", 138, "F major", about="title")
    s.track("lead", 0, 56, 104, -0.1, 30).track("brass", 1, 61, 92, 0.2, 20).track("bass", 2, 36, 127, 0)
    s.track("clav", 3, 7, 78, -0.35).track("strings", 4, 48, 62, 0.3, 40).track("sq", 5, 81, 58, 0.4, 20)
    s.track("kit", 9, 0, 100).track("hats", 9, 0, 100)
    pa = [("F", 16), ("Dm", 16), ("Bb", 16), ("C", 16), ("F", 16), ("Am", 16), ("Bb", 8), ("C", 8), ("F", 16)]
    pa2 = pa[:-1] + [("F", 8), ("C7", 8)]
    pb = [("Bb", 16), ("C", 16), ("Am", 16), ("Dm", 16), ("Gm", 16), ("C7", 16), ("F/A", 8), ("Bb", 8), ("C", 16)]
    slap = "R:3 R:1 O.:2 R:2 5:2 O.:2 R:2 A:2"
    clav = "..x-..x...x-..x."
    kit = "k...s..kk...s..."
    hats = "h.h.h.h.h.h.h.ho"
    s.part("intro", 2,
           brass="C4+E4+Bb4:3> C4+E4+Bb4:3> C4+E4+Bb4:2> r:4 C4+E4+Bb4:2. D4+F4+C5:2. | E4+G4+C5:12> r:4 |",
           bass="C2:3 C2:3 C2:2 r:4 C2:2 D2:2 | E2:2 E2:2 G2:2 G2:2 Bb2:2 Bb2:2 C3:2 E3:2 |",
           kit="K..K..K.....s.s.|s.s.s.s.ssssSSSS|")
    brass_a = bars("r:16", "r:12 A4+D5+F5:2. A4+D5+F5:2>", "r:16", "r:10 E4+G4+C5:2. r:2 E4+G4+C5:2>", "r:16",
                   "r:12 A4+C5+E5:2. A4+C5+E5:2>", "D4+F4+Bb4:3> r:5 E4+G4+C5:3> r:5", "A4+C5+F5:3> A4+C5+F5:3> A4+C5+F5:2> r:8")
    s.part("A", 8, lead=TITLE_A, brass=brass_a, bass=bassline(pa, slap), clav=comp(pa, clav, "F3", "C5"),
           kit=rep(kit, 8, "k...s..kk.s.s.ss"), hats="c" + rep(hats, 8)[1:])
    s.part("B", 8, lead=TITLE_B, bass=bassline(pb, "R:6 R:2 5:4 O.:2 A:2"), clav=comp(pb, clav, "F3", "C5"),
           strings=comp(pb, "x---------------", "F3", "A4"), sq=arp(pb, [0, 1, 2, 3, 2, 1, 2, 3], "F5", "F6", 2, 3),
           brass=bars(*["r:16"] * 7, "r:8 E4+G4+C5:2> r:2 G4+Bb4+E5:2> r:2"),
           kit=rep("k...s...k.k.s...", 8, "k...s..kk.s.SSSS"), hats="c" + rep("h.h.h.h.h.h.h.h.", 8)[1:])
    brass_a2 = brass_a.rsplit("|", 2)[0] + "| A4+C5+F5:3> A4+C5+F5:3> A4+C5+F5:2> r:2 Bb4+C5+E5:2> r:2 Bb4+C5+E5:2> |"
    lead_a2 = TITLE_A.rsplit("|", 2)[0] + "| F5:8 r:2 Bb4:2 C5:2 E5:2 |"  # (the turn: C7 back to the top)
    s.part("A2", 8, lead=lead_a2, sq=transpose(lead_a2, 12), brass=brass_a2, bass=bassline(pa2, slap),
           strings=comp(pa2, "x-------x-------", "F3", "F4"),
           kit=rep(kit, 8, "k...s...s.s.ssSS"), hats="c" + rep(hats, 8)[1:])
    return s.form(["intro"], ["A", "B", "A2"])


# ------------------------------------------------------------------ the map: the islands, at ease

@song
def mapa():
    """C major, 100 BPM, a light swing: island exotica. A steel drum sings a lazy tune over Cmaj7 Am7 Dm7 G7, marimba broken
    chords, a bossa bass (root and fifth), congas and a shaker; a bridge over Fmaj7 with a flute line under the steel."""
    s = Song("mapa", 100, "C major", swing=0.16, about="map")
    s.track("steel", 0, 114, 122, 0.1, 30).track("marimba", 1, 12, 72, -0.3, 20).track("bass", 2, 33, 86, 0)
    s.track("strings", 3, 48, 44, 0.3, 40).track("flute", 4, 73, 66, -0.2, 40)
    s.track("congas", 9, 0, 92).track("shaker", 9, 0, 92)
    pa = [("Cmaj7", 16), ("Am7", 16), ("Dm7", 16), ("G7", 16), ("Cmaj7", 16), ("E7", 16), ("Am7", 8), ("D7", 8), ("Dm7", 8), ("G7", 8)]
    pb = [("Fmaj7", 16), ("Em7", 8), ("A7", 8), ("Dm7", 16), ("G7sus4", 8), ("G7", 8)]
    tune_a = bars("E5:3 G5:3 B5:2 A5:4 G5:4", "E5:6 C5:2 r:4 A4:2 C5:2", "D5:3 F5:3 A5:2 C6:4 A5:4", "B5:6 G5:2 r:4 D5:2 F5:2",
                  "E5:3 G5:3 B5:2 D6:4 E6:4", "B5:6 G#5:2 r:4 E5:2 G#5:2", "A5:4 G5:2 E5:2 F#5:4 A5:4", "F5:4 E5:2 D5:2 B4:4 r:4")
    tune_b = bars("A5:3 C6:3 E6:2 C6:8", "B5:4 G5:4 C#6:4 A5:4", "F5:3 A5:3 C6:2 A5:4 F5:4", "G5:8 r:4 D5:2 F5:2")
    congas = "q..Q..q.q.Q.u.Q."
    shaker = "z.z.z.z.z.z.x.z."
    bossa = "R:6 R:2 5:6 5:2"
    order = [0, 1, 2, 3, 1, 2, 3, 2]
    s.part("A", 8, steel=tune_a, marimba=arp(pa, order, "C4", "C5", 2), bass=bassline(pa, bossa),
           strings=comp(pa, "x---------------", "E3", "G4"), congas=rep(congas, 8), shaker=rep(shaker, 8))
    s.part("B", 4, steel=tune_b, marimba=arp(pb, order, "C4", "C5", 2), bass=bassline(pb, bossa),
           flute=bars("C5:16", "D5:8 C#5:8", "D5:16", "D5:8 F5:8"), strings=comp(pb, "x---------------", "E3", "G4"),
           congas=rep(congas, 4, "q..Q..q.Q.Q.u.uu"), shaker=rep(shaker, 4))
    return s.form([], ["A", "B"])


# ------------------------------------------------------------------ the jungle

@song
def selva():
    """D dorian, 126 BPM: the jungle. Congas and toms, a bouncing marimba in eighths, a synth bass on the off-beats; the flute
    calls (A A G A C A) over Dm7 and G, a brass chorus over Bb C Dm with the band hitting with it, then a break of drums, an organ
    and a marimba solo, with birds (a thin square, very high)."""
    s = Song("selva", 126, "D dorian", about="jungle level")
    s.track("flute", 0, 73, 100, -0.1, 30).track("marimba", 1, 12, 86, 0.3, 20).track("bass", 2, 38, 104, 0)
    s.track("trumpet", 3, 56, 96, 0.1, 30).track("brass", 4, 61, 84, -0.2, 20).track("organ", 5, 16, 60, -0.3, 30)
    s.track("birds", 6, 82, 50, 0.6, 50).track("kit", 9, 0, 100).track("perc", 9, 0, 100)
    pa = [("Dm7", 16), ("G", 16)] * 3 + [("Bb", 16), ("A7", 16)]
    pb = [("Bb", 16), ("C", 16), ("Dm", 16), ("Dm", 16), ("Bb", 16), ("C7", 16), ("A7", 16), ("A7", 16)]
    pc = [("Dm7", 16), ("G", 16)] * 4
    flute_a = bars("A5:2 r:2 A5:2 G5:2 A5:2 C6:2 A5:4", "G5:2 F5:2 D5:2 F5:2 G5:8", "A5:2 r:2 A5:2 G5:2 A5:2 D6:2 C6:4",
                   "B5:4 A5:2 G5:2 D5:8", "F5:2 G5:2 A5:2 C6:2 D6:4 C6:2 A5:2", "B5:2 A5:2 G5:2 F5:2 G5:4 D5:4",
                   "D5:2 F5:2 Bb5:4 A5:2 G5:2 F5:4", "E5:4 G5:4 C#6:6 r:2")
    trumpet_b = bars("F5:3 F5:3 F5:2 G5:4 F5:4", "E5:3 E5:3 E5:2 G5:4 C6:4", "D6:6 C6:2 A5:8", "r:16",
                     "F5:3 F5:3 F5:2 G5:4 A5:4", "G5:3 G5:3 G5:2 Bb5:4 C6:4", "C#6:8 E6:8", "E6:4 C#6:4 A5:8")
    brass_b = bars("r:16", "r:16", "r:16", "D4+F4+A4:2> r:2 D4+F4+A4:2> r:2 C4+F4+A4:2> r:2 D4+F4+A4:4>", "r:16", "r:16", "r:16",
                   "r:8 A3+C#4+E4:2> r:2 A3+C#4+G4:4>")
    bounce = "R.:2 r:2 R.:2 O.:2 r:2 R.:2 5.:2 O.:2"
    hits = "R:3 R:3 R:2 5:4 O:4"
    birds = bars("r:12 A6:1' C7:1' A6:1' r:1", "r:16", "r:4 E7:1' D7:1' r:10", "r:16") * 2
    kit_a = "k...x..kk...x..."
    perc_a = "Q.qqu.Q.q.Qqu.qq"
    s.part("intro", 2, kit=rep("k.....k.k.......", 2), perc=rep("F..f..m.F.f.m.T.", 2, "F.f.m.M.t.T.TTTT"))
    s.part("A", 8, flute=flute_a, marimba=arp(pa, [0, 2, 1, 2, 3, 2, 1, 2], "D4", "D5", 2), bass=bassline(pa, bounce),
           kit=rep(kit_a, 8), perc=rep(perc_a, 8, "Q.qqu.Q.m.m.t.T."))
    s.part("B", 8, trumpet=trumpet_b, brass=brass_b, marimba=arp(pb, [0, 2, 1, 2, 3, 2, 1, 2], "D4", "D5", 2),
           bass=bassline(pb, hits), kit=rep("k..k..k.d...k.k.", 8, "k..k..k.d.d.dddd"), perc=rep("Q.q.u.Q.q.Q.u.q.", 8))
    solo = arp(pc, [0, 1, 2, 3, 4, 3, 2, 1, 2, 3, 4, 5, 4, 3, 2, 3], "D4", "D5", 2)
    s.part("C", 8, marimba=solo, organ=comp(pc, "x-------x-------", "A3", "C5"), bass=bassline(pc, "R:4 r:4 5:4 r:2 R.:2"),
           birds=birds, kit=rep("k.....k.k.......", 8, "k.k.k.k.kkkkKKKK"),
           perc=rep("F..f..m.F.f.m.T.", 8, "F.f.m.M.t.T.TTTT"))
    return s.form(["intro"], ["A", "B", "C"])


# ------------------------------------------------------------------ the crystal cave

@song
def cristal():
    """E minor, 72 BPM: the crystal cave. A celesta's broken chords ringing over a low string pad and a low tom like a heartbeat,
    drips of a high thin square; then a slow flute over Em7 Cmaj7 Am7 B7, the lydian F# shining over C."""
    s = Song("cristal", 72, "E minor", about="crystal cave")
    s.track("celesta", 0, 8, 88, 0.3, 50).track("flute", 1, 73, 110, -0.2, 50).track("strings", 2, 48, 52, 0, 40)
    s.track("bass", 3, 38, 60, 0).track("drips", 4, 82, 72, 0.6, 60).track("heart", 9, 0, 70)
    pa = [("Em7", 16), ("Cmaj7", 16), ("Am7", 16), ("Bsus4", 8), ("B7", 8)] * 2
    pb = [("Em7", 16), ("Cmaj7", 16), ("Am7", 16), ("Bsus4", 8), ("B7", 8), ("Em7", 16), ("Gmaj7/D", 16), ("Cmaj7#11", 16), ("B7", 16)]
    order = [0, 1, 2, 3, 4, 3, 2, 1]
    drips = bars("r:12 B6:1' r:3", "r:8 E7:1' r:7", "r:16", "r:4 F#6:1' r:3 B6:1' r:7") * 2
    tune = bars("B5:8 A5:4 G5:4", "E5:12 F#5:4", "A5:8 G5:4 E5:4", "F#5:16", "G5:4 A5:4 B5:8", "D6:8 F#6:4 D6:4",
                "E6:6 D6:2 B5:8", "D#6:8 B5:8")
    heart = rep("F..F............", 8)
    s.part("A", 8, celesta=arp(pa, order, "E4", "E5", 2), strings=comp(pa, "x---------------", "B2", "D4"),
           bass=bassline(pa, "R:16"), drips=drips, heart=heart)
    s.part("B", 8, celesta=arp(pb, order, "E4", "E5", 2), flute=tune, strings=comp(pb, "x---------------", "B2", "D4"),
           bass=bassline(pb, "R:16"), heart=heart)
    return s.form([], ["A", "B"])


# ------------------------------------------------------------------ the sunken galleon

@song
def galeon():
    """A minor, 3/4 at 112 BPM, swung: the galleon under the sea. A jazz waltz: the bass on one, a wave-channel organ on two and
    three, a ride's swing; a flute tune that rises and floats (E A B C | A F) over Am F Dm E7, a trumpet bridge over F G Em Am,
    then the tune on the trumpet with bubbles of celesta."""
    s = Song("galeon", 112, "A minor", beats=3, swing=1 / 3, about="underwater galleon")
    s.track("flute", 0, 73, 96, -0.15, 50).track("trumpet", 1, 56, 90, 0.15, 40).track("organ", 2, 16, 64, -0.3, 30)
    s.track("bass", 3, 33, 100, 0).track("strings", 4, 48, 50, 0.3, 50).track("celesta", 5, 8, 58, 0.5, 60)
    s.track("kit", 9, 0, 84).track("ride", 9, 0, 84)
    pa = [("Am", 12), ("F", 12), ("Dm", 12), ("E7", 12), ("Am", 12), ("F", 12), ("Bm7b5", 12), ("E7", 12)]
    pb = [("F", 12), ("G", 12), ("Em7", 12), ("Am", 12), ("Dm", 12), ("G", 12), ("C", 12), ("E7", 12)]
    tune_a = bars("E5:4 A5:4 B5:2 C6:2", "A5:8 F5:4", "D5:4 F5:4 A5:2 G5:2", "G#5:8 E5:4", "E5:4 A5:4 C6:2 E6:2",
                  "D6:6 C6:2 A5:4", "B5:4 A5:2 F5:2 D5:4", "E5:12")
    tune_b = bars("C6:4 A5:4 F5:4", "D6:4 B5:4 G5:4", "E6:6 D6:2 B5:4", "C6:12", "A5:4 F5:4 D6:4", "B5:4 G5:4 D6:4",
                  "E6:4 D6:2 C6:2 B5:4", "G#5:8 B5:4")
    waltz = "....x-..x-.."
    kit = rep("k...x...x...", 8)
    ride = rep("h...h.h.h.h.", 8)
    s.part("A", 8, flute=tune_a, organ=comp(pa, waltz, "E3", "G4", bar16=12), bass=bassline(pa, "R:8 5:4", bar16=12),
           kit=kit, ride=ride)
    s.part("B", 8, trumpet=tune_b, organ=comp(pb, waltz, "E3", "G4", bar16=12), bass=bassline(pb, "R:8 5:4", bar16=12),
           strings=comp(pb, "x-----------", "C4", "E5", bar16=12), kit=kit, ride=ride)
    s.part("A2", 8, trumpet=tune_a, organ=comp(pa, waltz, "E3", "G4", bar16=12), bass=bassline(pa, "R:8 5:4", bar16=12),
           celesta=arp(pa, [0, 1, 2], "A5", "A6", 4, 3), strings=comp(pa, "x-----------", "C4", "E5", bar16=12),
           kit=kit, ride=rep("h...h.h.h.h.", 8, "h...h.h.ooo."))
    return s.form([], ["A", "B", "A2"])


# ------------------------------------------------------------------ the volcano forge

@song
def fragua():
    """E minor, 112 BPM: the forge in the volcano. A slap bass riff that climbs A Bb B into the next bar, sixteenth hats, an
    anvil on two and four with the snare, clav stabs; the brass take a riffing chorus over C D Em B7; a break of orchestra hits
    swinging between E and Bb, the tritone."""
    s = Song("fragua", 112, "E minor", about="volcano forge")
    s.track("bass", 0, 36, 116, 0).track("clav", 1, 7, 74, 0.35).track("brass", 2, 61, 90, -0.25, 20)
    s.track("trumpet", 3, 56, 100, 0.1, 30).track("orch", 4, 55, 84, 0, 30)
    s.track("kit", 9, 0, 92).track("hats", 9, 0, 92).track("anvil", 9, 0, 98)
    riff = bars("E2:2 E2:1 E3:1 r:2 E2:1 G2:1 r:2 A2:2 Bb2:2 B2:2", "E2:2 E2:1 E3:1 r:2 D3:2 E3:2 r:2 G2:1 A2:1 F2:2")
    pa = [("Em7", 16)] * 8
    pb = [("Cmaj7", 16), ("D", 16), ("Em7", 16), ("Em7", 16), ("Cmaj7", 16), ("D7", 16), ("B7", 16), ("B7", 16)]
    trumpet = bars("G5:2 G5:2 r:2 E5:2 G5:2 A5:4 G5:2", "F#5:2 F#5:2 r:2 D5:2 F#5:2 A5:4 F#5:2", "E5:3 E5:3 G5:2 B5:4 E6:4",
                   "D6:2 B5:2 G5:2 E5:2 r:8", "G5:2 G5:2 r:2 E5:2 G5:2 C6:4 B5:2", "A5:2 A5:2 r:2 F#5:2 A5:2 D6:4 C6:2",
                   "B5:6 A5:2 F#5:4 D#5:4", "F#5:12 r:4")
    kit = "k...s..kk.k.s..."
    hats = "HhhhHhhhHhhhHhho"
    anvil = "....a.......a..."
    stab = bars("r:16", "r:12 B3+E4+G4:2> B3+E4+G4:2>")
    orch = bars("E4:2> r:6 E4:2> r:2 G4:2> Bb4:2>", "E4:2> r:6 D4:2> r:2 C4:2> B3:2>")
    s.part("intro", 2, anvil=rep("a...a...a...a.a.", 2), orch=bars("r:16", "r:12 E4:2> E4:2>"),
           kit=rep("k...k...k...k...", 2, "k...k...k.k.kkkk"))
    s.part("A", 8, bass=riff * 4, clav=comp(pa, "..x.x..x..x.x-..", "G3", "E5"), brass=stab * 4, kit=rep(kit, 8),
           hats=rep(hats, 8), anvil=rep(anvil, 8))
    s.part("B", 8, trumpet=trumpet, brass=comp(pb, "x.x...x.x...x...", "C4", "E5"),
           bass=bassline(pb, "R:2 R:1 O:1 r:2 R:1 5:1 r:2 7:2 5:2 O:2"), clav=comp(pb, "..x.x..x..x.x-..", "G3", "E5"),
           kit=rep(kit, 8, "k...s..kk.s.s.ss"), hats=rep(hats, 8), anvil=rep(anvil, 8))
    s.part("C", 4, bass=riff * 2, orch=orch * 2, kit=rep("k..k..k.s..k..k.", 4, "k.k.s.k.s.s.ssss"),
           anvil=rep("a...a...a...a...", 4))
    return s.form(["intro"], ["A", "B", "C"])


# ------------------------------------------------------------------ the escape

@song
def escape():
    """C minor, 160 BPM: the escape, after the frog switch. Alarm stabs on a diminished chord, a driving octave bass in eighths,
    brass stabs off the beat, a thin square's sixteenths for nerves, a trumpet that urges (G G G Eb F G C) over Cm Ab Bb Db G7;
    a bridge rising over Fm G Ab Bb; a break whose stabs climb Cm Db Ddim G7 into a snare roll."""
    s = Song("escape", 160, "C minor", about="level escape")
    s.track("trumpet", 0, 56, 104, 0, 25).track("brass", 1, 61, 112, -0.3, 15).track("bass", 2, 38, 108, 0)
    s.track("sq", 3, 82, 54, 0.4, 15).track("orch", 4, 55, 86, 0.1, 20).track("kit", 9, 0, 104).track("hats", 9, 0, 104)
    pa = [("Cm", 16), ("Cm", 16), ("Ab", 16), ("Bb", 16), ("Cm", 16), ("Cm", 16), ("Db", 16), ("G7", 16)]
    pb = [("Fm", 16), ("G", 16), ("Ab", 16), ("Bb", 16), ("Fm", 16), ("G", 16), ("Ab", 8), ("Bb", 8), ("G7", 16)]
    pc = [("Cm", 16), ("Cm", 16), ("Db", 16), ("Db", 16), ("Ddim", 16), ("Ddim", 16), ("G7", 16), ("G7", 16)]
    tune_a = bars("G5:2 G5:2 G5:2 Eb5:2 F5:2 G5:2 C6:4", "Bb5:2 G5:2 Eb5:2 C5:2 D5:4 Eb5:4", "C6:2 C6:2 C6:2 Ab5:2 Bb5:2 C6:2 Eb6:4",
                  "D6:4 Bb5:4 F5:4 D5:4", "G5:2 G5:2 G5:2 Eb5:2 F5:2 G5:2 C6:4", "Eb6:4 D6:2 C6:2 G5:8",
                  "F5:2 Ab5:2 Db6:4 C6:4 Ab5:4", "B5:4 D6:4 F6:4 G6:4")
    tune_b = bars("Ab5:6 G5:2 F5:8", "G5:6 F5:2 D5:8", "Eb5:2 F5:2 Ab5:4 C6:8", "D6:6 C6:2 Bb5:8", "Ab5:6 G5:2 F5:8",
                  "B5:6 C6:2 D6:8", "Eb6:4 C6:4 F6:4 D6:4", "G6:8 F6:2 D6:2 B5:2 G5:2")
    drive = "R:2 O:2 R:2 O:2 R:2 O:2 R:2 O:2"
    kit = "k...s.k.k...s..."
    hats = "h.h.h.h.h.h.h.h."
    s.part("intro", 1, brass="C4+Eb4+Gb4+A4:2> r:2 C4+Eb4+Gb4+A4:2> r:2 C4+Eb4+Gb4+A4:2> r:2 D4+F4+Ab4+B4:4> |",
           bass="C2:2 r:2 C2:2 r:2 C2:2 r:2 B1:4 |", kit="k...k...k...s.ss|")
    s.part("A", 8, trumpet=tune_a, brass=comp(pa, "x..x..x...x.x...", "G3", "G4"), bass=bassline(pa, drive),
           sq=arp(pa, [0, 1, 2, 1], "C5", "C6", 1, 3), kit=rep(kit, 8, "k...s.k.k.s.s.ss"), hats="c" + rep(hats, 8)[1:])
    s.part("B", 8, trumpet=tune_b, brass=comp(pb, "x-......x.......", "G3", "G4"), bass=bassline(pb, drive),
           sq=arp(pb, [0, 1, 2, 1], "C5", "C6", 1, 3), kit=rep(kit, 8, "k...s.k.k.s.s.ss"), hats="c" + rep(hats, 8)[1:])
    s.part("C", 8, brass=comp(pc, "x..x..x...x.x...", "G3", "G4"), bass=bassline(pc, drive),
           orch=bars("C4:2> r:14", "r:16", "Db4:2> r:14", "r:16", "D4:2> r:14", "r:16", "G3:2> r:14", "r:8 G3:2> r:2 G3:2> G3:2>"),
           trumpet=bars(*["r:16"] * 6, "G5:4 B5:4 D6:4 F6:4", "G6:8 F6:4 D6:4"),
           kit=rep("k...k...k...k...", 6) + "k.s.k.s.k.s.k.s.|ssssssssSSSSSSSS|", hats=rep("o.h.o.h.o.h.o.h.", 8))
    return s.form(["intro"], ["A", "B", "C"])


# ------------------------------------------------------------------ the boss, and the last boss

BOSS_A = bars("D5:6 A4:2 D5:4 F5:4", "G5:6 Eb5:2 Bb4:8", "A5:6 F5:2 D5:4 A5:4", "C#6:6 A5:2 E5:4 G5:4", "D6:6 A5:2 F5:4 D6:4",
              "Eb6:6 Bb5:2 G5:4 Eb6:4", "F6:4 E6:2 D6:2 A5:8", "A5:4 C#6:4 E6:4 G6:4")
BOSS_B = bars("Bb5:4 A5:2 G5:2 D5:8", "C#6:4 B5:2 A5:2 E5:8", "D6:4 C6:2 Bb5:2 F5:8", "E6:4 D6:2 C6:2 G5:8",
              "G5:3 Bb5:3 D6:2 G6:8", "A5:3 C#6:3 E6:2 A6:8", "F6:4 D6:4 Bb5:4 D6:4", "C#6:16")
BOSS_PA = [("Dm", 16), ("Eb", 16), ("Dm", 16), ("A7", 16)] * 2
BOSS_PB = [("Gm", 16), ("A", 16), ("Bb", 16), ("C", 16), ("Gm", 16), ("A", 16), ("Bb", 16), ("A7", 16)]
BOSS_ORCH = bars("D4:2> r:14", "Eb4:2> r:14", "D4:2> r:14", "A3:2> r:14") * 2


@song
def jefe():
    """D minor, 144 BPM: a boss. Orchestra hits on each chord of Dm Eb Dm A7 (the flat second's dread), strings sawing eighths,
    a heavy bass, toms; the trumpet's theme leaps (D A D F | G Eb Bb) and climbs to a high G; a bridge over Gm A Bb C up to A6."""
    s = Song("jefe", 144, "D minor", about="boss")
    s.track("trumpet", 0, 56, 104, 0, 25).track("brass", 1, 61, 86, -0.3, 20).track("ostinato", 2, 49, 96, 0.3, 20)
    s.track("bass", 3, 33, 112, 0).track("orch", 4, 55, 86, 0, 25).track("kit", 9, 0, 104).track("toms", 9, 0, 104)
    ost = [0, 0, 1, 0, 2, 0, 1, 0]
    kit = "k.k.s..kk.k.s.k."
    s.part("intro", 2, orch="D4:2> r:2 D4:2> r:2 D4:2> r:6 | Eb4:2> r:2 Eb4:2> r:2 Eb4:2> r:2 E4:2> F4:2> |",
           bass="D2:2 r:2 D2:2 r:2 D2:2 r:6 | Eb2:2 r:2 Eb2:2 r:2 Eb2:2 r:2 E2:2 F2:2 |",
           toms="F.F.F.......f.f.|M.M.M.M.t.t.TTTT|")
    s.part("A", 8, trumpet=BOSS_A, brass=comp(BOSS_PA, "x--.....x-......", "F3", "F4"), ostinato=arp(BOSS_PA, ost, "D3", "D4", 2, 3),
           bass=bassline(BOSS_PA, "R:4 r:2 R:2 R:4 O:2 5:2"), orch=BOSS_ORCH, kit=rep(kit, 8),
           toms=rep("................", 8, "T.T.t.t.M.M.f.f."))
    s.part("B", 8, trumpet=BOSS_B, brass=comp(BOSS_PB, "x-------x-------", "F3", "F4"), ostinato=arp(BOSS_PB, ost, "D3", "D4", 2, 3),
           bass=bassline(BOSS_PB, "R:4 r:2 R:2 R:4 O:2 5:2"), kit=rep("k...s..kk...s...", 8, "k.k.s.s.s.s.SSSS"),
           toms=rep("F...............", 8))
    return s.form(["intro"], ["A", "B"])


@song
def final():
    """E minor, 132 BPM: the last boss, the boss's theme made epic. Up a tone, a square wave an octave under the trumpet giving
    it body, busier drums with toms on every half bar, sustained strings in the intro; then the title's theme comes back in G
    major, the brass and an organ
    under it, as if the island answered."""
    s = Song("final", 132, "E minor", about="last boss")
    s.track("trumpet", 0, 56, 104, 0, 30).track("brass", 1, 61, 84, -0.3, 25).track("strings", 2, 48, 60, 0.3, 40)
    s.track("ostinato", 3, 49, 90, 0.4, 20).track("bass", 4, 33, 112, 0).track("orch", 5, 55, 84, 0, 30)
    s.track("organ", 6, 16, 58, -0.4, 40).track("sq", 7, 80, 50, 0.2, 30).track("kit", 9, 0, 104).track("toms", 9, 0, 104)
    pa = [("Em", 16), ("F", 16), ("Em", 16), ("B7", 16)] * 2
    pb = [("Am", 16), ("B", 16), ("C", 16), ("D", 16), ("Am", 16), ("B", 16), ("C", 16), ("B7", 16)]
    pc = [("G", 16), ("Em", 16), ("C", 16), ("D", 16), ("G", 16), ("Bm", 16), ("C", 8), ("D", 8), ("G", 8), ("B7", 8)]
    tune_a, tune_b = transpose(BOSS_A, 2), transpose(BOSS_B, 2)
    quote = transpose(TITLE_A, 2).rsplit("|", 2)[0] + "| G5:8 F#5:4 D#5:4 |"
    ost = [0, 0, 1, 0, 2, 0, 1, 0]
    kit = "k.k.s.kkk.k.s.kk"
    s.part("intro", 2, orch="E4:2> r:2 E4:2> r:2 E4:2> r:6 | F4:2> r:2 F4:2> r:2 F4:2> r:2 F#4:2> G4:2> |",
           bass="E2:2 r:2 E2:2 r:2 E2:2 r:6 | F2:2 r:2 F2:2 r:2 F2:2 r:2 F#2:2 G2:2 |",
           strings="E3+G3+B3:16 | F3+A3+C4:16 |", toms="F.F.F.......f.f.|M.M.M.M.t.t.TTTT|")
    s.part("A", 8, trumpet=tune_a, sq=transpose(tune_a, -12), brass=comp(pa, "x--.....x-......", "G3", "G4"),
           ostinato=arp(pa, ost, "E3", "E4", 2, 3), bass=bassline(pa, "R:4 r:2 R:2 R:4 O:2 5:2"), orch=transpose(BOSS_ORCH, 2),
           kit=rep(kit, 8),
           toms=rep("F.......F.......", 8, "T.T.t.t.M.M.f.f."))
    s.part("B", 8, trumpet=tune_b, sq=transpose(tune_b, -12), brass=comp(pb, "x-------x-------", "G3", "G4"),
           ostinato=arp(pb, ost, "E3", "E4", 2, 3), bass=bassline(pb, "R:4 r:2 R:2 R:4 O:2 5:2"),
           kit=rep("k...s..kk...s...", 8, "k.k.s.s.s.s.SSSS"), toms=rep("F.......F.......", 8))
    s.part("C", 8, trumpet=quote, brass=comp(pc, "x..x..x.........", "G3", "G4"), organ=comp(pc, "x-------x-------", "D3", "G4"),
           ostinato=arp(pc, ost, "E3", "E4", 2, 3), bass=bassline(pc, "R:3 R:1 O.:2 R:2 5:2 O.:2 R:2 A:2"),
           orch=bars("G3:2> r:14", "r:16", "C4:2> r:14", "D4:2> r:14", "G3:2> r:14", "r:16", "C4:2> r:6 D4:2> r:6", "G3:2> r:6 B3:2> r:6"),
           kit=rep("k...s..kk...s...", 8, "k...s...s.s.SSSS"), toms=rep("................", 8, "........T.t.M.f."))
    return s.form(["intro"], ["A", "B", "C"])


# ------------------------------------------------------------------ the ending

@song
def fin():
    """F major, 92 BPM: the credits. The title's tune slowed and warm on the flute over Fadd9 Dm7 Bbadd9 C7, a celesta's broken
    chords, strings and a soft brush beat; its second half on the trumpet; and a last climb with the brass, the toms rolling,
    to a high C over F."""
    s = Song("fin", 92, "F major", about="ending credits")
    s.track("flute", 0, 73, 96, -0.15, 50).track("trumpet", 1, 56, 96, 0.1, 40).track("strings", 2, 48, 66, 0.25, 50)
    s.track("celesta", 3, 8, 62, 0.45, 50).track("bass", 4, 33, 100, 0).track("brass", 5, 61, 80, -0.3, 30)
    s.track("kit", 9, 0, 80).track("hats", 9, 0, 80)
    pa = [("Fadd9", 16), ("Dm7", 16), ("Bbadd9", 16), ("C7sus4", 8), ("C7", 8), ("Fadd9", 16), ("Am7", 16), ("Bbadd9", 8), ("C7", 8),
          ("F", 16)]
    pb = [("Bbadd9", 16), ("C", 16), ("Am7", 16), ("Dm7", 16), ("Gm7", 16), ("C7", 16), ("F/A", 8), ("Bb", 8), ("C7sus4", 8), ("C7", 8)]
    pc = [("Bb", 16), ("C", 16), ("Dm", 8), ("Bb", 8), ("Fadd9", 16)]
    coda = bars("F5:4 G5:4 A5:4 Bb5:4", "C6:6 Bb5:2 A5:4 G5:4", "A5:4 F5:4 D6:4 C6:4", "C6:16")
    order = [0, 1, 2, 3, 2, 1, 2, 3]
    brush = "k.......x.......|"
    hats = "h..hh..hh..hh..h"
    s.part("intro", 2, strings=comp([("Fadd9", 16), ("C7sus4", 16)], "x---------------", "F3", "A4"),
           celesta=arp([("Fadd9", 16), ("C7sus4", 16)], order, "F4", "F5", 2), bass="F2:16 | C2:16 |")
    s.part("A", 8, flute=TITLE_A, celesta=arp(pa, order, "F4", "F5", 2), strings=comp(pa, "x---------------", "F3", "A4"),
           bass=bassline(pa, "R:6 5:2 O:4 5:4"), kit=brush * 8, hats=rep(hats, 8))
    s.part("B", 8, trumpet=TITLE_B, celesta=arp(pb, order, "F4", "F5", 2), strings=comp(pb, "x---------------", "F3", "A4"),
           bass=bassline(pb, "R:6 5:2 O:4 5:4"), kit=brush * 8, hats=rep(hats, 8))
    s.part("C", 4, trumpet=coda, brass=comp(pc, "x-------x-------", "F3", "F4"), strings=comp(pc, "x---------------", "A3", "C5"),
           bass=bassline(pc, "R:4 R:4 O:4 5:4"), kit="k...k...k...k...|k...k...k...k...|k...k...k.k.k.k.|c...............|",
           hats="................|................|F.F.f.f.M.M.T.TT|................|")
    return s.form(["intro"], ["A", "B", "C"])


# ------------------------------------------------------------------ jingles (played once)

def jingle(name: str, bpm: float, key: str, beats: int = 4, about: str = "") -> Song:
    return Song(name, bpm, key, beats=beats, jingle=True, about=about)


@song
def joya():
    """C major, 125 BPM, 2 s: a jewel piece. A square wave flies up the C chord to a high C, a celesta a sixth over
    it sparkling, a brass chord and a crash where it lands."""
    s = jingle("joya", 125, "C major", about="jewel piece")
    s.track("sq", 0, 81, 100, 0, 30).track("celesta", 1, 8, 92, 0.4, 50).track("brass", 2, 61, 84, -0.3, 30)
    s.track("bass", 3, 38, 96, 0).track("kit", 9, 0, 96)
    s.part("a", 1, sq="G5:1 C6:1 E6:1 G6:1 E6:1 G6:1 C7:10 |", celesta="E6:1 G6:1 C7:1 E7:1 C7:1 E7:1 G7:10 |",
           brass="r:6 C4+E4+G4:10> |", bass="r:6 C3:10 |", kit="k.....c.........|")
    return s.form(["a"], [])


@song
def llave():
    """E minor to E major, 150 BPM, 3.2 s: the key ghost caught. A ghostly celesta falls through E minor and E diminished over an
    organ, then the trumpet climbs B E G# B to a held E major with the brass, a square trilling over it."""
    s = jingle("llave", 150, "E major", about="key ghost caught")
    s.track("celesta", 0, 8, 90, 0.3, 60).track("organ", 1, 16, 70, -0.3, 40).track("trumpet", 2, 56, 102, 0, 30)
    s.track("brass", 3, 61, 84, -0.2, 30).track("bass", 4, 38, 96, 0).track("sq", 5, 81, 60, 0.4, 30).track("kit", 9, 0, 96)
    s.part("a", 2, celesta="B5:1 G5:1 E5:1 B4:1 Bb5:1 G5:1 E5:1 Bb4:1 r:8 | r:16 |", organ="E4+G4:8 r:8 | r:16 |",
           trumpet="r:8 B4:2 E5:2 G#5:2 B5:2 | E6:14 r:2 |", brass="r:16 | E4+G#4+B4:14> r:2 |", bass="r:8 B2:8 | E2:14 r:2 |",
           sq="r:16 | B5:1 E6:1 B5:1 E6:1 G#6:10 r:2 |", kit="................|c...............|")
    return s.form(["a"], [])


@song
def nivel_ok():
    """G major, 144 BPM, 4 s: a level done. A fanfare up the G chord (D G B D—B D), a turn over C and D, and a high G held with
    a crash, a square a third under the trumpet all the way, the band hitting with it."""
    s = jingle("nivel_ok", 144, "G major", about="level done")
    s.track("trumpet", 0, 56, 104, 0, 30).track("sq", 1, 81, 64, 0.35, 30).track("brass", 2, 61, 86, -0.3, 30)
    s.track("bass", 3, 33, 104, 0).track("kit", 9, 0, 100)
    s.part("a", 3, trumpet="D5:2 G5:2 B5:2 D6:4 B5:2 D6:4 | E6:4 C6:2 E6:2 F#6:4 D6:2 F#6:2 | G6:8 r:8 |",
           sq="B4:2 D5:2 G5:2 B5:4 G5:2 B5:4 | C6:4 A5:2 C6:2 D6:4 A5:2 D6:2 | B5:8 r:8 |",
           brass="G3+B3+D4:2> r:6 G3+B3+D4:2> r:6 | C4+E4+G4:4> r:4 D4+F#4+A4:4> r:4 | G3+B3+D4+G4:8> r:8 |",
           bass="G2:4 D2:4 G2:4 B2:4 | C3:8 D3:8 | G2:8 r:8 |", kit="k...s...k...s.s.|k...s...k.s.ssss|c...............|")
    return s.form(["a"], [])


@song
def muerte():
    """C, 120 BPM, 2 s: a death, comic. A square wave tumbles down eight semitones, the trumpet sighs C B Bb and droops (the
    pitch sagging two semitones), a low tom and the bass go bonk."""
    s = jingle("muerte", 120, "C minor", about="death")
    s.track("sq", 0, 80, 92, 0, 20).track("trumpet", 1, 56, 100, 0, 30).track("bass", 2, 38, 100, 0).track("kit", 9, 0, 100)
    s.part("a", 1, sq="B5:1 Bb5:1 A5:1 Ab5:1 G5:1 Gb5:1 F5:1 E5:1 r:8 |", trumpet="r:8 C5:2. B4:2. ~0>-2:4 Bb4:4_ |",
           bass="r:12 C2:4 |", kit="............F...|")
    return s.form(["a"], [])


@song
def game_over():
    """C minor, 3/4 at 88 BPM, 4 s: game over. A flute sighs down (Eb D C, Ab) over Cm and Fm, then B D to C over G7 and Cm, the
    strings holding the chords, the bass falling to a low C."""
    s = jingle("game_over", 88, "C minor", beats=3, about="game over")
    s.track("flute", 0, 73, 100, 0, 50).track("strings", 1, 48, 76, 0.2, 50).track("bass", 2, 33, 96, 0)
    s.part("a", 2, flute="Eb5:3 D5:1 C5:4 Ab4:4 | B4:3 D5:1 C5:8 |",
           strings="C4+Eb4+G4:8 C4+F4+Ab4:4 | B3+D4+F4:4 C4+Eb4+G4:8 |", bass="C3:8 Ab2:4 | G2:4 C2:8 |")
    return s.form(["a"], [])


@song
def tesoro():
    """A major, 128 BPM, 2 s: a treasure chest. A square sweeps up A C# E twice over, the trumpet answers C# D E
    up to a high A, an orchestra hit, the brass and a crash on it."""
    s = jingle("tesoro", 128, "A major", about="treasure chest")
    s.track("sq", 0, 81, 90, 0.3, 30).track("trumpet", 1, 56, 104, 0, 30).track("brass", 2, 61, 86, -0.3, 30)
    s.track("orch", 3, 55, 80, 0, 30).track("bass", 4, 38, 96, 0).track("kit", 9, 0, 100)
    s.part("a", 1, sq="A4:1 C#5:1 E5:1 A5:1 C#6:1 E6:1 r:10 |", trumpet="r:6 C#6:2 D6:1 E6:1 A6:6 |",
           brass="r:10 A3+C#4+E4+A4:6> |", orch="r:10 A3:6> |", bass="r:10 A2:6 |", kit="..........c.....|")
    return s.form(["a"], [])


# ------------------------------------------------------------------ main

# each song's master trim (its channels' volume times this), from the --check loudness numbers (K-weighted): the songs at about
# -17, the jingles a dB over them
LEVELS: dict[str, float] = {
    "titulo": 0.86, "mapa": 1.32, "selva": 1.05, "cristal": 1.14, "galeon": 1.07, "fragua": 1.23, "escape": 0.88, "jefe": 0.80,
    "final": 0.77, "fin": 0.95, "joya": 1.08, "llave": 0.97, "nivel_ok": 0.87, "muerte": 1.66, "game_over": 1.29, "tesoro": 1.08,
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
    print(f"{'song':10} {'key':10} {'meter':5} {'BPM':>4} {'intro s':>7} {'loop s':>7} {'bytes':>6}  about")
    for name in names:
        s = make(name)
        info = write_smf(s, audio / f"{name}.mid")
        size = (audio / f"{name}.mid").stat().st_size
        intro = s.seconds(info["loop_start"]) if not s.jingle else s.seconds(info["music_end"])
        body = s.seconds(info["loop_end"] - info["loop_start"]) if not s.jingle else 0.0
        print(f"{name:10} {s.key:10} {s.beats}/4   {s.bpm:4.0f} {intro:7.1f} {body:7.1f} {size:6}  {s.about}")


if __name__ == "__main__":
    main(sys.argv[1:])
