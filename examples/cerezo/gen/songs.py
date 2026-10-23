#!/usr/bin/env python3
"""Cerezo's music: every song and jingle of the game as a ProTracker module (M.K., 31 samples, four channels) that the
engine plays with music("name"), written here as readable Python.

    python3 gen/songs.py               writes audio/<name>.mod for every song and prints a table
    python3 gen/songs.py title boss    only those

The four channels are the Game Boy's: 0 pulse 1 (the lead), 1 pulse 2 (arpeggios, echo, counter-melody), 2 the wave
(the bass, now and then a lead) and 3 the noise (drums). The samples are the console's voices: pulses of 12.5, 25, 50
and 75 % (one period, `sample_square` of tools/famistudio2mod.py, whose tuning this keeps: period 428 is C4), two
32-step 4-bit waves (`wa` round, for the bass; `wb` thin, for leads; `tri` is the converter's triangle) and noise hits
(hat, open hat, snare, kick, crash, tick) made by a 15-bit LFSR like the console's, its clock falling for the kick.
The periods reach three octaves (C3-B5); a note out of them takes the same shape at double or half length, an octave
down or up, so the bass goes down to C1 and the leads up to B6.

A song is parts (a bar count and a voice for each channel) played in a form: an intro once, then a body that loops (a
Bxx on its last line goes back to its first pattern; the header's restart says the same). A jingle ends in a silent
pattern that loops on itself. Time: `speed` ticks a row and `tempo` (0.4 x tempo ticks a second: 150 is the Game Boy's
60 Hz frame), so at 4 rows a beat BPM = 6 x tempo / speed; speeds of 3, 6, 9, 12 keep the 0xy arpeggios even.

A voice is a string of tokens, a row the unit of length:
    C5:4   a note (C, C#, Db ... B; octave 4 holds middle C) four rows long; without :n the length set by L
    E4+G4+C5:8   a chord: an arpeggio (0xy) from its lowest note, the other two up to 15 semitones over it
    r:4  a rest      -:4  the note before held longer (a tie)     |  a bar line (each bar is checked)
    _D5:2  slurred: a new pitch with no new attack (the volume goes on)      ^D5:2  glides there (3xx)
    after the length: . staccato (half), ' short (a row), * held to its end, > accent, ~ vibrato at once, = none
    @name  the instrument from here on      v40  the attack volume from here on (0-64; v alone: the instrument's)
    L2  the default length                  {3}  the next note waits 3 ticks into its row (EDx)
Drums are a row a character (`.` nothing; the song's kit says what each letter plays and how loud). `Echo(...)` as a
voice copies another channel's notes a few rows or ticks later, quieter: the console's echo.

How a note becomes rows: its first row sets the period, the sample and the volume (Cxx, or a copy of the sample whose
own volume is the one wanted when the effect column is taken); the rows after it draw the volume envelope with Axy
(the decay, a tick at a time like the console's envelope) and the vibrato with 4xy (6xy when both), and a note let go
early fades with A0F. A chord's rows carry its 0xy and its envelope goes through the instrument column, row by row
(each level a copy of the sample at that volume). Speed, tempo and the loop's jump take free effect cells.
"""
from __future__ import annotations

import math
import re
import struct
import sys
from dataclasses import dataclass, field
from pathlib import Path

sys.dont_write_bytecode = True  # (nothing written beside the converter borrowed from tools/)
HERE = Path(__file__).resolve().parent
GAME = HERE.parent
sys.path.insert(0, str(GAME.parents[1] / "tools"))
from famistudio2mod import PERIODS, sample_noise, sample_square, sample_triangle  # noqa: E402

PAL_CLOCK = 3546894.6  # pocketmod's (an Amiga's): a sample byte lasts period / PAL_CLOCK seconds
LOW_MIDI = 48          # C3: period 856 (the table's first) with a 32-byte period; 428 is C4 (MIDI 60)
NOTE_INDEX = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
ROWS_PATTERN = 64


# ---------------------------------------------------------------------------------------------------------- samples

def _signed(values) -> bytes:
    return bytes(int(round(v)) & 255 for v in values)


def _wave4(levels) -> bytes:
    """32 levels 0..15 (the console's wave RAM) as signed bytes, +-120."""
    return _signed((lv - 7.5) * 16 for lv in levels)


def _wave_a() -> bytes:
    """The bass wave: a sine pushed towards a square and tilted a little, round (nothing over the fifth harmonic
    louder than -21 dB) but with a third and a second (-12 and -14 dB) that carry it on a small speaker. As wave
    RAM: ADEFFFEEDDCCCCB96433332211000125."""
    xs = [2 * math.pi * (i + 0.5) / 32 for i in range(32)]
    v = [math.tanh(3 * math.sin(x)) + 0.25 * math.sin(2 * x) for x in xs]
    lo, hi = min(v), max(v)
    return _wave4(round((y - lo) / (hi - lo) * 15) for y in v)


def _wave_b() -> bytes:
    """The thin lead wave: a 4-bit ramp (a saw), bright and reedy."""
    return _wave4(15 - i // 2 for i in range(32))


SHAPES = {
    "p12": sample_square(0.125), "p25": sample_square(0.25), "p50": sample_square(0.5), "p75": sample_square(0.75),
    "wa": _wave_a(), "wb": _wave_b(), "tri": sample_triangle(),
}


def _shifted(data: bytes, shift: int) -> bytes:
    """One period of a shape an octave up (shift 1: half as many bytes) or down (-1: each byte twice)."""
    if shift == 0:
        return data
    if shift > 0:
        step = 1 << shift
        vals = [b - 256 if b > 127 else b for b in data]
        return _signed(sum(vals[i:i + step]) / step for i in range(0, len(vals), step))
    return bytes(b for b in data for _ in range(1 << -shift))


class Lfsr:
    """The noise channel's 15-bit LFSR (7-bit when short), clocked at a rate that may change as it plays."""

    def __init__(self, short: bool = False):
        self.reg, self.short, self.phase = 0x7FFF, short, 0.0

    def run(self, clock_hz: float, rate: int) -> float:
        """The output (-1 or 1, averaged over the clocks inside one sample at `rate`)."""
        self.phase += clock_hz / rate
        n, acc = 0, 0.0
        while self.phase >= 1:
            self.phase -= 1
            bit = (self.reg ^ (self.reg >> 1)) & 1
            self.reg = (self.reg >> 1) | (bit << 14)
            if self.short:
                self.reg = (self.reg & ~0x40) | (bit << 6)
            acc += 1 if self.reg & 1 else -1
            n += 1
        return acc / n if n else (1 if self.reg & 1 else -1)


def _hit(seconds: float, rate: int, clock, env, amp: float = 118, short: bool = False, tone=None) -> bytes:
    """A one-shot noise hit: `clock(t)` the LFSR's clock in Hz, `env(t)` its level 0..1, `tone(t)` an extra wave."""
    lf, out, last = Lfsr(short), [0, 0], 0.0  # (two zero bytes first: ProTracker's idle loop of a one-shot)
    for i in range(int(seconds * rate)):
        t = i / rate
        last = lf.run(clock(t), rate)
        v = (last * env(t) + (tone(t) if tone else 0)) * min(1.0, (seconds - t) / 0.01)
        out.append(max(-127, min(127, v * amp)))
    return _signed(out)


NOISE_FAST = 161  # period of the hits made at 22030 Hz (the engine mixes at 22050: almost no resampling)
NOISE_SLOW = 322  # those made at 11015 Hz (longer, darker hits: half the bytes)


def _rate(period: int) -> int:
    return round(PAL_CLOCK / period)


def _make_hits() -> dict[str, tuple[bytes, int]]:
    fast, slow = _rate(NOISE_FAST), _rate(NOISE_SLOW)
    kick_phase = [0.0]

    def kick_tone(t: float) -> float:  # a thud falling from 150 to 48 Hz under the noise
        f = 48 + 102 * math.exp(-t / 0.025)
        kick_phase[0] += f / slow
        return math.sin(2 * math.pi * kick_phase[0]) * 0.9 * math.exp(-t / 0.07)

    return {
        "hat": (_hit(0.045, fast, lambda t: 262144, lambda t: math.exp(-t / 0.011)), NOISE_FAST),
        "ohat": (_hit(0.13, fast, lambda t: 262144, lambda t: math.exp(-t / 0.05), amp=100), NOISE_FAST),
        "snare": (_hit(0.13, fast, lambda t: 65536 - 30000 * min(1, t / 0.1), lambda t: math.exp(-t / 0.045)), NOISE_FAST),
        "kick": (_hit(0.12, slow, lambda t: 300 + 3700 * math.exp(-t / 0.018), lambda t: 0.45 * math.exp(-t / 0.02),
                      tone=kick_tone), NOISE_SLOW),
        "crash": (_hit(0.42, slow, lambda t: 131072, lambda t: math.exp(-t / 0.16), amp=105), NOISE_SLOW),
        "tick": (_hit(0.03, fast, lambda t: 21845, lambda t: math.exp(-t / 0.008), short=True), NOISE_FAST),
    }


HITS = _make_hits()


# ---------------------------------------------------------------------------------------------------------- music

@dataclass(frozen=True)
class Inst:
    """How a channel sounds a note: its shape, attack, envelope, vibrato and articulation."""
    shape: str
    vol: int = 48             # the attack (0..64)
    decay: float = 0.0        # volume lost a tick after the attack (0: held), as the console's envelope
    sustain: int = 0          # the level the decay stops at
    hold: float = 0.0         # seconds at the attack before the decay
    vib: float = 0.0          # vibrato depth, cents (0: none)
    vib_delay: float = 0.3    # seconds into a note before its vibrato (shorter notes have none)
    vib_hz: float = 5.5
    gate: float = 1.0         # the part of a note that sounds (staccato under 1; at least a row)
    steps: tuple[int, ...] = ()  # a chord's volume row by row (the last one held); empty: from the envelope
    shift: int | None = None  # the sample's octave (None: whichever reaches the note)
    release: int = 15         # volume a tick lost when a note is let go early (A0x); 0: cut at once


@dataclass(frozen=True)
class Echo:
    """A voice that is another channel's notes `rows` rows and `ticks` ticks later, played by `inst`."""
    src: int = 0
    rows: int = 0
    ticks: int = 3
    inst: str = "echo"


@dataclass
class Ev:
    row: int
    length: int
    notes: tuple[int, ...] = ()  # one note, a chord (an arpeggio), or none (a rest)
    inst: str = ""
    vol: int | None = None
    flags: str = ""
    ticks: int = 0
    hit: str | None = None


@dataclass
class Part:
    name: str
    bars: int
    voices: dict
    tempo: int | None = None
    speed: int | None = None


class Song:
    def __init__(self, name: str, *, tempo: int, speed: int, bar: int, beat: int = 4, pattern: int = ROWS_PATTERN,
                 key: str = "", meter: str = "4/4", jingle: bool = False):
        self.name, self.tempo, self.speed, self.bar, self.beat = name, tempo, speed, bar, beat
        self.pattern, self.key, self.meter, self.jingle = pattern, key, meter, jingle
        self.insts: dict[str, Inst] = {}
        self.kit: dict[str, tuple[str, int]] = {}
        self.defaults: dict[int, str] = {}
        self.parts: dict[str, Part] = {}
        self.intro: list[str] = []
        self.body: list[str] = []
        self.doc = ""

    def inst(self, name: str, inst: Inst, *channels: int) -> Song:
        """An instrument; the first one given a channel is the one its voices start with."""
        self.insts[name] = inst
        for ch in channels:
            self.defaults.setdefault(ch, name)
        return self

    def drums(self, **kit: tuple[str, int]) -> Song:
        self.kit.update(kit)
        return self

    def part(self, name: str, bars: int, v0="", v1="", v2="", v3="", tempo: int | None = None,
             speed: int | None = None) -> Song:
        self.parts[name] = Part(name, bars, {0: v0, 1: v1, 2: v2, 3: v3}, tempo, speed)
        return self

    def form(self, intro: list[str], body: list[str]) -> Song:
        self.intro, self.body = intro, body
        return self

    @property
    def bpm(self) -> float:
        return 24 * self.tempo / (self.speed * self.beat)


# ---------------------------------------------------------------------------------------------------------- parsing

TOKEN_NOTE = re.compile(r"^([_^]?)((?:[A-G](?:#|b)?-?\d)(?:\+[A-G](?:#|b)?-?\d)*)(?::(\d+))?([.'>~=*]*)$")
ONE_NOTE = re.compile(r"([A-G])(#|b)?(-?\d)")


def midi_of(name: str) -> int:
    m = ONE_NOTE.fullmatch(name)
    if not m:
        raise ValueError(f"not a note: {name}")
    semis = NOTE_INDEX[m.group(1)] + {"#": 1, "b": -1, None: 0}[m.group(2)]
    return 12 * (int(m.group(3)) + 1) + semis


def transpose(text: str, semis: int, flats: bool = False) -> str:
    """The same voice `semis` semitones away (sharps unless `flats`)."""
    names = ["C", "Db" if flats else "C#", "D", "Eb" if flats else "D#", "E", "F", "Gb" if flats else "F#", "G",
             "Ab" if flats else "G#", "A", "Bb" if flats else "A#", "B"]

    def one(m: re.Match) -> str:
        n = midi_of(m.group(0)) + semis
        return f"{names[n % 12]}{n // 12 - 1}"
    return re.sub(r"(?<![A-Za-z@])[A-G](?:#|b)?-?\d", one, text)


def parse_voice(text: str, song: Song, start: int, rows: int, ch: int, where: str) -> list[Ev]:
    """A voice's tokens as events from row `start`, checked against its bars and its part's length."""
    evs: list[Ev] = []
    row, bar_start = start, start
    inst = song.defaults.get(ch, "")
    vol: int | None = None
    deflen = song.beat
    ticks = 0
    for tok in text.replace("|", " | ").split():
        if tok == "|":
            if row - bar_start != song.bar:
                raise ValueError(f"{where}: a bar of {row - bar_start} rows (not {song.bar}) ending at row {row - start}")
            bar_start = row
            continue
        if tok.startswith("@"):
            inst = tok[1:]
            if inst not in song.insts:
                raise ValueError(f"{where}: no instrument {inst}")
            continue
        if re.fullmatch(r"v\d*", tok):
            vol = int(tok[1:]) if len(tok) > 1 else None
            continue
        if re.fullmatch(r"L\d+", tok):
            deflen = int(tok[1:])
            continue
        if re.fullmatch(r"\{\d+\}", tok):
            ticks = int(tok[1:-1])
            continue
        m = re.fullmatch(r"([r-])(?::(\d+))?", tok)
        if m:
            n = int(m.group(2)) if m.group(2) else deflen
            if m.group(1) == "-":
                if not evs:
                    raise ValueError(f"{where}: a tie with nothing before it")
                evs[-1].length += n
            else:
                evs.append(Ev(row, n, (), inst))
            row += n
            continue
        m = TOKEN_NOTE.fullmatch(tok)
        if not m:
            raise ValueError(f"{where}: cannot read '{tok}'")
        notes = tuple(midi_of(x) for x in m.group(2).split("+"))
        if len(notes) > 3 or any(not 0 < n - notes[0] <= 15 for n in notes[1:]):
            raise ValueError(f"{where}: '{tok}' is not a chord an arpeggio plays (three notes, 15 semitones up)")
        n = int(m.group(3)) if m.group(3) else deflen
        evs.append(Ev(row, n, notes, inst, vol, m.group(1) + m.group(4), ticks))
        ticks = 0
        row += n
    if row - start not in (0, rows):
        raise ValueError(f"{where}: {row - start} rows, the part has {rows}")
    if row - start == 0:
        evs.append(Ev(start, rows, (), inst))
    return evs


def parse_drums(text: str, song: Song, start: int, rows: int, where: str) -> list[Ev]:
    evs: list[Ev] = []
    row, bar_start = start, start
    for c in text.replace(" ", ""):
        if c == "|":
            if row - bar_start != song.bar:
                raise ValueError(f"{where}: a drum bar of {row - bar_start} rows ending at row {row - start}")
            bar_start = row
            continue
        if c != ".":
            if c not in song.kit:
                raise ValueError(f"{where}: no drum '{c}' in the kit")
            name, level = song.kit[c]
            evs.append(Ev(row, 1, (), "", level, "", 0, name))
        row += 1
    if row - start not in (0, rows):
        raise ValueError(f"{where}: drums of {row - start} rows, the part has {rows}")
    return evs


# ---------------------------------------------------------------------------------------------------------- rendering

@dataclass
class Cell:
    period: int = 0
    family: str | None = None  # the sample (shape and octave, or a hit) a note starts or a volume is set through
    vol: int | None = None     # the volume from this row
    fx: int | None = None      # effect (0..15)
    param: int = 0
    soft: bool = False         # an effect that may give way to the song's own commands (a slide, a vibrato row)


MIN_PERIOD = 162  # pocketmod stalls a looped sample whose step passes a byte an output sample (period < 161 at 22050 Hz)


def family_for(shape: str, midi: int, shift: int | None, span: int = 0, swing: float = 0) -> tuple[str, int, int]:
    """The sample (shape at an octave) and the period that play `midi`, and the bytes in its period. The period stays
    at MIN_PERIOD or over even at the top of a chord `span` semitones wide and of a vibrato `swing` cents deep."""
    def lowest(period: int) -> float:
        return period / 2 ** ((span + swing / 100) / 12)
    if shift is None:  # the octave nearest the shape's own that reaches the note
        for shift in (0, -1, 1, -2, 2, -3, 3):
            idx = midi - LOW_MIDI - 12 * shift
            if 0 <= idx < len(PERIODS) and lowest(PERIODS[idx]) >= MIN_PERIOD:
                break
    idx = midi - LOW_MIDI - 12 * shift
    if not 0 <= idx < len(PERIODS):
        raise ValueError(f"note {midi} out of reach of {shape} at octave shift {shift}")
    if lowest(PERIODS[idx]) < MIN_PERIOD:
        raise ValueError(f"note {midi} on {shape} at octave shift {shift} needs a period under {MIN_PERIOD}")
    size = len(SHAPES[shape]) >> shift if shift >= 0 else len(SHAPES[shape]) << -shift
    return f"{shape}{shift:+d}", PERIODS[idx], size


class Renderer:
    def __init__(self, song: Song):
        self.song = song
        self.tick_hz = 0.4 * song.tempo

    def envelope(self, inst: Inst, v0: int, tick: int) -> float:
        t_hold = inst.hold * self.tick_hz
        if inst.decay <= 0 or tick <= t_hold:
            return v0
        return max(min(inst.sustain, v0), v0 - inst.decay * (tick - t_hold))

    def vib_param(self, inst: Inst, period: int, speed: int) -> int:
        x = max(1, min(15, round(inst.vib_hz * 64 * speed / ((speed - 1) * self.tick_hz))))
        y = max(1, min(15, round(inst.vib * period / 3462)))
        return x << 4 | y

    def channel(self, evs: list[Ev], cells: list[Cell], speed_at, starts: set[int]) -> list[tuple]:
        """Writes a channel's events into its cells; returns its notes (row, rows, midis, kind, period, bytes). At a
        part's first row anything may be sounding (the loop comes back there from its end): a rest there always fades
        and a note always starts afresh."""
        song, notes = self.song, []
        evs = sorted(evs, key=lambda e: e.row)
        vol, sounding, family, release = 0, False, None, 15
        for k, ev in enumerate(evs):
            end = evs[k + 1].row if k + 1 < len(evs) else len(cells)
            length = min(ev.length, end - ev.row)
            c0 = cells[ev.row]
            if ev.row in starts:
                vol, sounding, family = max(vol, 64), True, None
            if ev.hit:
                c0.period, c0.family, c0.vol = HITS[ev.hit][1], ev.hit, ev.vol
                notes.append((ev.row, 1, (), "hit:" + ev.hit, HITS[ev.hit][1], 0))
                continue
            if not ev.notes:  # a rest: what still sounds fades out (or stops on the tick an echo's rest falls)
                if sounding and vol > 0:
                    if ev.ticks:
                        c0.fx, c0.param = 0xE, 0xC0 | ev.ticks
                    else:
                        self.fade(cells, ev.row, ev.row + length, vol, release, speed_at)
                vol, sounding = 0, False
                continue
            inst = song.insts[ev.inst]
            speed = speed_at(ev.row)
            fam, period, size = family_for(inst.shape, ev.notes[0], inst.shift, max(ev.notes) - ev.notes[0],
                                           2.5 * inst.vib)
            flags = ev.flags
            v0 = ev.vol if ev.vol is not None else inst.vol
            if ">" in flags:
                v0 = min(64, v0 + 10)
            legato = ("_" in flags or "^" in flags) and sounding and fam == family and vol > 0
            c0.period = period
            if ev.ticks:
                c0.fx, c0.param = 0xE, 0xD0 | ev.ticks
            if legato and "^" in flags:
                prev = notes[-1][4] if notes else period
                c0.fx, c0.param = 3, max(1, min(255, math.ceil(abs(prev - period) / max(1, speed - 1))))
            if legato:
                v0 = vol  # (the envelope goes on from where it is)
            else:
                c0.family, c0.vol, vol = fam, v0, v0
            family, sounding, release = fam, True, inst.release
            gate = length
            if "'" in flags:
                gate = 1
            elif "." in flags:
                gate = max(1, length // 2)
            elif inst.gate < 1 and "*" not in flags:
                gate = max(1, min(length, round(length * inst.gate)))
            chord = len(ev.notes) > 1
            kind = "chord" if chord else "echo" if "e" in flags else "glide" if legato and "^" in flags else "note"
            notes.append((ev.row, gate, ev.notes, kind, period, size))
            if chord:
                vol = self.chord(inst, ev, cells, gate, v0, legato, fam, speed)
            else:
                vol = self.tone(inst, ev, cells, gate, v0, vol, legato, period, speed, flags)
            if gate < length:  # let go early: a quick fade (or a cut), then nothing until the next event
                self.fade(cells, ev.row + gate, ev.row + length, vol, inst.release, speed_at)
                vol, sounding = 0, False
        return notes

    @staticmethod
    def fade(cells: list[Cell], row: int, end: int, vol: int, release: int, speed_at) -> None:
        if not release:
            cells[row].vol = 0
            return
        while vol > 0 and row < end:
            cells[row].fx, cells[row].param, cells[row].soft = 0xA, release, True
            vol -= release * (speed_at(row) - 1)
            row += 1

    def chord(self, inst: Inst, ev: Ev, cells: list[Cell], gate: int, v0: int, legato: bool, fam: str,
              speed: int) -> int:
        """An arpeggio: its 0xy on every row it sounds, its envelope through the instrument column."""
        arp = (ev.notes[1] - ev.notes[0]) << 4 | (ev.notes[2] - ev.notes[0] if len(ev.notes) > 2 else 0)
        if inst.steps:
            levels = [s * v0 / inst.steps[0] for s in inst.steps]
        else:
            levels = [self.envelope(inst, v0, r * speed) for r in range(gate)]
        level = None
        for r in range(gate):
            cell = cells[ev.row + r]
            if r or cell.fx is None:
                cell.fx, cell.param = 0, arp
            want = int(round(levels[min(r, len(levels) - 1)] / 4) * 4)
            if r == 0:
                if legato:
                    cell.vol, cell.family = want, fam
                else:
                    cell.vol = want
                level = want
            elif want != level:
                cell.vol, cell.family, level = want, fam, want
        return level

    def tone(self, inst: Inst, ev: Ev, cells: list[Cell], gate: int, v0: int, vol: int, legato: bool, period: int,
             speed: int, flags: str) -> int:
        """A single note: its envelope with Axy (from the attack's own row for a pluck), its vibrato with 4xy/6xy."""
        c0 = cells[ev.row]
        if inst.decay > 0 and inst.hold <= 0 and c0.fx is None and not legato:
            y = min(15, round((v0 - self.envelope(inst, v0, speed)) / (speed - 1)))
            if y >= 1:
                c0.fx, c0.param, c0.soft = 0xA, y, True
                vol = max(0, vol - y * (speed - 1))
        vib_from = 0 if "~" in flags else math.ceil(inst.vib_delay * self.tick_hz / speed)
        want_vib = inst.vib > 0 and "=" not in flags and gate > max(1, vib_from)
        vp = self.vib_param(inst, period, speed) if want_vib else 0
        param4 = -1
        for r in range(1, gate):
            cell = cells[ev.row + r]
            target = self.envelope(inst, v0, (r + 1) * speed)
            y = max(0, min(15, round((vol - target) / (speed - 1))))
            if want_vib and r >= vib_from:
                if y and param4 == vp:
                    cell.fx, cell.param, cell.soft = 6, y, True
                    vol = max(0, vol - y * (speed - 1))
                else:
                    cell.fx, cell.param, cell.soft = 4, vp, True
                    param4 = vp
            elif y:
                cell.fx, cell.param, cell.soft = 0xA, y, True
                vol = max(0, vol - y * (speed - 1))
        return vol


# ---------------------------------------------------------------------------------------------------------- the module

@dataclass
class Built:
    data: bytes
    intro_s: float
    loop_s: float
    notes: dict = field(default_factory=dict)  # channel -> [(t0, t1, midis, kind, period, bytes)]
    row_time: list = field(default_factory=list)
    loop_row: int = 0


SHAPE_NAMES = {"p12": "pulse12", "p25": "pulse25", "p50": "pulse50", "p75": "pulse75", "wa": "wave_a", "wb": "wave_b",
               "tri": "triangle"}


def sample_name(fam: str, volume: int) -> str:
    """A slot's name in the module (a tracker shows it): the shape, its octave if not its own, its volume."""
    if fam in HITS:
        return f"{fam} v{volume}"
    m = re.fullmatch(r"(\w+?)([+-]\d+)", fam)
    shift = int(m.group(2))
    return f"{SHAPE_NAMES[m.group(1)]}{f' oct{shift:+d}' if shift else ''} v{volume}"


def build(song: Song, solo: int | None = None) -> Built:
    order_parts = song.intro + song.body
    if song.jingle:
        order_parts = order_parts + ["__silence"]
        song.parts["__silence"] = Part("__silence", max(1, ROWS_PATTERN // song.bar), {0: "", 1: "", 2: "", 3: ""})
    starts, total = [], 0
    for name in order_parts:
        starts.append(total)
        total += song.parts[name].bars * song.bar
    cells = [[Cell() for _ in range(total)] for _ in range(4)]
    # the time of each row
    speeds, tempos = [song.speed] * total, [song.tempo] * total
    for name, s0 in zip(order_parts, starts):
        p = song.parts[name]
        for r in range(s0, s0 + p.bars * song.bar):
            speeds[r] = p.speed or song.speed
            tempos[r] = p.tempo or song.tempo
    row_time = [0.0]
    for r in range(total):
        row_time.append(row_time[-1] + speeds[r] / (0.4 * tempos[r]))
    # the voices
    evs: dict[int, list[Ev]] = {ch: [] for ch in range(4)}
    for name, s0 in zip(order_parts, starts):
        p = song.parts[name]
        rows = p.bars * song.bar
        echoes = []
        for ch in range(4):
            v = p.voices.get(ch, "")
            where = f"{song.name}/{name}/ch{ch}"
            if isinstance(v, Echo):
                echoes.append((ch, v))
            elif ch == 3:
                evs[3] += parse_drums(v, song, s0, rows, where) if v else [Ev(s0, rows)]
            else:
                evs[ch] += parse_voice(v, song, s0, rows, ch, where)
        for ch, e in echoes:
            src = [x for x in evs[e.src] if s0 <= x.row < s0 + rows]
            out = [Ev(s0, e.rows, (), e.inst)] if e.rows else []
            for x in src:
                r = x.row + e.rows
                if r >= s0 + rows:
                    continue
                flags = x.flags.replace(">", "") + "e"  # (e: an echo, for the notes' list)
                out.append(Ev(r, min(x.length, s0 + rows - r), x.notes, e.inst if x.notes else x.inst,
                              None, flags, e.ticks))
            evs[ch] += out
    ren = Renderer(song)
    notes = {}
    for ch in range(4):
        if solo is not None and ch != solo:
            continue
        notes[ch] = ren.channel(evs[ch], cells[ch], lambda r: speeds[r], set(starts) - {0})

    # the song's own commands: speed and tempo where they change, the loop's jump at the end
    def free(row: int, avoid=()) -> int:
        for kind in range(3):
            for ch in (3, 2, 1, 0):
                c = cells[ch][row]
                if ch in avoid:
                    continue
                if (kind == 0 and c.fx is None and c.vol is None) or (kind == 1 and c.fx is None) or (kind == 2 and c.soft):
                    c.fx, c.soft = None, False
                    return ch
        raise ValueError(f"{song.name}: no free effect cell on row {row} for the song's commands")

    loop_row = starts[len(song.intro)] if song.body or song.jingle else 0
    for r in range(total):  # (at the loop's start only if the song's end runs at another speed or tempo)
        if r == 0 or speeds[r] != speeds[r - 1] or tempos[r] != tempos[r - 1] or (
                r == loop_row and (speeds[r], tempos[r]) != (speeds[-1], tempos[-1])):
            a = free(r)
            cells[a][r].fx, cells[a][r].param = 0xF, speeds[r]
            b = free(r, (a,))
            cells[b][r].fx, cells[b][r].param = 0xF, tempos[r]
    # patterns: each part cut in pieces of a pattern's rows (a short last piece ends with a break)
    pieces = []  # (first row, rows)
    for name, s0 in zip(order_parts, starts):
        rows = song.parts[name].bars * song.bar
        for a in range(0, rows, song.pattern):
            pieces.append((s0 + a, min(song.pattern, rows - a)))
    loop_order = next(i for i, (a, _) in enumerate(pieces) if a == loop_row)
    last_a, last_n = pieces[-1]
    c = free(last_a + last_n - 1)
    cells[c][last_a + last_n - 1].fx, cells[c][last_a + last_n - 1].param = 0xB, loop_order
    for a, n in pieces[:-1]:
        if n < 64:
            c = free(a + n - 1)
            cells[c][a + n - 1].fx, cells[c][a + n - 1].param = 0xD, 0

    # the samples: a slot for each (family, default volume) used
    slots: dict[tuple[str, int], int] = {}
    sample_list: list[tuple[str, bytes, bool, int]] = []

    def slot(fam: str, volume: int) -> int:
        key = (fam, volume)
        if key not in slots:
            if fam in HITS:
                data, looped = HITS[fam][0], False
            else:
                m = re.fullmatch(r"(\w+?)([+-]\d+)", fam)
                data, looped = _shifted(SHAPES[m.group(1)], int(m.group(2))), True
            sample_list.append((sample_name(fam, volume), data, looped, volume))
            slots[key] = len(sample_list)
            if len(sample_list) > 31:
                raise ValueError(f"{song.name}: more than 31 samples")
        return slots[key]

    def encode(c: Cell, family_now: str | None) -> tuple[bytes, str | None]:
        smp, fx, param = 0, c.fx, c.param
        fam = c.family or family_now
        if c.family and c.period:
            family_now = c.family
        if c.vol is not None:
            if c.family is None and fx is None:
                fx, param = 0xC, c.vol
            elif fx is None:
                smp = slot(c.family, 64)
                if c.vol != 64:
                    fx, param = 0xC, c.vol
            else:
                if fam is None:
                    raise ValueError(f"{song.name}: a volume with neither sample nor free effect")
                smp = slot(fam, c.vol)
        elif c.family:
            smp = slot(c.family, 64)
        if fx is None:
            fx, param = 0, 0
        b = bytes([(smp & 0xF0) | (c.period >> 8), c.period & 255, (smp & 15) << 4 | fx, param & 255])
        return b, family_now

    pattern_bytes: list[bytes] = []
    index: dict[bytes, int] = {}
    order: list[int] = []
    fam_now = [None] * 4
    for a, n in pieces:
        pat = bytearray(64 * 16)
        for r in range(n):
            for ch in range(4):
                b, fam_now[ch] = encode(cells[ch][a + r], fam_now[ch])
                pat[r * 16 + ch * 4: r * 16 + ch * 4 + 4] = b
        key = bytes(pat)
        if key not in index:
            index[key] = len(pattern_bytes)
            pattern_bytes.append(key)
        order.append(index[key])
    if len(order) > 128:
        raise ValueError(f"{song.name}: more than 128 positions")

    head = song.name.encode("ascii")[:20].ljust(20, b"\0")
    for i in range(31):
        if i < len(sample_list):
            name, data, looped, volume = sample_list[i]
            words = len(data) // 2
            head += name.encode("ascii")[:22].ljust(22, b"\0")
            head += struct.pack(">HBBHH", words, 0, min(64, volume), 0, words if looped else 1)
        else:
            head += bytes(22) + struct.pack(">HBBHH", 0, 0, 0, 0, 1)
    head += bytes([len(order), loop_order]) + bytes(order) + bytes(128 - len(order)) + b"M.K."
    data = head + b"".join(pattern_bytes) + b"".join(d for _, d, _, _ in sample_list)
    t = row_time
    out_notes = {ch: [(t[r], t[r + n], m, k, p, s) for r, n, m, k, p, s in lst] for ch, lst in notes.items()}
    body_rows = total - loop_row
    return Built(data, t[loop_row], t[total] - t[loop_row] if body_rows else 0, out_notes, t, loop_row)


# ---------------------------------------------------------------------------------------------------------- the songs

SONGS: dict[str, object] = {}  # name -> a function making its Song (in the order they are listed)


def song(fn):
    SONGS[fn.__name__] = fn
    return fn


def make(name: str) -> Song:
    fn = SONGS[name]
    s = fn()
    s.doc = (fn.__doc__ or "").strip()
    return s



def waltz(*bars: str, beat: int = 4) -> str:
    """The waltz's pah-pah: each bar's chord on beats 2 and 3 ("X Y": X on beat 2, Y on beat 3)."""
    out = []
    for bar in bars:
        x = bar.split()
        out.append(f"r:{beat} {x[0]}:{beat} {x[-1]}:{beat} |")
    return " ".join(out)


# ---------------------------------------------------------------------------------------------------------- 1. title

@song
def title():
    """D major, 96 BPM (speed 9, tempo 144: 57.6 Hz ticks), 4/4. Intro 2 bars (the harp alone), then A 8 bars and B 8
    bars, looping (40 s). The cherry tree's motif, D E A B F# (1 2 5 6 3, rising), opens both halves: over Gmaj7 in A
    it is tender and a little mysterious (Gmaj7 F#m7-Bm7 Em7 A), over D in B it is hopeful, and it climbs again a fourth
    higher (G A D E B) before settling on D. Lead: 25 % pulse, slow vibrato; pulse 2: a 12.5 % harp of broken chords in
    eighths; wave: long bass notes, walking in B; noise: soft off-beat hats in B only."""
    s = Song("title", tempo=144, speed=9, bar=16, key="D major")
    s.inst("lead", Inst("p25", vol=44, decay=0.25, sustain=34, vib=14, vib_delay=0.35, vib_hz=5), 0)
    s.inst("harp", Inst("p12", vol=30, decay=1.0, sustain=4), 1)
    s.inst("bass", Inst("wa", vol=56, gate=0.95), 2)
    s.drums(h=("hat", 12), o=("ohat", 18))
    gmaj7 = "G3:2 D4:2 F#4:2 B4:2 D5:2 B4:2 F#4:2 D4:2"
    fsm7 = "F#3:2 C#4:2 E4:2 A4:2 C#5:2 A4:2 E4:2 C#4:2"
    em7 = "E3:2 B3:2 D4:2 G4:2 B4:2 G4:2 D4:2 B3:2"
    bm7 = "B3:2 D4:2 F#4:2 A4:2 D5:2 A4:2 F#4:2 D4:2"
    d = "D4:2 F#4:2 A4:2 D5:2 F#5:2 D5:2 A4:2 F#4:2"
    s.part("intro", 2, "r:32", f"{gmaj7} | {fsm7} |", "G2:16 | F#2:16 |")
    s.part("A", 8,
           "D4:2 E4:2 A4:4 B4:2 F#5:6 | -:6 E5:2 D5:4 C#5:4 | B4:6 A4:2 G4:4 B4:4 | D5:8 C#5:8 |"
           "D4:2 E4:2 A4:4 B4:2 F#5:6 | -:4 A5:4 G5:2 F#5:2 D5:4 | E5:6 F#5:2 G5:4 F#5:4 | E5:12 r:4 |",
           f"{gmaj7} | F#3:2 C#4:2 E4:2 A4:2 B3:2 D4:2 F#4:2 A4:2 | {em7} | A3:2 D4:2 E4:2 A4:2 A3:2 C#4:2 E4:2 A4:2 |"
           f"{gmaj7} | {bm7} | {em7} | A3:2 E4:2 G4:2 D5:2 A3:2 E4:2 G4:2 C#5:2 |",
           "G2:16 | F#2:8 B2:8 | E2:16 | A2:8 E2:8 | G2:16 | B2:16 | E2:16 | A2:8 E2:4 C#3:4 |")
    s.part("B", 8,
           "D4:2 E4:2 A4:4 B4:2 F#5:6 | -:6 E5:2 C#5:4 A4:4 | G4:2 A4:2 D5:4 E5:2 B5:6 | -:6 A5:2 F#5:4 D5:4 |"
           "E5:6 F#5:2 G5:4 B5:4 | A5:8 F#5:4 D5:4 | E5:6 D5:2 C#5:4 E5:4 | D5:16 |",
           f"{d} | C#4:2 E4:2 A4:2 C#5:2 E5:2 C#5:2 A4:2 E4:2 | G3:2 D4:2 G4:2 B4:2 D5:2 B4:2 G4:2 D4:2 |"
           f"F#3:2 A3:2 D4:2 F#4:2 A4:2 F#4:2 D4:2 A3:2 | {em7} | A3:2 D4:2 F#4:2 A4:2 D5:2 A4:2 F#4:2 D4:2 |"
           f"E3:2 B3:2 D4:2 G4:2 A3:2 E4:2 G4:2 C#5:2 | {d} |",
           "D3:12 A2:4 | C#3:12 A2:4 | G2:12 E2:4 | F#2:12 D2:4 | E2:12 G2:4 | A2:12 F#2:4 | E2:8 A2:8 |"
           "D2:8 A2:4 F#2:4 |",
           "o.h...h...h...h.|..h...h...h...h.|..h...h...h...h.|..h...h...h.h.h.|"
           "o.h...h...h...h.|..h...h...h...h.|..h...h...h...h.|..h...h.h.h.h...|")
    return s.form(["intro"], ["A", "B"])


# ---------------------------------------------------------------------------------------------------------- helpers

def stabs(*bars: str, rows: int = 16, every: int = 4, at: int = 2, length: int = 2) -> str:
    """Off-beat chords: each bar a chord, or two ("X Y": the second from the half bar), struck at row `at` of each
    `every` rows (the off-beats of a 4/4 bar in sixteenths)."""
    out = []
    for bar in bars:
        chords = bar.split()
        cells = []
        for k in range(0, rows, every):
            c = chords[min(len(chords) - 1, k * len(chords) // rows)]
            cells.append(f"r:{at} {c}:{length}" + (f" r:{every - at - length}" if every - at - length else ""))
        out.append(" ".join(cells) + " |")
    return " ".join(out)


# ---------------------------------------------------------------------------------------------------------- 2. overworld

@song
def overworld():
    """G major with mixolydian turns (F), 128 BPM (speed 6, tempo 128: 51.2 Hz ticks), 4/4. Intro 2 bars (the cherry
    motif whole, as a call: G A D E B), then A 8, A' 8, B 8, B' 8 bars looping (60 s). A: the walking theme, whose head
    is the motif turned back down (G A D, E D B) and sequenced a step up over C; off-beat chord stabs on pulse 2,
    walking bass in quarters, kick-hat-snare kept light. A': the theme with the echo on pulse 2 (75 %, a row
    behind) and a bVII bar (F)
    that turns to F# on the way home. B: E minor, lyrical long notes over held arpeggio chords, no snare, ends on B7.
    B': a deceptive turn into C, where the cherry motif comes back as in the title (C D G A E) with its harp, sequenced
    up a fourth over F, and a turnaround on D7 that walks back into the theme."""
    s = Song("overworld", tempo=128, speed=6, bar=16, key="G major (mixolydian)")
    s.inst("lead", Inst("p25", vol=46, decay=0.3, sustain=36, vib=12, vib_delay=0.25, vib_hz=5.5), 0)
    s.inst("stab", Inst("p50", vol=30, steps=(30, 22)), 1)
    s.inst("pad", Inst("p50", vol=24, steps=(24, 22, 20, 20, 18, 18, 16)), 1)
    s.inst("echo", Inst("p75", vol=20, decay=0.2, sustain=14), 1)
    s.inst("harp", Inst("p12", vol=26, decay=0.9, sustain=4), 1)
    s.inst("bass", Inst("wa", vol=54, gate=0.75), 2)
    s.inst("bass_long", Inst("wa", vol=54, gate=0.9), 2)
    s.drums(h=("hat", 12), s=("snare", 22), k=("kick", 34), c=("crash", 26), o=("ohat", 16))
    G, C, D, Am7, D7, F, Em = "B3+D4+G4", "C4+E4+G4", "A3+D4+F#4", "A3+C4+G4", "A3+C4+F#4", "A3+C4+F4", "B3+E4+G4"
    beat = "k.h.s.h.k.h.s.h.|"
    s.part("intro", 2,
           "G4:2 A4:2 D5:4 E5:2 B5:6 | -:8 A5:2 G5:2 F#5:2 D5:2 |",
           "@pad B3+D4+G4:16 | A3+D4+F#4:16 |",
           "G2:4 D3:4 G2:4 B2:4 | D3:4 A2:4 F#2:4 D2:4 |",
           "c.......h.h.h.h.|k.h.s.h.k.h.s.ss|")
    s.part("A", 8,
           "G4:2 A4:2 D5:4 E5:2 D5:2 B4:4 | C5:2 D5:2 E5:4 D5:2 C5:2 A4:4 | B4:2 C5:2 D5:4 G5:4 F#5:2 E5:2 |"
           "D5:12 r:2 D4:2 | G4:2 A4:2 D5:4 E5:2 D5:2 B4:4 | C5:2 D5:2 E5:4 D5:2 C5:2 A4:4 |"
           "E5:2 D5:2 C5:2 A4:2 D5:2 C5:2 B4:2 A4:2 | G4:12 r:4 |",
           "@stab " + stabs(G, C, f"{G} {C}", D, G, C, f"{Am7} {D7}", G),
           "G2:4 B2:4 D3:4 B2:4 | C3:4 G2:4 A2:4 A#2:4 | B2:4 D3:4 C3:4 E3:4 | D3:4 A2:4 F#2:4 A2:4 |"
           "G2:4 B2:4 D3:4 B2:4 | C3:4 E3:4 G2:4 B2:4 | A2:4 C3:4 D3:4 F#2:4 | G2:4 D3:4 G2:4 D2:4 |",
           "c.h.s.h.k.h.s.h.|" + beat * 6 + "k.h.s.h.k.h.s.hh|")
    s.part("A2", 8,
           "G4:2 A4:2 D5:4 E5:2 D5:2 B4:4 | C5:2 D5:2 E5:4 D5:2 C5:2 A4:4 | A4:2 C5:2 F5:4 E5:2 D5:2 C5:4 |"
           "E5:4 G5:4 F#5:8 | G5:2 F#5:2 D5:4 E5:2 D5:2 B4:4 | C5:2 B4:2 A4:2 B4:2 C5:2 E5:2 G5:4 |"
           "E5:2 D5:2 C5:2 A4:2 F#5:2 E5:2 D5:2 C5:2 | B4:2 A4:2 G4:12 |",
           Echo(0, 1, 0, "echo"),
           "G2:4 B2:4 D3:4 B2:4 | C3:4 G2:4 A2:4 B2:4 | C3:4 A2:4 F2:4 A2:4 | C3:4 E3:4 D3:4 F#2:4 |"
           "G2:4 B2:4 D3:4 B2:4 | C3:4 G2:4 A2:4 A#2:4 | A2:4 C3:4 D3:4 F#2:4 | G2:4 D3:4 G2:4 B2:4 |",
           beat * 7 + "k.h.s.h.k.hss.s.|")
    s.part("B", 8,
           "E5:6 F#5:2 G5:4 B5:4 | A5:6 G5:2 E5:8 | F#5:6 G5:2 A5:4 D5:4 | G5:6 F#5:2 D5:8 |"
           "E5:6 F#5:2 G5:4 B5:4 | A5:6 G5:2 E5:4 C5:4 | A4:4 C5:4 E5:4 G5:4 | F#5:8 D#5:4 B4:4 |",
           "@pad E4+G4+B4:16 | E4+G4+C5:16 | D4+F#4+A4:16 | D4+G4+B4:16 | E4+G4+B4:16 | E4+G4+C5:16 |"
           "C4+E4+A4:16 | B3+D#4+A4:16 |",
           "@bass_long E2:8 B2:8 | C3:8 G2:8 | D3:8 A2:8 | G2:8 B2:8 | E2:8 B2:8 | C3:8 E3:8 | A2:8 E2:8 |"
           "B2:8 A2:4 B2:4 |",
           "k.h...h.k.h...h.|" * 7 + "k.h.s.h.s.h.sss.|")
    s.part("B2", 8,
           "C4:2 D4:2 G4:4 A4:2 E5:6 | -:6 D5:2 C5:4 B4:4 | F4:2 G4:2 C5:4 D5:2 A5:6 | -:6 G5:2 E5:4 C5:4 |"
           "B4:4 E5:4 G5:4 B5:4 | G5:8 E5:4 C5:4 | A4:2 B4:2 C5:4 E5:2 D5:2 C5:4 | F#5:4 E5:2 D5:2 C5:2 B4:2 A4:4 |",
           "@harp C4:2 E4:2 G4:2 C5:2 E5:2 C5:2 G4:2 E4:2 | A3:2 C4:2 E4:2 A4:2 C5:2 A4:2 E4:2 C4:2 |"
           "F3:2 C4:2 F4:2 A4:2 C5:2 A4:2 F4:2 C4:2 | G3:2 C4:2 E4:2 G4:2 C5:2 G4:2 E4:2 C4:2 |"
           "E3:2 B3:2 E4:2 G4:2 B4:2 G4:2 E4:2 B3:2 | C4:2 E4:2 G4:2 C5:2 E5:2 C5:2 G4:2 E4:2 |"
           "A3:2 E4:2 G4:2 C5:2 E5:2 C5:2 G4:2 E4:2 | D4:2 F#4:2 A4:2 C5:2 D5:2 C5:2 A4:2 F#4:2 |",
           "@bass_long C3:8 G2:8 | A2:8 E2:8 | F2:8 C3:8 | G2:4 A2:4 C3:4 D3:4 | E3:8 B2:8 | C3:8 G2:8 | A2:8 E2:8 |"
           "@bass D3:4 C3:4 A2:4 F#2:4 |",
           "c.h.s.h.k.h.s.h.|" + beat * 5 + "k.h.s.h.k.hss.ss|s.s.s.s.ssssssss|")
    return s.form(["intro"], ["A", "A2", "B", "B2"])


# ---------------------------------------------------------------------------------------------------------- 3. village

@song
def village():
    """F major, a waltz: 3/4 at 144 BPM (speed 6, tempo 144: 57.6 Hz ticks). Intro 2 bars (the pah-pah alone), then A 8,
    A' 8, B 8, A'' 8 and a 4-bar tag, looping (45 s). A: a lilting tune (long-short-long: C— D C | F— E D | D— C Bb),
    plucked 12.5 % arpeggio chords on beats 2 and 3, the wave bass on beat 1. A': it turns through F7 to Bb and ends low.
    B, the middle: pulse 1 rests and the wave sings instead (wave_b, the thin reedy wave, held level with a vibrato as
    the console's wave channel would): the cherry motif (F G C D A) over Bbmaj7, tender as in the title's first half,
    its answer falling (over Dm/A) into the tune's own D— C Bb, then the motif again over F, hopeful; pulse 2 alone
    keeps the waltz, its own bass note on beat 1 (50 %) and the chord on 2 and 3. A'': the tune back on pulse 1,
    reaching A5 for its last phrase, soft woodblock ticks. Tag: the motif's first four notes alone, unanswered, walking
    back to the start."""
    s = Song("village", tempo=144, speed=6, bar=12, pattern=48, key="F major", meter="3/4")
    s.inst("lead", Inst("p50", vol=42, decay=0.2, sustain=32, vib=12, vib_delay=0.3, vib_hz=5), 0)
    s.inst("pluck", Inst("p12", vol=28, steps=(28, 18, 12, 8)), 1)
    s.inst("bass", Inst("wa", vol=54, gate=0.85), 2)
    s.inst("reed", Inst("wb", vol=46, vib=12, vib_delay=0.3, vib_hz=5))
    s.inst("oom", Inst("p50", vol=34, gate=0.75))
    s.drums(h=("hat", 8), t=("tick", 12))
    F, Dm, Bb, C7, Gm, F7, Bbmaj7, C7sus = ("A3+C4+F4", "A3+D4+F4", "Bb3+D4+F4", "G3+Bb3+E4", "G3+Bb3+D4",
                                            "A3+C4+Eb4", "Bb3+D4+A4", "C4+F4+Bb4")
    s.part("intro", 2, "", waltz(F, C7), "F2:12 | C3:12 |")
    s.part("A", 8,
           "C5:6 D5:2 C5:4 | F5:6 E5:2 D5:4 | D5:6 C5:2 Bb4:4 | A4:4 G4:4 C5:4 |"
           "C5:6 D5:2 C5:4 | F5:6 E5:2 D5:4 | G5:6 F5:2 E5:4 | F5:12 |",
           waltz(F, Dm, Bb, C7, F, Dm, f"{Gm} {C7}", F),
           "F2:12 | D2:12 | Bb2:12 | C3:8 E2:4 | F2:12 | D2:12 | G2:8 C3:4 | F2:8 C3:4 |")
    s.part("A2", 8,
           "C5:6 D5:2 C5:4 | F5:6 E5:2 D5:4 | D5:6 C5:2 Bb4:4 | A4:4 G4:4 C5:4 |"
           "C5:6 D5:2 Eb5:4 | D5:6 C5:2 Bb4:4 | A4:6 Bb4:2 G4:4 | F4:12 |",
           waltz(F, Dm, Bb, C7, F7, Bb, f"{F} {C7}", F),
           "F2:12 | D2:12 | Bb2:12 | C3:8 E2:4 | F2:8 A2:4 | Bb2:12 | C3:12 | F2:8 A2:4 |",
           "....h...h...|" * 8)
    def oompah(*bars: str) -> str:  # pulse 2 alone: its bass note on beat 1, the chord on 2 and 3
        return " ".join(f"@oom {b.split()[0]}:4 @pluck {b.split()[1]}:4 {b.split()[-1]}:4 |" for b in bars)
    s.part("B", 8, "",
           oompah(f"Bb2 {Bbmaj7}", f"A2 {Dm}", f"G2 {Gm}", f"C3 {C7sus} {C7}", f"F2 {F}", f"D2 {Dm}",
                  f"G2 {Gm} {C7}", f"F2 {F}"),
           "@reed F4:2 G4:2 C5:4 D5:2 A5:2 | -:6 G5:2 F5:2 E5:2 | D5:6 C5:2 Bb4:4 | F5:8 E5:4 |"
           "F4:2 G4:2 C5:4 D5:2 A5:2 | -:6 Bb5:2 A5:2 F5:2 | G5:6 F5:2 E5:4 | F5:8 r:4 |")
    s.part("A3", 8,
           "C5:6 D5:2 C5:4 | F5:6 E5:2 D5:4 | D5:6 C5:2 Bb4:4 | A4:4 G4:4 C5:4 |"
           "C5:6 D5:2 C5:4 | A5:6 G5:2 F5:4 | G5:6 F5:2 E5:4 | F5:12 |",
           waltz(F, Dm, Bb, C7, F, Dm, f"{Gm} {C7}", F),
           "F2:12 | D2:12 | Bb2:12 | C3:8 E2:4 | F2:12 | D2:12 | G2:8 C3:4 | F2:12 |",
           "....t...t...|" * 7 + "....t...t.t.|")
    s.part("tag", 4,
           "F4:2 G4:2 C5:4 D5:4 | C5:12 | Bb4:6 A4:2 G4:4 | G4:4 A4:4 Bb4:4 |",
           waltz(Bb, F, Gm, C7),
           "Bb2:12 | A2:12 | G2:12 | C3:8 E2:4 |")
    return s.form(["intro"], ["A", "A2", "B", "A3", "tag"])


# ---------------------------------------------------------------------------------------------------------- 4. beach

@song
def beach():
    """A major, 96 BPM swung (6 rows a beat, eighths long-short 4+2; speed 6, tempo 144: 57.6 Hz ticks), 4/4. Intro 2
    bars (the rolling bass and the skank), then A 8 and B 8 bars looping (40 s). A: a lazy, breezy tune of long notes
    (E— C# A | F#— E C# | B C# E C# B A | B———) over Amaj7 and Dmaj7, a 12.5 % skank on every swung off-beat, and the
    bass rolling up and down each bar like a swell (root, fifth, third); a one-drop beat (the kick on 3) with ticks.
    B: the skank stops and the tune floats down a sequence (A F# E | G# E C# | F# D B | E C#) with a long echo on pulse 2
    (three rows later), the bass in slow half notes; an open hat like a wave every two bars."""
    s = Song("beach", tempo=144, speed=6, bar=24, beat=6, pattern=48, key="A major")
    s.inst("lead", Inst("p50", vol=42, decay=0.15, sustain=34, vib=16, vib_delay=0.3, vib_hz=4.5), 0)
    s.inst("skank", Inst("p12", vol=26, steps=(26, 14)), 1)
    s.inst("echo", Inst("p50", vol=18, decay=0.1, sustain=12, vib=10, vib_delay=0.4, vib_hz=4.5), 1)
    s.inst("bass", Inst("wa", vol=54, gate=0.9), 2)
    s.drums(h=("hat", 10), t=("tick", 14), k=("kick", 30), o=("ohat", 14))
    A, D, E7s, E7, Bm7 = "A3+C#4+E4", "A3+D4+F#4", "A3+B3+E4", "G#3+B3+D4", "A3+B3+D4"

    def sk(*bars):
        return stabs(*bars, rows=24, every=6, at=4, length=2)
    groove = "h...t.h...t.k...t.h...t.|"
    s.part("intro", 2, "", "@skank " + sk(A, f"{E7s} {E7}"),
           "A2:12 E3:6 C#3:6 | E2:12 B2:6 G#2:6 |", "o...t.h...t.k...t.h...t.|h...t.h...t.k...t.h.t.t.|")
    s.part("A", 8,
           "E5:12 C#5:6 A4:6 | F#5:12 E5:6 C#5:6 | B4:4 C#5:2 E5:4 C#5:2 B4:6 A4:6 | B4:18 r:6 |"
           "E5:12 C#5:6 A4:6 | F#5:12 A5:6 F#5:6 | E5:4 F#5:2 E5:4 D5:2 C#5:6 B4:6 | A4:18 r:6 |",
           "@skank " + sk(A, D, A, f"{E7s} {E7}", A, D, f"{Bm7} {E7}", A),
           "A2:12 E3:6 C#3:6 | D3:12 A2:6 F#2:6 | A2:12 E3:6 C#3:6 | E2:12 B2:6 G#2:6 |"
           "A2:12 E3:6 C#3:6 | D3:12 A2:6 F#2:6 | B2:12 E2:12 | A2:12 E2:6 G#2:6 |",
           "o...t.h...t.k...t.h...t.|" + groove * 6 + "h...t.h...t.k...t.h.t.t.|")
    s.part("B", 8,
           "A5:12 F#5:6 E5:6 | G#5:12 E5:6 C#5:6 | F#5:12 D5:6 B4:6 | E5:18 C#5:6 |"
           "A5:6 B5:6 A5:6 F#5:6 | G#5:12 E5:6 C#5:6 | F#5:6 E5:6 D5:6 C#5:6 | B4:12 D5:6 E5:6 |",
           Echo(0, 3, 0, "echo"),
           "D3:12 A2:12 | C#3:12 G#2:12 | B2:12 F#2:12 | A2:12 E2:12 | D3:12 A2:12 | C#3:12 G#2:12 |"
           "B2:12 F#2:12 | E2:12 E3:6 D3:6 |",
           ("o...t.....t.k...t.....t.|" + "h...t.....t.k...t.....t.|") * 3
           + "o...t.....t.k...t.....t.|h...t.h...t.k...t.h.t.t.|")
    return s.form(["intro"], ["A", "B"])


# ---------------------------------------------------------------------------------------------------------- 5. forest

@song
def forest():
    """E dorian (E minor with C#), 84 BPM (speed 9, tempo 126: 50.4 Hz ticks), 4/4. Intro 2 bars (the pedal and the
    wind), then A 8 and B 8 bars looping (45.7 s). Sparse 50 % notes with breaths between them, each answered two rows
    later by a ghostly 25 % echo; the wave holds an E pedal, struck again each bar like a slow pulse. A stays in the
    mode (the dorian C# over A/E is its colour); B leaves it: a bVI (Cmaj7, the tune reaching B5), D, a phrygian F over
    the E pedal (the chill of the piece) and B7 home. Noise: twig ticks and wind (open hats); a soft heartbeat in B."""
    s = Song("forest", tempo=126, speed=9, bar=16, key="E dorian")
    s.inst("lead", Inst("p50", vol=40, decay=0.2, sustain=30, vib=15, vib_delay=0.4, vib_hz=4.5), 0)
    s.inst("echo", Inst("p25", vol=16, decay=0.15, sustain=10), 1)
    s.inst("bass", Inst("wa", vol=50, gate=0.95, shift=-1), 2)
    s.drums(t=("tick", 10), o=("ohat", 9), k=("kick", 22))
    s.part("intro", 2, "", "", "E2:14 r:2 | E2:14 r:2 |", "o...............|........t.......|")
    s.part("A", 8,
           "E5:6 F#5:2 G5:6 r:2 | F#5:4 E5:4 C#5:6 r:2 | B4:6 C#5:2 D5:4 E5:4 | F#5:4 D5:4 A4:6 r:2 |"
           "E5:6 F#5:2 G5:6 r:2 | A5:4 G5:4 F#5:4 E5:4 | D5:6 E5:2 B4:6 r:2 | E5:12 r:4 |",
           Echo(0, 2, 0, "echo"),
           "E2:14 r:2 | E2:14 r:2 | E2:14 r:2 | E2:14 r:2 | E2:14 r:2 | E2:14 r:2 | E2:14 r:2 | E2:14 r:2 |",
           "o...............|........t.......|...............t|....t...........|"
           "o...............|........t.......|......t.........|....t.......t...|")
    s.part("B", 8,
           "E5:4 G5:4 B5:6 r:2 | A5:4 G5:4 E5:6 r:2 | D5:4 F#5:4 A5:6 r:2 | G5:4 F#5:4 D5:6 r:2 |"
           "B4:4 E5:4 G5:6 r:2 | F5:4 E5:4 C5:6 r:2 | E5:4 F#5:4 G5:4 A5:4 | B5:8 A5:4 F#5:2 D#5:2 |",
           Echo(0, 2, 0, "echo"),
           "C2:14 r:2 | C2:14 r:2 | D2:14 r:2 | D2:14 r:2 | E2:14 r:2 | E2:14 r:2 | E2:14 r:2 | B2:14 r:2 |",
           "k..k............|k..k....t.......|k..k............|k..k.........t..|"
           "k..k............|k..k....t.......|k..k......t.....|k..k....k..k....|")
    return s.form(["intro"], ["A", "B"])


# ---------------------------------------------------------------------------------------------------------- 6. raiz

@song
def raiz():
    """A minor, 80 BPM (speed 9, tempo 120: 48 Hz ticks), 4/4. Intro 2 bars (the pulse and the first drops), then A 8,
    B 8, C 4 bars looping (60 s). The wave is a tense pedal on A pulsing in staccato eighths, a heartbeat kick under
    it. Pulse 1 is water dripping: high 12.5 % drops (A minor pentatonic, E6 to A6), each with its own echo (the same
    note twice more, quieter, an eighth apart), at uneven places. Pulse 2 creeps chromatically, a note a bar: down from
    E4 to A3 over the pedal in A (5, #4, 4, 3, b3, 2, b2, 1), and back up in B, where the pedal moves to F and then E
    (VI-V, the Andalusian pull) under a low 25 % dirge in harmonic minor and a slow kick-snare march. C: the drops come
    back faster over the pedal while pulse 2 sighs F-E (b6-5)."""
    s = Song("raiz", tempo=120, speed=9, bar=16, key="A minor")
    s.inst("drip", Inst("p12", vol=36, decay=3, sustain=0), 0)
    s.inst("dirge", Inst("p25", vol=38, decay=0.2, sustain=30, vib=10, vib_delay=0.4, vib_hz=4.5), 0)
    s.inst("line", Inst("p50", vol=22, decay=0.05, sustain=18, vib=8, vib_delay=0.5, vib_hz=3.5), 1)
    s.inst("pulse", Inst("wa", vol=50, gate=0.45, shift=-1), 2)
    s.drums(k=("kick", 26), s=("snare", 18), t=("tick", 8))

    def drop(note: str) -> str:  # a drop and its echo: six rows
        return f"v36 {note}:2 v14 {note}:2 v6 {note}:2 v"

    def pedal(note: str, bars: int, last: str = "") -> str:
        bar = f"{note}:2 " * 8
        return ("| ".join([bar] * (bars - 1) + [last or bar])) + "|"
    s.part("intro", 2, f"r:4 {drop('E6')} r:6 | r:2 {drop('A6')} r:8 |", "", pedal("A2", 2),
           "k...............|k.......t.......|")
    s.part("A", 8,
           f"r:4 {drop('E6')} r:6 | r:10 {drop('C6')} | {drop('A6')} r:4 {drop('E6')} | r:8 {drop('G6')} r:2 |"
           f"r:2 {drop('D6')} r:8 | r:6 {drop('A6')} r:4 | {drop('E6')} r:10 | r:4 {drop('C6')} {drop('B5')} |",
           "@line E4:16 | D#4:16 | D4:16 | C#4:16 | C4:16 | B3:16 | Bb3:16 | A3:16 |",
           pedal("A2", 4, "A2:2 " * 6 + "E2:2 E2:2 ") + " " + pedal("A2", 4, "A2:2 " * 6 + "E2:2 E2:2 "),
           "k...............|k.........t.....|k...............|k...t...........|"
           "k...............|k.......t.......|k...........t...|k.......k.......|")
    s.part("B", 8,
           "@dirge A4:4 C5:4 B4:4 A4:4 | F5:8 E5:4 C5:4 | D5:6 C5:2 B4:8 | C5:16 |"
           "B4:4 G#4:4 A4:4 B4:4 | C5:8 B4:4 G#4:4 | A4:4 B4:4 C5:4 B4:4 | E5:8 D5:4 B4:4 |",
           "@line A3:16 | Bb3:16 | B3:16 | C4:16 | C#4:16 | D4:16 | D#4:16 | E4:16 |",
           pedal("F2", 4) + " " + pedal("E2", 4),
           "k.......s.......|" * 7 + "k.......s...s.s.|")
    s.part("C", 4,
           f"{drop('E6')} r:4 {drop('A6')} | r:4 {drop('G6')} {drop('E6')} | {drop('C6')} r:4 {drop('D6')} |"
           f"r:2 {drop('A5')} r:2 {drop('E6')} |",
           "@line F4:16 | E4:16 | F4:16 | E4:16 |",
           pedal("A2", 4),
           "k...............|k.....t.........|k...............|k.......k...k...|")
    return s.form(["intro"], ["A", "B", "C"])


# ---------------------------------------------------------------------------------------------------------- 7. boss

@song
def boss():
    """D minor (harmonic: C#), 168 BPM (speed 6, tempo 168: 67.2 Hz ticks), 4/4. Intro 2 bars (the riff and the
    drums, the ostinato joining), then A 8, B 8, A 8, C 8 bars looping (45.7 s), no bar of rest anywhere. The wave
    (the saw, wave_b) gallops a menacing pedal riff, D-D-D then D3 F3 E3 stabbing over it (C3, then Bb2 falling to A2 on the
    second bar: b6 to 5); pulse 2 runs a sixteenth-note broken-chord ostinato as in the Game Boy's
    battle themes; the 25 % lead is urgent (D—— F E D C# D | A—— D F A | ...), the drums drive kick-snare with
    off-beat kicks. A ends on A7 and B turns deceptively to Bb: long held lead notes over eighth-note arpeggio chords
    and a straight pedal climbing Bb, C, D. C is the frenzy: sixteenth runs sequenced down the progression, a crash on
    its first bar and a snare fill that falls straight back into the riff."""
    s = Song("boss", tempo=168, speed=6, bar=16, key="D minor")
    s.inst("lead", Inst("p25", vol=48, decay=0.3, sustain=40, vib=12, vib_delay=0.2, vib_hz=6), 0)
    s.inst("ost", Inst("p12", vol=22, decay=2.5, sustain=0), 1)
    s.inst("chord", Inst("p50", vol=28, steps=(28, 20)), 1)
    s.inst("bass", Inst("wb", vol=48, gate=0.7), 2)
    s.drums(h=("hat", 14), s=("snare", 30), k=("kick", 40), c=("crash", 26))

    def ost(*bars: str) -> str:  # each bar: a four-note cell four times (or two cells, a half bar each)
        out = []
        for bar in bars:
            cells = bar.split("/")
            out.append(" ".join(" ".join(f"{n}:1" for n in cells[min(len(cells) - 1, k // 2)].split()) for k in range(4)) + " |")
        return " ".join(out)
    dm, bb, a, gm, c = "D4 A4 F4 A4", "Bb3 F4 D4 F4", "A3 E4 C#4 E4", "G3 D4 Bb3 D4", "C4 G4 E4 G4"
    riff1 = "D2:2 D2:1 D2:1 D3:2 D2:2 F3:2 D2:2 E3:2 D2:2 |"
    riff2 = "D2:2 D2:1 D2:1 D3:2 D2:2 C3:2 D2:2 Bb2:2 A2:2 |"
    rbb = "Bb1:2 Bb1:1 Bb1:1 Bb2:2 Bb1:2 D3:2 Bb1:2 C3:2 Bb1:2 |"
    ra = "A1:2 A1:1 A1:1 A2:2 A1:2 C#3:2 A1:2 E3:2 A1:2 |"
    beat, fill = "k.h.s.hkk.h.s.h.|", "k.h.s.hkk.s.ssss|"
    s.part("intro", 2, "", "r:16 | " + ost(dm), riff1 + riff2, "c.h.s.hkk.h.s.h.|" + fill)
    s.part("A", 8,
           "D5:6 F5:2 E5:2 D5:2 C#5:2 D5:2 | A4:6 D5:2 F5:4 A5:4 | G5:6 F5:2 E5:2 F5:2 G5:2 A5:2 | E5:8 C#5:4 A4:4 |"
           "D5:6 F5:2 E5:2 D5:2 C#5:2 D5:2 | A5:6 Bb5:2 A5:4 F5:4 | G5:4 Bb5:4 A5:4 G5:4 |"
           "E5:2 F5:2 E5:2 D5:2 C#5:4 A4:4 |",
           ost(dm, dm, bb, a, dm, dm, f"{bb}/{gm}", a),
           riff1 + riff2 + rbb + ra + riff1 + riff2 + rbb + ra,
           "c.h.s.hkk.h.s.h.|" + beat * 6 + fill)
    s.part("B", 8,
           "F5:12 D5:4 | E5:12 G5:4 | A5:16 | A5:4 G5:4 F5:4 E5:4 | D5:12 F5:4 | E5:8 G5:8 | C#5:8 E5:8 |"
           "G5:8 E5:4 C#5:4 |",
           "@chord " + " ".join(f"{x}:2 " * 8 + "|" for x in ("Bb3+D4+F4", "C4+E4+G4", "D4+F4+A4", "D4+F4+A4",
                                                             "Bb3+D4+F4", "C4+E4+G4", "C#4+E4+A4", "C#4+E4+G4")),
           "Bb1:2 " * 8 + "| " + "C2:2 " * 8 + "| " + ("D2:2 " * 8 + "| ") * 2 + "Bb1:2 " * 8 + "| " + "C2:2 " * 8
           + "| " + ("A1:2 " * 8 + "| ") * 2,
           "k.hhs.hhk.hhs.hh|" * 7 + "k.hhs.hhs.s.ssss|")
    s.part("C", 8,
           "D5:1 E5:1 F5:1 G5:1 A5:2 F5:2 D5:2 A4:2 D5:4 | C#5:1 D5:1 E5:1 F5:1 G5:2 E5:2 C#5:2 A4:2 C#5:4 |"
           "Bb4:1 C5:1 D5:1 E5:1 F5:2 D5:2 Bb4:2 F4:2 Bb4:4 | A4:1 B4:1 C#5:1 D5:1 E5:2 C#5:2 A4:2 E4:2 A4:4 |"
           "D5:2 F5:2 A5:4 G5:2 F5:2 E5:4 | F5:2 D5:2 Bb4:4 C5:2 D5:2 E5:4 | C#5:4 E5:4 A5:4 G5:4 |"
           "F5:2 E5:2 D5:2 C#5:2 E5:2 D5:2 C#5:2 A4:2 |",
           ost(dm, a, bb, a, dm, bb, a, a),
           riff1 + ra + rbb + ra + riff1 + rbb + ra + ra,
           "c.h.s.hkk.h.s.h.|" + beat * 5 + "k.h.s.hkk.hss.ss|s.s.s.ssssssssss|")
    return s.form(["intro"], ["A", "B", "A", "C"])


# ---------------------------------------------------------------------------------------------------------- 8. house

@song
def house():
    """G major, a lullaby in 6/8 at 60 BPM a dotted quarter (2 rows an eighth; speed 9, tempo 135: 54 Hz ticks).
    Intro 1 bar (the music box), then A 4, A' 4, B 4, A'' 4 bars looping (32 s). A soft 50 % voice sings a rocking
    tune (B—A G—B | C—B A—— | A—G F#—A | G———) over a 12.5 % music box of broken chords in eighths and a triangle
    bass a bar long; A' climbs to E5, B rises a step at a time (D E D B | C D C A | B C B G) to a half cadence on D, A''
    comes home. A clock ticks very softly on each dotted quarter."""
    s = Song("house", tempo=135, speed=9, bar=12, beat=6, pattern=48, key="G major", meter="6/8")
    s.inst("voice", Inst("p50", vol=38, decay=0.15, sustain=30, vib=12, vib_delay=0.4, vib_hz=4.5), 0)
    s.inst("box", Inst("p12", vol=24, decay=1.2, sustain=4), 1)
    s.inst("bass", Inst("tri", vol=64, gate=0.9), 2)
    s.drums(t=("tick", 6))
    g, c, d7, em, am7_d7, gd = ("G3 B3 D4 G4 D4 B3", "C4 E4 G4 C5 G4 E4", "D4 F#4 A4 C5 A4 F#4", "E3 G3 B3 E4 B3 G3",
                                "A3 C4 E4 D4 F#4 A4", "D4 G4 B4 D4 F#4 C5")
    am = "A3 C4 E4 A4 E4 C4"

    def box(*bars: str) -> str:
        return " ".join(" ".join(f"{n}:2" for n in b.split()) + " |" for b in bars)
    clock = "t.....t.....|"
    s.part("intro", 1, "", box(g), "G2:12 |", clock)
    s.part("A", 4, "B4:4 A4:2 G4:4 B4:2 | C5:4 B4:2 A4:6 | A4:4 G4:2 F#4:4 A4:2 | G4:12 |",
           box(g, c, d7, g), "G2:12 | C3:12 | D3:12 | G2:12 |", clock * 4)
    s.part("A2", 4, "B4:4 C5:2 D5:4 B4:2 | E5:4 D5:2 B4:6 | C5:4 B4:2 A4:4 F#4:2 | G4:12 |",
           box(g, em, am7_d7, g), "G2:12 | E2:12 | A2:6 D3:6 | G2:12 |", clock * 4)
    s.part("B", 4, "D5:4 E5:2 D5:4 B4:2 | C5:4 D5:2 C5:4 A4:2 | B4:4 C5:2 B4:4 G4:2 | A4:12 |",
           box(g, am, em, d7), "G2:12 | A2:12 | E2:12 | D3:12 |", clock * 4)
    s.part("A3", 4, "B4:4 A4:2 G4:4 B4:2 | C5:4 B4:2 A4:4 C5:2 | B4:4 A4:2 G4:4 F#4:2 | G4:12 |",
           box(g, c, gd, g), "G2:12 | C3:12 | D3:12 | G2:12 |", clock * 4)
    return s.form(["intro"], ["A", "A2", "B", "A3"])


# ---------------------------------------------------------------------------------------------------------- 9. shop

@song
def shop():
    """C major, ragtime-ish, 96 BPM (speed 9, tempo 144: 57.6 Hz ticks), 4/4. Intro 1 bar (an oom-pah vamp on G7 and
    a pickup), then one 8-bar strain looping (20 s). The same syncopated cell (short-long-short, a chromatic step
    in it) climbs the ragtime circle C, A7, D7, G7 and comes back over C7, F to G7 with a flat nine, and a pickup that
    runs into the top again. Oom-pah: the wave on beats 1 and 3, pulse 2's chords stabbed on 2 and 4, a woodblock
    tick with them. The 25 % lead is a little detached, bouncy."""
    s = Song("shop", tempo=144, speed=9, bar=16, key="C major")
    s.inst("lead", Inst("p25", vol=44, decay=0.4, sustain=32, vib=10, vib_delay=0.35, vib_hz=5.5, gate=0.85), 0)
    s.inst("pah", Inst("p50", vol=26, steps=(26, 16)), 1)
    s.inst("oom", Inst("wa", vol=54, gate=0.6, shift=-1), 2)
    s.drums(t=("tick", 14), h=("hat", 8))
    C, A7, D7, G7, C7, F, G7b9 = ("E4+G4+C5", "E4+G4+C#5", "F#4+A4+C5", "D4+F4+B4", "E4+G4+Bb4", "F4+A4+C5",
                                   "F4+Ab4+B4")

    def pah(*bars: str) -> str:
        out = []
        for bar in bars:
            x = bar.split()
            out.append(f"r:4 {x[0]}:2 r:2 r:4 {x[-1]}:2 r:2 |")
        return " ".join(out)
    ticks = "....t.h.....t.h.|"
    s.part("intro", 1, "r:8 G4:2 A4:1 B4:1 D5:4* |", pah(G7), "G2:4 r:4 D3:4 r:4 |", ticks)
    s.part("A", 8,
           "E5:2 G5:1 E5:3 C5:2 D5:1 D#5:1 E5:2 G4:4 | A4:2 C#5:1 E5:3 G5:2 F5:1 E5:1 D5:2 C#5:4 |"
           "D5:2 F#5:1 A5:3 F#5:2 E5:1 D5:1 C5:2 A4:4 | G4:2 B4:1 D5:3 F5:2 E5:1 D5:1 B4:2 G4:4 |"
           "E5:2 G5:1 E5:3 C5:2 D5:1 D#5:1 E5:2 G4:4 | C5:2 E5:1 G5:3 Bb5:2 A5:1 G5:1 E5:2 C5:4 |"
           "A5:2 F5:1 C5:3 Ab5:2 F5:1 C5:1 D5:2 B4:4 | C5:4 r:4 G4:2 A4:1 B4:1 D5:4* |",
           pah(C, A7, D7, G7, C, C7, f"{F} {G7b9}", f"{C} {G7}"),
           "C3:4 r:4 G2:4 r:4 | A2:4 r:4 E2:4 r:4 | D3:4 r:4 A2:4 r:4 | G2:4 r:4 D3:4 r:4 |"
           "C3:4 r:4 G2:4 r:4 | C3:4 r:4 E2:4 r:4 | F2:4 r:4 G2:4 r:4 | C3:4 r:4 G2:4 r:4 |",
           ticks * 7 + "....t.h.t.t.t.h.|")
    return s.form(["intro"], ["A"])


# ---------------------------------------------------------------------------------------------------------- 10. intro

@song
def intro():
    """D major, slow: 64 BPM (speed 12, tempo 128: 51.2 Hz ticks), 4/4. Intro 1 bar (the sea alone), then 8 bars
    looping (30 s). Waves and wind on the noise (a soft crash where a wave breaks, open hats for the gusts, two bars
    apart); the wave channel sings a slow line (D, C#, B, A, G, F#, E, A) that glides into its notes; one lonely
    12.5 % pulse high above (A5, F#5, E5 D5 ...) with a faint echo far behind it. At the end it plays the cherry tree's
    motif without its last note, D E A B, and holds the B over an open A (sus2 and sus4): a question, the tree not yet
    in flower. It goes round to D again."""
    s = Song("intro", tempo=128, speed=12, bar=16, key="D major")
    s.inst("lone", Inst("p12", vol=32, decay=0.1, sustain=26, vib=14, vib_delay=0.5, vib_hz=4.5), 0)
    s.inst("far", Inst("p12", vol=11, decay=0.05, sustain=8), 1)
    s.inst("swell", Inst("wa", vol=44, gate=0.98, shift=-1), 2)
    s.drums(c=("crash", 9), o=("ohat", 5))
    sea = "c.......o.......|........o...o...|"
    s.part("intro", 1, "", "", "D3:16 |", "c.......o...o...|")
    s.part("A", 8,
           "r:8 A5:8 | -:8 F#5:4 E5:4 | F#5:16 | -:8 D5:4 E5:4 | F#5:8 E5:4 D5:4 | A5:16 | D5:2 E5:2 A5:4 B5:8 |"
           "-:16 |",
           Echo(0, 3, 0, "far"),
           "D3:16 | ^C#3:16 | ^B2:16 | ^A2:16 | ^G2:16 | ^F#2:16 | ^E2:16 | ^A2:16 |",
           sea * 4)
    return s.form(["intro"], ["A"])


# ---------------------------------------------------------------------------------------------------------- 11. ending

@song
def ending():
    """D major, then E major. 96 BPM (speed 9, tempo 144: 57.6 Hz ticks) slowing to 72 BPM (speed 12) for the close;
    4/4. Played once (43 s): a bloom (2 bars: the harp sweeping up over A7 and a snare roll), the title's hopeful half
    in full with the band (8 bars: the cherry motif D E A B F# and its sequence a fourth up, eighth-note chords, a
    walking bass, drums), C and D lifting it into E (bVI, bVII, I), the motif in E sequenced up to C#6 (4 bars), and
    one slower bar settling on E. Then the reflective close loops softly (8 bars, 27 s, 70 s with the first part):
    the title's tender half in E with its harp and no drums, now ending on E each time, the motif answered at last
    (the intro left it on a question)."""
    s = Song("ending", tempo=144, speed=9, bar=16, key="D major, then E")
    s.inst("lead", Inst("p25", vol=48, decay=0.25, sustain=38, vib=14, vib_delay=0.3, vib_hz=5), 0)
    s.inst("soft", Inst("p25", vol=34, decay=0.2, sustain=26, vib=14, vib_delay=0.4, vib_hz=4.5), 0)
    s.inst("arp", Inst("p50", vol=28, steps=(28, 20)), 1)
    s.inst("pad", Inst("p50", vol=26, steps=(26, 24, 22, 20, 18, 16, 14, 12)), 1)
    s.inst("harp", Inst("p12", vol=26, decay=0.8, sustain=4), 1)
    s.inst("bass", Inst("wa", vol=54, gate=0.8, shift=-1), 2)
    s.inst("bass_long", Inst("wa", vol=52, gate=0.95, shift=-1), 2)
    s.drums(s=("snare", 16), S=("snare", 30), C=("crash", 30), k=("kick", 36), h=("hat", 12))

    def eighths(*chords: str) -> str:  # each bar one chord, or two ("X Y": half a bar each), struck in eighths
        out = []
        for bar in chords:
            x = bar.split()
            out.append(" ".join(f"{x[min(len(x) - 1, k * len(x) // 8)]}:2" for k in range(8)) + " |")
        return "@arp " + " ".join(out)

    def harp(*bars: str) -> str:
        return "@harp " + " ".join(" ".join(f"{n}:2" for n in b.split()) + " |" for b in bars)
    beat = "k.h.s.h.k.h.s.h.|"
    sweep = " ".join(f"{n}:1" for n in "A3 C#4 E4 A4 C#5 E5 A5 E5 C#5 A4 E4 C#4 A3 C#4 E4 A4".split())
    sweep7 = " ".join(f"{n}:1" for n in "A3 C#4 E4 G4 C#5 E5 G5 E5 C#5 G4 E4 C#4 E4 G4 C#5 E5".split())
    s.part("bloom", 2, "", f"@harp {sweep} | {sweep7} |", "A2:16 | A2:8 E2:4 C#3:4 |",
           "s...s...s.s.s.ss|sSsSSSSSSSSSSSSS|")
    s.part("statement", 8,
           "D4:2 E4:2 A4:4 B4:2 F#5:6 | -:6 E5:2 C#5:4 A4:4 | G4:2 A4:2 D5:4 E5:2 B5:6 | -:6 A5:2 F#5:4 D5:4 |"
           "E5:6 F#5:2 G5:4 B5:4 | A5:8 F#5:4 D5:4 | E5:6 D5:2 C#5:4 E5:4 | D5:16 |",
           eighths("D4+F#4+A4", "C#4+E4+A4", "D4+G4+B4", "D4+F#4+A4", "E4+G4+D5", "D4+F#4+A4",
                   "E4+G4+B4 C#4+E4+G4", "D4+F#4+A4"),
           "D3:4 F#2:4 A2:4 D3:4 | C#3:4 A2:4 E2:4 A2:4 | G2:4 B2:4 D3:4 B2:4 | F#2:4 A2:4 D3:4 A2:4 |"
           "E2:4 G2:4 B2:4 D3:4 | A2:4 D3:4 F#2:4 A2:4 | E2:4 B2:4 A2:4 C#3:4 | D3:4 A2:4 F#2:4 D2:4 |",
           "C.h.s.h.k.h.s.h.|" + beat * 3 + "C.h.s.h.k.h.s.h.|" + beat * 2 + "k.h.s.h.k.hss.ss|")
    s.part("pivot", 2, "E5:16 | F#5:12 r:4 |", eighths("C4+E4+G4", "D4+F#4+A4"),
           "C3:4 G2:4 C3:4 E3:4 | D3:4 A2:4 D3:4 F#2:4 |", "C.h.s.h.k.h.s.h.|k.s.s.s.ssssSSSS|")
    s.part("climax", 4,
           "E4:2 F#4:2 B4:4 C#5:2 G#5:6 | -:6 F#5:2 D#5:4 B4:4 | A4:2 B4:2 E5:4 F#5:2 C#6:6 | -:6 B5:2 G#5:4 E5:4 |",
           eighths("E4+G#4+B4", "D#4+F#4+B4", "E4+A4+C#5", "E4+G#4+B4"),
           "E2:4 G#2:4 B2:4 E3:4 | D#3:4 B2:4 F#2:4 B2:4 | A2:4 C#3:4 E3:4 A2:4 | G#2:4 B2:4 E3:4 B2:4 |",
           "C.h.s.h.k.h.s.h.|" + beat + "C.h.s.h.k.h.s.h.|k.h.s.h.k.s.ssss|")
    s.part("settle", 1, "E5:16~", "@pad E4+G#4+B4:16", "@bass_long E2:16", "C...............|", speed=12)
    s.part("close", 8,
           "@soft E4:2 F#4:2 B4:4 C#5:2 G#5:6 | -:6 F#5:2 E5:4 D#5:4 | C#5:6 B4:2 A4:4 C#5:4 | E5:8 D#5:8 |"
           "E4:2 F#4:2 B4:4 C#5:2 G#5:6 | -:4 B5:4 A5:2 G#5:2 E5:4 | F#5:6 E5:2 D#5:4 F#5:4 | E5:16 |",
           harp("A3 E4 G#4 C#5 E5 C#5 G#4 E4", "G#3 D#4 F#4 B4 C#4 E4 G#4 B4", "F#3 C#4 E4 A4 C#5 A4 E4 C#4",
                "B3 E4 F#4 B4 B3 D#4 F#4 B4", "A3 E4 G#4 C#5 E5 C#5 G#4 E4", "C#4 E4 G#4 B4 E5 B4 G#4 E4",
                "F#3 C#4 E4 A4 B3 D#4 F#4 A4", "E4 G#4 B4 E5 G#5 E5 B4 G#4"),
           "@bass_long A2:16 | G#2:8 C#3:8 | F#2:16 | B2:8 B2:8 | A2:16 | C#3:16 | F#2:8 B2:8 | E2:16 |",
           "", speed=12)
    return s.form(["bloom", "statement", "pivot", "climax", "settle"], ["close"])


# ---------------------------------------------------------------------------------------------------------- 12. jingles
# They play once: after them a silent pattern loops on itself (Song(jingle=True) adds it).

def _fanfare(name: str, key: str, rows: int, tempo: int = 150, speed: int = 6) -> Song:
    """A jingle `rows` long (a tenth of a second a row at 150 and speed 6), written as one bar of that many rows."""
    s = Song(name, tempo=tempo, speed=speed, bar=rows, key=key, jingle=True)
    s.inst("lead", Inst("p25", vol=48, decay=0.3, sustain=36, vib=14, vib_delay=0.25, vib_hz=6), 0)
    s.inst("second", Inst("p50", vol=30, decay=0.3, sustain=22), 1)
    s.inst("arp", Inst("p50", vol=30, steps=(30, 28, 26, 24, 22, 20, 18, 16, 14, 12, 10, 8)), 1)
    s.inst("bass", Inst("wa", vol=52, gate=0.9, shift=-1), 2)
    s.drums(s=("snare", 22), S=("snare", 32), k=("kick", 38), c=("crash", 26), C=("crash", 34), o=("ohat", 14),
            t=("tick", 14))
    return s


@song
def jingle_item():
    """C major, 150 BPM (60 Hz ticks), 3 s: an item found. A quick call up the chord (C E G), A G, and a held C6 with
    vibrato over a shimmering C chord, the bass walking I IV V I under it; a crash where it lands."""
    s = _fanfare("jingle_item", "C major", 30)
    s.part("a", 1, "C5:1 E5:1 G5:1 r:1 A5:2 G5:2 C6:14 r:8 |",
           "E4:1 G4:1 C5:1 r:1 F5:2 E5:2 @arp E4+G4+C5:14 r:8 |",
           "C3:4 F2:2 G2:2 C3:14 r:8 |", "k...s.s.C.....................|")
    return s.form(["a"], [])


@song
def jingle_heart():
    """F major, 150 BPM, 2 s: a heart container. A warm run up the F chord to C6, held over its arpeggio."""
    s = _fanfare("jingle_heart", "F major", 20)
    s.part("a", 1, "A4:1 C5:1 F5:1 A5:1 C6:11 r:5 |", "r:4 @arp F4+A4+C5:11 r:5 |", "F2:4 C3:11 r:5 |",
           "t...c...............|")
    return s.form(["a"], [])


@song
def jingle_secret():
    """C lydian, 150 BPM, 2 s: a secret found. C E F# B up, the #4 giving it its glint, then E6 and C6 sparkling
    over an open C, echoed an eighth later (and a few ticks) on pulse 2."""
    s = _fanfare("jingle_secret", "C lydian", 20)
    s.inst("echo", Inst("p25", vol=18, decay=0.4, sustain=8))
    s.part("a", 1, "C5:1 E5:1 F#5:1 B5:1 E6:2 C6:9 r:5 |", Echo(0, 2, 2, "echo"), "C3:15 r:5 |",
           "o...t.......t.......|")
    return s.form(["a"], [])


@song
def jingle_big():
    """D major, 150 BPM, 6 s: a great item. The cherry tree's motif as a fanfare (D E A B F#, up to F#5 held), a turn
    over G and A up to the high D, eighth-note chords under it, drums rolling into the crash on the last chord."""
    s = _fanfare("jingle_big", "D major", 60)
    s.part("a", 1,
           "D4:2 E4:2 A4:2 B4:2 F#5:8 G5:2 F#5:2 E5:2 D5:2 E5:4 A5:4 F#5:4 A5:4 D6:16 r:4 |",
           "@arp " + "D4+F#4+A4:2 " * 8 + "D4+G4+B4:2 " * 4 + "C#4+E4+A4:2 " * 4 + "D4+F#4+A4:24 r:4 |",
           "D3:8 A2:8 G2:8 A2:8 D3:24 r:4 |",
           "C.s.s.s.C.s.s.s.k.s.k.s.SsSsSSSSC...........................|")
    return s.form(["a"], [])


@song
def jingle_win():
    """D major, 150 BPM, 8 s: Topo Rey beaten, his D minor turned to D major. A march-like fanfare in dotted
    calls (A—a D F# D | B—b D G D | C#—c# E A G) climbing a scale to the high D, pulse 2 a third under the lead
    all the way, the bass marching I IV V I, snare and kick, a crash on the last note."""
    s = _fanfare("jingle_win", "D major", 80)
    s.part("a", 1,
           "A4:3 A4:1 D5:4 F#5:4 D5:4 B4:3 B4:1 D5:4 G5:4 D5:4 C#5:3 C#5:1 E5:4 A5:4 G5:4 "
           "F#5:2 G5:2 A5:4 B5:2 C#6:2 D6:14 r:6 |",
           "@second F#4:3 F#4:1 A4:4 D5:4 A4:4 G4:3 G4:1 B4:4 D5:4 B4:4 E4:3 E4:1 G4:4 C#5:4 E5:4 "
           "D5:2 E5:2 F#5:4 G5:2 A5:2 @arp D4+F#4+A4:14 r:6 |",
           "D3:4 A2:4 D3:4 A2:4 G2:4 D3:4 G2:4 B2:4 A2:4 E3:4 A2:4 C#3:4 D3:4 G2:4 A2:4 D2:14 r:6 |",
           "k.s.k.s." * 6 + "k.s.ssssSSSS" + "C" + "." * 19 + "|")
    return s.form(["a"], [])


@song
def jingle_gameover():
    """A minor, slow: 80 BPM (speed 9, tempo 120), 6 s: sad and short. A rises a little and sighs (A— C E—— D), then
    falls (C— B A———) over Am, Dm/F, E7 and Am, the chords held soft on pulse 2, the bass sinking to a low A."""
    s = _fanfare("jingle_gameover", "A minor", 16, tempo=120, speed=9)
    s.inst("sad", Inst("p50", vol=40, decay=0.12, sustain=26, vib=16, vib_delay=0.3, vib_hz=4.5))
    s.inst("hold", Inst("p50", vol=24, steps=(24, 22, 20, 18, 16, 14, 12, 12, 10, 10, 8, 8)))
    s.part("a", 2, "@sad A4:3 C5:1 E5:8 D5:4 | C5:3 B4:1 A4:10 r:2 |",
           "@hold C4+E4+A4:12 D4+F4+A4:4 | B3+D4+G#4:4 C4+E4+A4:10 r:2 |", "A2:12 F2:4 | E2:4 A2:10 r:2 |",
           "o...............|................|")
    return s.form(["a"], [])


# ---------------------------------------------------------------------------------------------------------- main

def main(argv: list[str]) -> None:
    out_dir = GAME / "audio"
    out_dir.mkdir(exist_ok=True)
    names = argv or list(SONGS)
    print(f"{'song':16} {'key':18} {'meter':5} {'BPM':>5} {'intro s':>7} {'pass s':>7} {'bytes':>6}")
    for name in names:
        s = make(name)
        b = build(s)
        (out_dir / f"{name}.mod").write_bytes(b.data)
        length = b.intro_s if s.jingle else b.loop_s
        print(f"{name:16} {s.key:18} {s.meter:5} {s.bpm:5.0f} {b.intro_s:7.1f} {length:7.1f} {len(b.data):6}")


if __name__ == "__main__":
    main(sys.argv[1:])
