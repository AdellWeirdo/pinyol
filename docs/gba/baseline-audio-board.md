# What the sound costs on the board

Measured on 2026-10-19 with `firmware/main/bench_audio.c` (`cd firmware && idf.py -DBP_BENCH=audio build flash`): the real audio
output (ES8311, I2S, the mixing task on core 1) with voices started from the bench, over 4 s for each case. The percentages are
the time `audio_mix()` takes for a block of 256 samples (11.6 ms of sound) over that 11.6 ms: `min` is the quickest block, the
cost with nothing in its way; `mean` and `max` include the task being preempted. In every case they sit within 0.5 % of each
other (the 12 plain voices: 0.5 %), so the cost is steady. No underrun in any case.

| Case | min | mean | max |
|---|---|---|---|
| idle (no voice) | 1.09 % | 1.10 % | 1.14 % |
| 4 sample voices, as recorded (fast path) | 2.69 % | 2.71 % | 2.76 % |
| 12 sample voices, as recorded | 6.74 % | 6.83 % | 7.21 % |
| 8 sample voices, pitched (interpolated) | 5.12 % | 5.19 % | 5.43 % |
| 4 instrument notes (envelope, loop region) | 3.44 % | 3.46 % | 3.54 % |
| 8 instrument notes | 5.81 % | 5.83 % | 5.92 % |
| 12 instrument notes | 8.17 % | 8.24 % | 8.36 % |
| 4 PSG tones, wave table | 8.98 % | 8.99 % | 9.05 % |
| 4 PSG tones, wave table + vibrato | 10.65 % | 10.76 % | 10.79 % |
| 4 instruments + GBA reverb + lo-fi | 5.26 % | 5.38 % | 5.55 % |
| 8 instruments + 4 tones + GBA reverb + lo-fi | 17.26 % | 17.49 % | 17.66 % |
| 4 instruments + plate reverb | 9.70 % | 9.82 % | 9.96 % |
| idle again after everything | 1.09 % | 1.10 % | 1.14 % |

## What it says

- **A mixer with nothing to play costs 1.1 % of a core**, from the first second (the console's own `perf:` line shows 1-2 % in the
  game list). A first run of this bench, which started the audio without `audio_reset()`, showed 6.7 % for 8 s: that was the
  bench's own doing. The studio's effects rest when `studio_fx_reset()` has run (a game's start does it through `audio_reset()`);
  without it their idle count starts at 0 and they run for 8 s. The bench now resets first, and every other number is the same.
- **A voice costs about 0.4-0.6 % of a core**: 0.40 % a plain one as recorded (4 voices), 0.47 % (12), 0.50 % pitched, 0.59 %
  an instrument note (envelope and loop region). The general path costs a little more than the pitched one (0.09 % a voice) and
  stays flat from 4 to 12 voices. The audit's guess, made without a number, was 0.4 %.
- **A PSG tone costs far more**: 2.0 % a tone with a wave table, 2.4 % with vibrato (float per sample, an envelope, a table
  lookup, and an `exp2f` every 16 samples for the vibrato). Four tones are 9-11 % of a core. A lookup table or a fixed-point
  phase would cut it; nobody asked yet.
- **Reverb**: the GBA's two echoes with the 8-bit rate cost about 1.8 % over the four instruments; the plate reverb 6.3 %.
- **Everything at once** (8 instrument notes, 4 vibrato tones, the GBA reverb and its rate) is 17.3 % of a core. The mixer shares
  core 1 with the second half of each frame's drawing, which preempts it; this has not been measured together with a game.

## On `main`, with the merged mixer, and what was cut from it

The table above is the `gba-engine` mixer. After the merge with `font-catalog` the mixer is the catalog's (sends, panning, game
reverb, ADPCM), which does more for each voice, so the same bench gave a different row set. Measured on the board on 2026-10-19
(min, % of a core), before and after three changes that leave the output bit for bit the same:

| Case | before | after |
|---|---|---|
| idle (no voice) | 1.84 | 1.10 |
| 4 sample voices | 4.63 | 3.66 |
| 12 sample voices | 11.87 | 10.31 |
| 8 sample voices, pitched | 9.07 | 7.71 |
| 8 instrument notes | 9.51 | 8.15 |
| 4 PSG tones, wave table | 9.72 | 5.72 |
| 4 PSG tones, wave table + vibrato | 11.41 | 7.73 |
| 8 instruments + 4 tones + GBA reverb + lo-fi | 19.72 | 15.45 |

- **The ambience bus left out when it has nothing in it** (`mix_core`): with no bed playing, its lowpass empty and its three ramps
  at rest, the loop adds nothing and moves nothing, and it was 22 000 cycles a block, 42 % of the idle cost. `tests/audio_ambient_test.c`
  holds it (a bed through a shut lowpass sings out after it ends; without the empty-lowpass condition that test fails).
- **PSG**: the wave channel divided by 7.5 on every sample (a software division on this core, there is no hardware one); its 256
  possible levels are now a table, worked out with the same expression. The vibrato phase and the slide are no longer advanced when
  their speed is 0.
- **Sample voices** read their gain, sends, pan and reverb once instead of through the voice on every sample, and a bus whose send is
  0 is no longer added to.
- Found on the way, and not it: the engine's `.bss` living in PSRAM (`firmware/components/pinyol_core/linker.lf`) and the mixer running
  from flash. Putting `audio.c` and `psg.c` inside the RAM (32 KB of the 139 KB free) or their code in IRAM changed nothing: with the
  game idle on the other core the loops are bound by instructions (about 60-90 cycles a sample for a loop of some 40 instructions on
  an in-order core), not by memory. Left as it was.
- Checked: a hash of 12 mixes (loops, one-shots, pitched, envelopes with a loop region, pan, reverb, delays, a released voice, PSG tones
  of every wave) is identical before and after, in mono and stereo; 152 tests pass; MAQUETA's train scene on the board runs at
  59.6-60 fps with 0 underruns. Its audio load stays at 8 % of a core: that game's is the music stream, which none of this touches.

## Next to a running game (TRECE's quick game, `main` at `5e0c395`, 2026-10-19)

Played from the cable with `lua:` (an instrument with 8 held notes, then 4 PSG triangle tones with vibrato added), three 1 s windows
of the console's own `perf:` line for each, no screenshots (a capture freezes the game):

| What plays beside TRECE | fps | audio, % of a core | underruns |
|---|---|---|---|
| the game alone | 58.2-59.1 | 7 | 0 |
| + 8 instrument notes | 57.2-59.1 | 15-20 | 0 |
| + 4 PSG tones with vibrato | 58.2-59.3 | 23-28 | 0 |
| everything released | 58.5 | 7 | 0 |

The game keeps 57-59 fps with 27 % of a core going to sound. The one window at 38.6 fps seen before the mixer's changes was not
repeated (nine windows here, none under 57); it may have been the instrument's setup (`sound()` makes its sample the moment it is
called) and not the voices. The audio share is more than the bench's (8 notes 8 %, plus 7 % of TRECE's own sound is 15 %): on the
console the mixer shares core 1 with the second half of the drawing, which preempts it.

