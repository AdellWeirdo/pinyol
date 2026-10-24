"""Taller de los Autómatas' songs as data (from paella's, which was copied from examples/botin/gen/music_seq.py and extended: a Spanish kit's letters,
accented hits in `comp`, strummed chords): a tiny notation, a few arranging helpers and a Standard MIDI File writer (format 1: the tempo, the time
signature and the loop markers in the first track, then a track a channel with its program, volume, pan and reverb send).

A voice is a string of tokens; a sixteenth note is the unit of length:
    C5:4        a note four sixteenths long (C, C#, Db ... B; octave 4 holds middle C); without :n the length set by L
    C4+E4+G4:8  a chord          r:4  a rest          -:4  the notes before held longer (a tie)          |  a bar line (checked)
    lengths may be fractions: :4/3 is an eighth-note triplet
    after the length: . staccato (half the length)   ' short (a quarter)   _ legato (all of it)   > accent (louder)
    vNN         the velocity from here on (1-127)       LN  the default length       @NN  a program change (General MIDI)
    ~-2         pitch bend now, in semitones (-2..2)     ~0>-2:8  a bend gliding from 0 to -2 over 8 sixteenths (takes no time)
Drums are a grid: a character a step, the bar's steps as many as its characters (16 for sixteenths in 4/4, 12 for triplet eighths
in 3/4...); `.` is nothing, every other letter a drum of KIT_LETTERS.
"""
from __future__ import annotations

import re
import struct
from dataclasses import dataclass, field
from fractions import Fraction
from pathlib import Path

PPQ = 96
SIX = PPQ // 4  # ticks a sixteenth
NOTE_PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}

# letter: (key, velocity)
KIT_LETTERS = {
    "k": (36, 100), "K": (36, 122), "s": (38, 96), "S": (38, 120), "g": (38, 46), "x": (37, 80), "p": (39, 100),
    "d": (40, 108), "h": (42, 80), "H": (42, 110), "j": (44, 70), "o": (46, 90), "c": (49, 110), "C": (57, 110),
    "F": (41, 104), "f": (43, 104), "m": (45, 104), "M": (47, 104), "t": (48, 104), "T": (50, 104),
    "b": (60, 92), "B": (61, 92), "q": (62, 80), "Q": (63, 104), "u": (64, 104), "a": (67, 100), "z": (70, 80), "Z": (82, 84),
    "w": (76, 96), "W": (77, 110),
    # the Spanish kit: palmas (a group's handclaps), castanets, cajón, tambourine, ride
    "l": (39, 70), "P": (39, 124), "n": (85, 84), "N": (85, 118), "y": (86, 108), "Y": (87, 108), "v": (87, 74),
    "e": (54, 70), "A": (56, 104), "E": (54, 104), "r": (51, 84), "R": (53, 100), "i": (55, 100), "D": (35, 127),
}


def midi_of(name: str) -> int:
    m = re.fullmatch(r"([A-G])([#b]?)(-?\d)", name)
    if not m:
        raise ValueError(f"not a note: {name!r}")
    pc = NOTE_PC[m.group(1)] + (1 if m.group(2) == "#" else -1 if m.group(2) == "b" else 0)
    return 12 * (int(m.group(3)) + 1) + pc


SHARP_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
FLAT_NAMES = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]


def name_of(midi: int, flats: bool = False) -> str:
    return (FLAT_NAMES if flats else SHARP_NAMES)[midi % 12] + str(midi // 12 - 1)


def transpose(text: str, semis: int, flats: bool = False) -> str:
    """The same voice `semis` semitones away."""
    return re.sub(r"(?<![A-Za-z@])([A-G][#b]?-?\d)", lambda m: name_of(midi_of(m.group(1)) + semis, flats), text)


def length_of(s: str) -> Fraction:
    return Fraction(s)


@dataclass
class Note:
    start: int  # ticks
    dur: int
    key: int
    vel: int
    track: str
    gated: int = 0  # the length as written (before the gate), for the harmony check


@dataclass
class Ctl:
    tick: int
    kind: str  # "bend" (value -8192..8191) or "prog"
    value: int
    track: str


def parse_voice(text: str, start: int, bar16: int, track: str, where: str) -> tuple[list[Note], list[Ctl], int]:
    """A voice's notes from tick `start`: (notes, controls, its length in ticks)."""
    notes: list[Note] = []
    ctls: list[Ctl] = []
    pos = Fraction(0)
    deflen = Fraction(4)
    vel = 96
    last: list[Note] = []
    bar_start = Fraction(0)
    for tok in text.replace("|", " | ").split():
        if tok == "|":
            if (pos - bar_start) != bar16:
                raise ValueError(f"{where}: a bar of {float(pos - bar_start)} sixteenths, not {bar16} (at {float(pos)})")
            bar_start = pos
            continue
        if tok[0] == "L":
            deflen = length_of(tok[1:])
            continue
        if tok[0] == "v" and tok[1:].isdigit():
            vel = int(tok[1:])
            continue
        if tok[0] == "@":
            ctls.append(Ctl(start + int(pos * SIX), "prog", int(tok[1:]), track))
            continue
        if tok[0] == "~":
            m = re.fullmatch(r"~(-?[\d.]+)(?:>(-?[\d.]+):([\d/]+))?", tok)
            if not m:
                raise ValueError(f"{where}: bad bend {tok!r}")
            a = float(m.group(1))
            if m.group(2) is None:
                ctls.append(Ctl(start + int(pos * SIX), "bend", int(a / 2 * 8191), track))
            else:
                b, span = float(m.group(2)), length_of(m.group(3)) * SIX
                steps = max(2, int(span // 6))
                for i in range(steps + 1):
                    v = a + (b - a) * i / steps
                    ctls.append(Ctl(start + int(pos * SIX + span * i / steps), "bend", int(v / 2 * 8191), track))
            continue
        m = re.fullmatch(r"([^:]+?)(?::([\d/.]+))?([.'_>]*)", tok)
        if not m:
            raise ValueError(f"{where}: bad token {tok!r}")
        head, ln, flags = m.group(1), m.group(2), m.group(3)
        n = length_of(ln) if ln else deflen
        ticks = n * SIX
        if head == "r":
            last = []
        elif head == "-":
            for x in last:
                x.dur += int(ticks)
                x.gated += int(ticks)
        else:
            gate = Fraction(1) if "_" in flags else Fraction(1, 2) if "." in flags else Fraction(1, 4) if "'" in flags else Fraction(9, 10)
            v = min(127, vel + (18 if ">" in flags else 0))
            last = []
            for nm in head.split("+"):
                dur = max(6, int(ticks * gate))
                note = Note(start + int(pos * SIX), dur, midi_of(nm), v, track, int(ticks))
                if gate == Fraction(9, 10) and ticks >= 2 * SIX:
                    note.dur = int(ticks) - SIX // 2  # long notes: a short gap before the next one, whatever their length
                notes.append(note)
                last.append(note)
        pos += n
    if pos != bar_start and (pos - bar_start) % bar16:
        raise ValueError(f"{where}: ends {float(pos - bar_start)} sixteenths into a bar")
    return notes, ctls, int(pos * SIX)


def parse_drums(text: str, start: int, bar16: int, track: str, where: str) -> tuple[list[Note], int]:
    notes: list[Note] = []
    pos = Fraction(0)
    for bar in [b for b in text.split("|") if b.strip()]:
        bar = bar.strip()
        step = Fraction(bar16, len(bar))
        for i, ch in enumerate(bar):
            if ch == ".":
                continue
            if ch not in KIT_LETTERS:
                raise ValueError(f"{where}: drum {ch!r} is not in the kit")
            key, vel = KIT_LETTERS[ch]
            notes.append(Note(start + int((pos + i * step) * SIX), SIX, key, vel, track, SIX))
        pos += bar16
    return notes, int(pos * SIX)


# ------------------------------------------------------------------ chords and arranging helpers

QUALITY = {
    "": (0, 4, 7), "m": (0, 3, 7), "7": (0, 4, 7, 10), "m7": (0, 3, 7, 10), "maj7": (0, 4, 7, 11), "dim": (0, 3, 6),
    "dim7": (0, 3, 6, 9), "m7b5": (0, 3, 6, 10), "sus4": (0, 5, 7), "sus2": (0, 2, 7), "aug": (0, 4, 8), "6": (0, 4, 7, 9),
    "m6": (0, 3, 7, 9), "9": (0, 4, 7, 10, 14), "m9": (0, 3, 7, 10, 14), "maj9": (0, 4, 7, 11, 14), "add9": (0, 4, 7, 14),
    "madd9": (0, 3, 7, 14), "7sus4": (0, 5, 7, 10), "5": (0, 7), "maj7#11": (0, 4, 7, 11, 18),
    "7b9": (0, 4, 7, 10, 13),  # the flamenco dominant: the phrygian's flat second over the major chord
}


def chord(name: str) -> tuple[int, list[int], int]:
    """'F', 'Dm7', 'Bb/D', 'C7sus4' -> (root pitch class, intervals, bass pitch class)."""
    main, _, bass = name.partition("/")
    m = re.fullmatch(r"([A-G][#b]?)(.*)", main)
    if not m or m.group(2) not in QUALITY:
        raise ValueError(f"not a chord: {name!r}")
    root = midi_of(m.group(1) + "0") % 12
    b = midi_of(bass + "0") % 12 if bass else root
    return root, list(QUALITY[m.group(2)]), b


def place(pc: int, low: int) -> int:
    """The pitch of class `pc` at or just above `low`."""
    return low + (pc - low) % 12


def voicing(name: str, low: int, high: int, prev: list[int] | None, size: int = 3) -> list[int]:
    """`size` notes of the chord between low and high, as close as can be to the voicing before (smooth voice leading)."""
    root, iv, _ = chord(name)
    pcs = [(root + i) % 12 for i in iv]
    if len(pcs) > size:  # drop the fifth first, then the root: the colour notes stay
        fifth = (root + 7) % 12
        if fifth in pcs and len(pcs) > size:
            pcs.remove(fifth)
        if len(pcs) > size:
            pcs.remove(root)
    pcs = pcs[:size]
    from itertools import combinations
    best, best_cost = None, None
    for top, span in ((high, 14), (high + 5, 14), (high, 19), (high + 7, 19)):  # (widened when nothing fits: a maj7 without a cluster)
        cands = sorted({p for pc in pcs for p in range(place(pc, low), top + 1, 12)})
        for combo in combinations(cands, len(pcs)):
            if {c % 12 for c in combo} != set(pcs) or max(combo) - min(combo) > span:
                continue
            if any(abs(b - a) in (1, 13) for i, a in enumerate(combo) for b in combo[i + 1:]):  # no minor seconds or ninths
                continue
            cost = sum(min(abs(c - p) for p in prev) for c in combo) if prev else abs(sum(combo) / len(combo) - (low + high) / 2)
            if best_cost is None or cost < best_cost:
                best, best_cost = list(combo), cost
        if best is not None:
            break
    if best is None:
        raise ValueError(f"no voicing of {name} between {low} and {high}")
    return best


def comp(prog: list[tuple[str, float]], rhythm: str, low: str, high: str, size: int = 3, bar16: int = 16) -> str:
    """Chords played to a rhythm: `prog` is (chord, sixteenths) pairs; `rhythm` a bar's grid ('x' a hit as long as the dots after
    it, '-' holds, '.' rests), repeated; the voicings lead smoothly into each other."""
    lo, hi = midi_of(low), midi_of(high)
    timeline = []
    for name, n in prog:
        timeline += [name] * int(n)
    out, prev = [], None
    steps = len(rhythm)
    unit = Fraction(bar16, steps)
    total = len(timeline)
    i = 0
    held = None  # the chord of the hit being held
    while i * unit < total:
        ch = rhythm[i % steps]
        at = int(i * unit)
        if ch in "xX" or (ch == "-" and held is not None and timeline[at] != held):
            j = i + 1
            while j * unit < total and rhythm[j % steps] == "-" and timeline[int(j * unit)] == timeline[at]:
                j += 1
            v = voicing(timeline[at], lo, hi, prev, size)
            prev, held = v, timeline[at]
            ln = (j - i) * unit
            out.append("+".join(name_of(p, True) for p in v) + f":{ln}" + ("." if j - i == 1 else "") + (">" if ch == "X" else ""))
            i = j
        else:
            held = None
            out.append(f"r:{unit}")
            i += 1
    return " ".join(out)


def bassline(prog: list[tuple[str, float]], pattern: str, octave_low: str = "E1", bar16: int = 16) -> str:
    """A bass line from a pattern of degrees for each bar ('R:4 5:2 O:2 ...': R root, 3 third, 5 fifth, 7 seventh, O octave,
    6 sixth, A the half step under the next chord's root, 5d the fifth under the root, r rest), using the chord's bass
    (a slash chord's) for R; the pattern repeats over the progression."""
    lo = midi_of(octave_low)
    toks = pattern.split()
    timeline = []
    for name, n in prog:
        timeline += [name] * int(n)
    out, i, pos = [], 0, Fraction(0)
    while pos < len(timeline):
        deg, _, ln = toks[i % len(toks)].partition(":")
        ln = Fraction(ln or 4)
        name = timeline[int(pos)]
        root, iv, bass = chord(name)
        r = place(bass, lo)
        nxt_name = timeline[int(min(len(timeline) - 1, pos + ln))] if pos + ln < len(timeline) else timeline[0]
        flag = ""
        if deg.endswith("."):
            deg, flag = deg[:-1], "."
        third = next((x for x in iv if x in (3, 4)), 4)
        seventh = next((x for x in iv if x in (10, 11)), 10)
        if deg == "r":
            out.append(f"r:{ln}")
        else:
            nxt = place(chord(nxt_name)[2], lo)
            p = {"R": r, "O": r + 12, "5": place((root + 7) % 12, r), "3": place((root + third) % 12, r),
                 "7": place((root + seventh) % 12, r), "6": place((root + 9) % 12, r), "A": nxt - 1 if nxt - 1 >= lo else nxt + 11,
                 "5d": place((root + 7) % 12, r) - 12}[deg]
            out.append(f"{name_of(p, True)}:{ln}{flag}")
        pos += ln
        i += 1
    return " ".join(out)


def arp(prog: list[tuple[str, float]], order: list[int], low: str, high: str, step: float = 2, size: int = 4) -> str:
    """Broken chords: each chord's notes (as `voicing` places them, `size` of them, lowest first), played in `order` (indices; an
    index past the voicing climbs an octave), a note every `step` sixteenths."""
    lo, hi = midi_of(low), midi_of(high)
    out, prev = [], None
    k = 0
    for name, n in prog:
        v = voicing(name, lo, hi, prev, size)
        prev = v
        t = Fraction(0)
        while t < n:
            idx = order[k % len(order)]
            p = v[idx % len(v)] + 12 * (idx // len(v))
            out.append(f"{name_of(p, True)}:{step}")
            t += Fraction(step)
            k += 1
    return " ".join(out)


# ------------------------------------------------------------------ songs

@dataclass
class Track:
    name: str
    ch: int
    prog: int
    vol: int = 100
    pan: int = 64
    rev: int = 0
    strum: int = 0  # ticks between the strings of a chord struck at once (a guitar's strum: down on the beat, up off it)


@dataclass
class Song:
    name: str
    bpm: float
    key: str
    beats: int = 4
    swing: float = 0.0  # 0: straight; 1/3: triplet swing of the eighths (the off eighth late by a third of a beat... of its half)
    jingle: bool = False
    master: float = 1.0
    about: str = ""
    tracks: dict = field(default_factory=dict)
    parts: dict = field(default_factory=dict)
    intro: list = field(default_factory=list)
    body: list = field(default_factory=list)

    @property
    def bar16(self) -> int:
        return self.beats * 4

    def track(self, name: str, ch: int, prog: int, vol: int = 100, pan: float = 0, rev: int = 20, strum: int = 0) -> Song:
        self.tracks[name] = Track(name, ch, prog, vol, int(round(64 + pan * 63)), rev, strum)
        return self

    def part(self, name: str, bars: int, **voices: str) -> Song:
        for t in voices:
            if t not in self.tracks:
                raise ValueError(f"{self.name}/{name}: no track {t!r}")
        self.parts[name] = (bars, voices)
        return self

    def form(self, intro: list[str], body: list[str]) -> Song:
        self.intro, self.body = intro, body
        return self

    def swung(self, tick: int) -> int:
        if not self.swing:
            return tick
        beat, at = divmod(tick, PPQ)
        half = PPQ // 2
        late = self.swing * half
        if at <= half:
            return beat * PPQ + int(round(at * (half + late) / half))
        return beat * PPQ + int(round(half + late + (at - half) * (half - late) / half))

    def build(self):
        """-> (notes, controls, loop start tick or None, loop end tick, song end tick)"""
        notes: list[Note] = []
        ctls: list[Ctl] = []
        t = 0
        loop_start = None
        for i, pname in enumerate(self.intro + self.body):
            if i == len(self.intro) and not self.jingle:
                loop_start = t
            bars, voices = self.parts[pname]
            length = bars * self.bar16 * SIX
            for tname, text in voices.items():
                where = f"{self.name}/{pname}/{tname}"
                if not text:
                    continue
                if self.tracks[tname].ch == 9:
                    ns, ln = parse_drums(text, t, self.bar16, tname, where)
                    cs = []
                else:
                    ns, cs, ln = parse_voice(text, t, self.bar16, tname, where)
                if ln > length:
                    raise ValueError(f"{where}: {ln / SIX / self.bar16} bars, the part has {bars}")
                notes += ns
                ctls += cs
            t += length
        end = t
        self._strum(notes)
        for n in notes:
            a, b, g = self.swung(n.start), self.swung(n.start + n.dur), self.swung(n.start + n.gated)
            n.start, n.dur, n.gated = a, max(6, b - a), max(6, g - a)
        for c in ctls:
            c.tick = self.swung(c.tick)
        return notes, ctls, loop_start, end, end

    def _strum(self, notes: list[Note]) -> None:
        """Chords on a strummed track spread out: low to high on the beat's eighths, high to low (an up stroke) off them."""
        by: dict = {}
        for n in notes:
            k = self.tracks[n.track].strum
            if k and self.tracks[n.track].ch != 9:
                by.setdefault((n.track, n.start), []).append(n)
        for (tname, start), group in by.items():
            if len(group) < 2:
                continue
            k = self.tracks[tname].strum
            up = (start % PPQ) == PPQ // 2 or (start % PPQ) == 3 * PPQ // 4
            for i, n in enumerate(sorted(group, key=lambda n: -n.key if up else n.key)):
                d = min(i * k, max(0, n.dur - 6))
                n.start += d
                n.dur -= d
                n.gated = max(6, n.gated - d)

    def seconds(self, ticks: int) -> float:
        return ticks / PPQ * 60 / self.bpm


# ------------------------------------------------------------------ the file

def varlen(v: int) -> bytes:
    out = [v & 0x7F]
    v >>= 7
    while v:
        out.append(0x80 | (v & 0x7F))
        v >>= 7
    return bytes(reversed(out))


def track_chunk(events: list[tuple[int, int, bytes]]) -> bytes:
    """events: (tick, order, bytes); written in time order, end of track after the last."""
    body = bytearray()
    last = 0
    for tick, _, data in sorted(events, key=lambda e: (e[0], e[1])):
        body += varlen(tick - last) + data
        last = tick
    body += varlen(0) + b"\xff\x2f\x00"
    return b"MTrk" + struct.pack(">I", len(body)) + bytes(body)


def write_smf(song: Song, path: Path, jingle_tail_s: float = 2.0) -> dict:
    notes, ctls, loop_start, loop_end, end = song.build()
    usec = int(round(60_000_000 / song.bpm))
    meta = [(0, 0, b"\xff\x51\x03" + usec.to_bytes(3, "big")),
            (0, 1, b"\xff\x58\x04" + bytes([song.beats, 2, 24, 8])),
            (0, 2, b"\xff\x03" + varlen(len(song.name)) + song.name.encode())]
    if song.jingle:
        # played once (loop = false) it ends; asked to loop, it goes round a stretch of silence after its tail
        end = max(n.start + n.dur for n in notes)
        tail = int(jingle_tail_s * song.bpm / 60 * PPQ)
        loop_start, loop_end = end + tail, end + tail + PPQ
        end = loop_end
    meta.append((loop_start, 3, b"\xff\x06\x09loopStart"))
    meta.append((loop_end, 4, b"\xff\x06\x07loopEnd"))
    meta.append((end, 5, b"\xff\x01\x00"))  # (an empty text event: the song's last tick)
    chunks = [track_chunk(meta)]
    for tr in song.tracks.values():
        c = tr.ch
        want = tr.vol * song.master
        vel_k = (want / 127) ** 0.5 if want > 127 else 1.0  # (past 127 the rest goes on the velocities: a note's gain is velocity squared)
        ev = [(0, 0, bytes([0xC0 | c, tr.prog])), (0, 1, bytes([0xB0 | c, 7, max(1, min(127, int(round(want))))])),
              (0, 2, bytes([0xB0 | c, 10, tr.pan])), (0, 3, bytes([0xB0 | c, 91, tr.rev])), (0, 4, bytes([0xE0 | c, 0, 64]))]
        if loop_start:  # what the channel is set to, again where the loop comes back to
            ev += [(loop_start, 0, bytes([0xC0 | c, tr.prog])), (loop_start, 1, bytes([0xE0 | c, 0, 64]))]
        for n in notes:
            if n.track != tr.name:
                continue
            ev.append((n.start, 6, bytes([0x90 | c, n.key, min(127, int(round(n.vel * vel_k)))])))
            ev.append((n.start + n.dur, 5, bytes([0x80 | c, n.key, 0])))
        for x in ctls:
            if x.track != tr.name:
                continue
            if x.kind == "prog":
                ev.append((x.tick, 2, bytes([0xC0 | c, x.value])))
            else:
                v = max(0, min(16383, x.value + 8192))
                ev.append((x.tick, 3, bytes([0xE0 | c, v & 0x7F, v >> 7])))
        chunks.append(track_chunk(ev))
    head = b"MThd" + struct.pack(">IHHH", 6, 1, len(chunks), PPQ)
    path.write_bytes(head + b"".join(chunks))
    music_end = max(n.start + n.dur for n in notes) if song.jingle else song.build()[3]
    return {"notes": notes, "loop_start": loop_start, "loop_end": loop_end, "end": end, "music_end": music_end}


# ------------------------------------------------------------------ checks on the notes

def program_at(song: Song, notes: list[Note], ctls: list[Ctl]) -> list[tuple[Note, int]]:
    """Each note with the program it is played by (the track's, or the last @ change before it)."""
    out = []
    for n in notes:
        tr = song.tracks[n.track]
        prog = tr.prog
        for c in sorted((c for c in ctls if c.track == n.track and c.kind == "prog"), key=lambda c: c.tick):
            if c.tick <= n.start:
                prog = c.value
        out.append((n, prog))
    return out


def check_coverage(song: Song, programs: dict[int, tuple[int, int]], drum_keys: set[int]) -> list[str]:
    notes, ctls, *_ = song.build()
    bad = []
    for n, prog in program_at(song, notes, ctls):
        if song.tracks[n.track].ch == 9:
            if n.key not in drum_keys:
                bad.append(f"drum key {n.key}")
        elif prog not in programs or not programs[prog][0] <= n.key <= programs[prog][1]:
            bad.append(f"program {prog} key {n.key}")
    return sorted(set(bad))


def polyphony(song: Song, release_of, length_of_sample, limit: int = 16) -> tuple[int, float, float]:
    """The most voices sounding at once (a note from its start to its end plus its release, or its sample's end if sooner), the
    time it happens (seconds), and the share of the song's time when more than `limit` sound (the engine then takes the oldest)."""
    notes, ctls, *_ = song.build()
    spans = []
    for n, prog in program_at(song, notes, ctls):
        drum = song.tracks[n.track].ch == 9
        a = song.seconds(n.start)
        rel, smp_len = release_of(prog, n.key, drum), length_of_sample(prog, n.key, drum)
        b = a + song.seconds(n.dur) + rel * 1.33  # (a voice lasts until its release has fallen 80 dB: 1.33 times its 60)
        if smp_len is not None:
            b = min(b, a + smp_len)
        spans.append((a, 1))
        spans.append((b, -1))
    cur = most = 0
    when = last = over = 0.0
    for t, d in sorted(spans, key=lambda x: (x[0], x[1])):
        if cur > limit:
            over += t - last
        last = t
        cur += d
        if cur > most:
            most, when = cur, t
    return most, when, over / max(last, 1e-9)


def harmony_clashes(song: Song, skip: tuple[str, ...] = ()) -> list[str]:
    """Places where two pitched notes a semitone apart (a minor second or ninth) sound together for at least an eighth note,
    both struck on or held over a beat: what would grate. Listed as bar:beat and the two tracks."""
    notes, *_ = song.build()
    pitched = [n for n in notes if song.tracks[n.track].ch != 9 and n.track not in skip]
    found = []
    step = SIX
    end = max(n.start + n.dur for n in pitched) if pitched else 0
    for t in range(0, end, step):
        if t % (PPQ // 2):  # sample on eighth notes
            continue
        now = [n for n in pitched if n.start <= t < n.start + min(n.dur, n.gated or n.dur)]
        for i, x in enumerate(now):
            for y in now[i + 1:]:
                d = abs(x.key - y.key)
                if d in (1, 13):
                    overlap = min(x.start + x.dur, y.start + y.dur) - t
                    if overlap >= PPQ // 2:
                        bar, at = divmod(t, PPQ * song.beats)
                        found.append(f"{bar + 1}:{at / PPQ + 1:g} {x.track} {name_of(x.key)} / {y.track} {name_of(y.key)}")
    return sorted(set(found), key=lambda s: (int(s.split(":")[0]), s))
