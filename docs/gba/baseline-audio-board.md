# What the sound costs on the board

Measured on 2026-10-19 with `firmware/main/bench_audio.c` (`cd firmware && idf.py -DBP_BENCH=audio build flash`): the real audio
output (ES8311, I2S, the mixing task on core 1) with voices started from the bench, over 4 s for each case. The percentages are
the time `audio_mix()` takes for a block of 256 samples (11.6 ms of sound) over that 11.6 ms: `min` is the quickest block, the
cost with nothing in its way; `mean` and `max` include the task being preempted. In every case they sit within 0.5 % of each
other (the 12 plain voices: 0.5 %), so the cost is steady. No underrun in any case.

| Case | min | mean | max |
|---|---|---|---|
| idle (no voice), right after boot | 6.69 % | 6.74 % | 6.75 % |
| idle (no voice), 12 s later | 1.09 % | 1.10 % | 1.14 % |
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
| idle again after everything, 12 s on | 1.09 % | 1.10 % | 1.14 % |

## What it says

- **A mixer with nothing to play costs 1.1 % of a core.** Right after boot it costs 6.7 %: the studio's effects (`studio_fx.c`)
  stay on for about 8 s after the last send, whatever the game does. That is older than this work and worth a look: 5.6 % of a core
  for nothing at every start.
- **A voice costs about 0.4-0.6 % of a core**: 0.40 % a plain one as recorded (4 voices), 0.47 % (12), 0.50 % pitched, 0.59 %
  an instrument note (envelope and loop region). The general path costs a little more than the pitched one (0.09 % a voice) and
  stays flat from 4 to 12 voices. The audit's guess, made without a number, was 0.4 %.
- **A PSG tone costs far more**: 2.0 % a tone with a wave table, 2.4 % with vibrato (float per sample, an envelope, a table
  lookup, and an `exp2f` every 16 samples for the vibrato). Four tones are 9-11 % of a core. A lookup table or a fixed-point
  phase would cut it; nobody asked yet.
- **Reverb**: the GBA's two echoes with the 8-bit rate cost about 1.8 % over the four instruments; the plate reverb 6.3 %.
- **Everything at once** (8 instrument notes, 4 vibrato tones, the GBA reverb and its rate) is 17.3 % of a core. The mixer shares
  core 1 with the second half of each frame's drawing, which preempts it; this has not been measured together with a game.
