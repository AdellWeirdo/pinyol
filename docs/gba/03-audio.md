# GBA audio hardware and software: reference digest for pinyol

Purpose: how GBA audio really worked, so we can decide how to extend `src/psg.c`, `src/audio.c`, `src/modplay.c`.
Written from GBATEK, Tonc, Pan Docs, mGBA / NanoBoyAdvance (read only, described in prose, no code copied),
pret/pokeemerald (`include/gba/m4a_internal.h`, `src/m4a.c`, `src/m4a_1.s`, `asm/macros/music_voice.inc`), agbplay's README,
Maxmod's docs. No Nintendo SDK / AGB manual material was used.
"unverified" = not confirmed in a primary source during this research (general knowledge or inference);
"derived" = arithmetic from verified numbers.

Sources (whole doc):
- GBATEK, https://problemkaputt.de/gbatek.htm (the "GBA Sound" sections; the fetch covered the first 100 kB of the page only)
- Tonc ch. 18 (square channels), https://gbadev.net/tonc/sndsqr.html (coranac.com did not resolve; there is no Direct Sound chapter in the mirror)
- Pan Docs "Audio details" (frame sequencer, LFSR, sweep internals), https://gbdev.io/pandocs/Audio_details.html
- Ian Finlayson, "Sound Programming" (Direct Sound / DMA / timer), https://ianfinlayson.net/gba/10-sound.html
- Maxmod docs (BlocksDS copy): https://blocksds.skylyrac.net/maxmod/md_documentation_2cpu__usage.html , `..._2memory__usage.html`, `..._2hardware__usage.html`, `..._2gba__programming__guide.html`, `group__gba__init.html`
- pret/pokeemerald: https://github.com/pret/pokeemerald (files above, raw.githubusercontent.com)
- mGBA audio core: https://github.com/mgba-emu/mgba/blob/master/src/gba/audio.c
- NanoBoyAdvance APU + MP2K HLE (read only): https://github.com/nba-emu/NanoBoyAdvance/tree/master/src/nba/src/hw/apu
- agbplay (MP2K player): https://github.com/ipatix/agbplay
- Battle of the Bits GBA overview (tools list), https://battleofthebits.com/lyceum/View/GameBoy%20Advance ; Krawall, https://battleofthebits.com/lyceum/View/Krawall
- Bregalad's "Sappy" document (RHDN doc 462) was not retrievable (host closed the connection); everything about MP2K below comes from the pokeemerald decomp and agbplay/NBA instead.

---

## 1. Big picture

| Block | What it is | Output scale |
|---|---|---|
| 4 PSG channels | The Game Boy / GBC "analogue" generators: CH1 pulse+sweep, CH2 pulse, CH3 4-bit wave RAM, CH4 noise | each up to +-0x80 (9-bit output scale) |
| 2 Direct Sound channels A/B | 8-bit signed PCM, fed from a 32-byte FIFO by DMA, one sample popped per timer overflow | each up to +-0x200 |
| Mixer + SOUNDBIAS | sums, adds bias 0x100-ish, clips to 10 bits (0..0x3FF), PWM output | see section 4 |
| Output | one built-in mono speaker; stereo only through the line-out connector | |

- Hardware sums everything; it has no software mixing. **All polyphony beyond 2 PCM streams is software** (m4a, Maxmod, Krawall mix N voices on the CPU into one buffer that DMA feeds to FIFO A, and often B for stereo).
- Source: GBATEK "GBA Sound Controller" (levels, +-0x600 sum, 0..3FFh clip); Battle of the Bits GBA page.

## 2. The 4 legacy PSG channels

Source: GBATEK sound section; Tonc `sndsqr`; Pan Docs `Audio_details`. GBA I/O addresses below (the same bits as DMG/CGB NRxx).

### 2.1 Registers

| Reg (addr) | Bits | Meaning |
|---|---|---|
| SOUND1CNT_L 4000060h (NR10) | 0-2 shift n; 3 dir (0 up, 1 down); 4-6 sweep time T | sweep: every T/128 s (7.8 ms units, T=1..7), `R' = R +- R/2^n`; T=0 disables |
| SOUND1CNT_H 4000062h / SOUND2CNT_L 4000068h (NR11/12, 21/22) | 0-5 length L; 6-7 duty; 8-10 envelope step time; 11 env dir (1 = increase); 12-15 initial volume 0..15 | length `(64-L)/256` s; duty 0..3 = 12.5/25/50/75 %; env step = `n/64` s, volume moves +-1 per step; n=0 no envelope |
| SOUND1CNT_X 4000064h / SOUND2CNT_H 400006Ch (NR13/14, 23/24) | 0-10 rate R; 14 length-enable; 15 trigger | **f = 131072 / (2048 - R) Hz** (R 0..2047 gives ~64 Hz..131 kHz); register is write-only: write the whole value to retrigger |
| SOUND3CNT_L 4000070h (NR30) | 5 dimension (0 = 32 samples, 1 = 64); 6 bank played; 7 on | wave RAM is two 16-byte banks = 2 x 32 four-bit samples, or one 64-sample pattern |
| SOUND3CNT_H 4000072h (NR31/32) | 0-7 length; 13-14 volume (0 mute, 1 = 100 %, 2 = 50 %, 3 = 25 %); 15 force 75 % | length `(256-L)/256` s |
| SOUND3CNT_X 4000074h (NR33/34) | 0-10 rate R; 14 length; 15 trigger | **sample rate = 2097152 / (2048 - R) Hz**; tone = sample rate / pattern length |
| Wave RAM 4000090h-400009Fh | 16 bytes, high nibble first | internally a shift register: write all of it at once (reads may return shifted data) |
| SOUND4CNT_L 4000078h (NR41/42) | length, envelope: as CH2 | |
| SOUND4CNT_H 400007Ch (NR43/44) | 0-2 divisor r; 3 width (0 = 15-bit, 1 = 7-bit); 4-7 shift s; 14 length; 15 trigger | **f = 524288 / r / 2^(s+1) Hz** (r=0 counts as 0.5) |
| SOUNDCNT_L 4000080h (NR50/51) | 0-2 / 4-6 PSG master volume R/L (0..7); 8-11 / 12-15 enable CH1-4 on R/L | |
| SOUNDCNT_H 4000082h | 0-1 PSG ratio (25/50/100 %, 3 prohibited); 2/3 DMA A/B 50 or 100 %; 8,9 / 12,13 DS A/B enable R/L; 10/14 timer select; 11/15 FIFO reset | |
| SOUNDCNT_X 4000084h (NR52) | 7 master enable; 0-3 channel-on flags (read) | while bit 7 = 0 registers 60h-81h are held at zero: re-init after enabling |

Wave-channel tone for 32 samples: `65536/(2048-R)` for a full-cycle pattern; derived: 64-sample mode halves it, `32768/(2048-R)`.

### 2.2 Timing: the frame sequencer (Pan Docs; GBA PSG is CGB-compatible, exact GBA edge quirks unverified)

| Unit | Rate | Notes |
|---|---|---|
| Frame sequencer | 512 Hz (8 steps) | drives the three below |
| Length counter | 256 Hz (every 2nd step) | only when the length-enable bit is set |
| CH1 sweep | 128 Hz (every 4th step) | shadow register; frequency overflow past 2047 silences CH1 |
| Envelope | 64 Hz (every 8th step) | 1/64 s per step unit; this is why "envelope step n" is n/64 s |
| Pulse duty | 8 steps per period | duty step advances at 8 x f; retriggering resets the step timer |
| Wave | index advances at 32 x f | sample 0 is skipped on start; retrigger does not refresh the sample buffer |
| Noise LFSR | clocked at the NR43 rate | clock shift 14/15 = no clocks |

- Noise LFSR: 15-bit state shifted right each clock; feedback bit = XOR of the two low bits (GBATEK: taps 6000h in 15-bit, 60h in 7-bit; Pan Docs describes the same machine as an XNOR with reset to 0, so the two descriptions differ in polarity/initial state). 7-bit mode repeats after 127 steps (metallic ring), 15-bit after 32767 (hiss). Lock-up if the active bits are all ones (Pan Docs).
- Pulse waveform detail (Tonc): 50 % kills every 2nd harmonic, 12.5 % kills every 8th (the thin, nasal timbre), 25 % and 75 % sound the same (every 4th).
- Volume is linear 0..15 (4 bit). PSG is generated at 262.144 kHz internally (GBATEK) and resampled to the output rate, so it is not "8-bit crunchy" the way Direct Sound is; it is aliasing-heavy square waves instead.

### 2.3 Tonc note table (tonc `sndsqr`)

- Octave rates for the pulse channels: `R = 2048 - (rates[note] >> (4 + oct))` with C=8013, C#=7566, D=7144 ... B=4246 at the top octave; Tonc notes the rate steps get coarse at high octaves (the formula is `2^17/(2048-R)`, so adjacent R values are further apart in Hz as R nears 2047).

## 3. Direct Sound A / B

Source: GBATEK "DMA Sound"; Ian Finlayson `10-sound.html`; Maxmod hardware page.

| Item | Value |
|---|---|
| FIFO | `FIFO_A` 40000A0h, `FIFO_B` 40000A4h, write-only, 32 bytes (8 words); samples **signed 8-bit**, byte 0 plays first |
| Sample clock | Timer 0 or 1 (chosen per channel in SOUNDCNT_H bit 10/14); one sample leaves the FIFO per overflow |
| Refill | when the FIFO holds <= 16 bytes it requests DMA; DMA 1 (A) / 2 (B), start timing 3 (sound FIFO), repeat on, dest fixed = FIFO, 4 words per request, count ignored |
| Timer reload | `reload = 65536 - 16777216 / rate` (prescaler F/1); e.g. 13379 Hz = 1254 cycles, reload 64282; 16384 Hz = 1024 cycles |
| Good rates | 32768, 16384, 8192 Hz (divide the 32.768 kHz output clock evenly); odd rates are held (zero-order hold) so jitter and imaging appear |
| Volume | only 50 % or 100 % per channel in hardware (SOUNDCNT_H bit 2/3); finer volume is applied in software before the FIFO |
| Pan | enable bit per side per channel: A to R, A to L, B to R, B to L; the hardware cannot pan between, only on/off; fake pan = two software mixes at different gain |
| Two ways to use it | (1) one-shot "stream a sample" (Finlayson: DMA a whole array, count VBlanks, rearm on loop); (2) double-buffered software mixer, buffers swapped by a VBlank IRQ with DMA re-armed (Maxmod, m4a). Maxmod warns the VBlank handler is timing-critical and must not be interrupted. Timer 0 belongs to the mixer: touching it corrupts audio. |
| Resampling | each FIFO sample is **held** until the next timer overflow, then the whole sum is resampled to 32.768 kHz (GBATEK); no interpolation in hardware |

## 4. Master mixing, SOUNDBIAS, output rate

Source: GBATEK SOUNDBIAS; mGBA `audio.c` (prose reading); NanoBoyAdvance `apu.cc` (prose reading).

| SOUNDBIAS bits 14-15 | Resolution | Sample rate | Best for |
|---|---|---|---|
| 0 (default) | 9 bit | 32.768 kHz (512 cycles) | Direct Sound |
| 1 | 8 bit | 65.536 kHz | |
| 2 | 7 bit | 131.072 kHz | |
| 3 | 6 bit | 262.144 kHz | PSG (it is generated at this rate) |

- Bits 1-9: bias level (default 100h, register default 0200h). Each FIFO spans +-200h, each PSG channel +-80h; the sum can reach +-600h; add bias, **clip to 0..3FFh**. So loud music clips hard, and the engine's master volume exists to avoid it.
- mGBA's model: PSG is shifted by (4 - PSG ratio) (25/50/100 % = shifts 2,3,4); each FIFO is `<<2` then halved unless "full volume" is set; summed per side; biased; clamped to 10 bits; bias removed; times master. Output is produced per `512 >> resolution` cycles.
- Final stage is a 1-bit PWM at 16.78 MHz (512 bits per sample at 32.768 kHz): cheap analogue filtering, so high-frequency imaging from the 13 kHz hold is audible as grit. (PWM detail from GBATEK.)
- Low power: SOUNDCNT_X = 0 and SOUNDBIAS = 0. SWI 19h "SoundBias" ramps the bias gradually to avoid pops (GBATEK). The rest of the BIOS sound-driver SWIs (1Ah..28h, MidiKey2Freq etc.) were not retrievable here: unverified.
- Emulator contrast: NanoBoyAdvance mixes in integer with the bias path, but when its MP2K HLE is active it mixes floating point at 65536 Hz and resamples (cosine, cubic or sinc); agbplay resamples PCM straight to the output rate (nearest, linear, sinc, BLEP, BLAMP) and runs its sequencer at 240 Hz instead of 60 Hz. Both are explicitly "better than hardware", not accurate.

## 5. The m4a / MP2K / "Sappy" engine

Nintendo's "MusicPlayer2000", used by most first-party and many third-party GBA games (Battle of the Bits; pokeemerald calls it m4a). Not all games: others used Krawall, Maxmod, GAX and studio-private engines (see section 7).
Sources: `m4a_internal.h`, `m4a.c`, `m4a_1.s`, `music_voice.inc` (pret/pokeemerald); agbplay README; NanoBoyAdvance `mp2k.cc`.

### 5.1 Architecture

| Part | Fact |
|---|---|
| Mixer | `SoundMain` runs **once per VBlank** (59.7275 Hz), mixes `pcmSamplesPerVBlank` samples (224 at 13379 Hz) for up to `maxChans` PCM channels into a ring of `pcmDmaPeriod` frames per side (L and R buffers, `PCM_DMA_BUF_SIZE` = 1584 bytes each in pokeemerald); DMA1/2 feed FIFO A (left) and B (right) from the ring, Timer 0 reload = `-(280896 / samplesPerVBlank)`, started on a fixed scanline so mixing stays in phase with VBlank |
| Budget | `maxLines` limits how far down the screen the mixer may run (it compares VCOUNT); overrun stops mixing -> crackles. Typical games are tuned to this, not to a fixed cost |
| Channels | up to 12 PCM channels (`MAX_DIRECTSOUND_CHANNELS`), each with an ADSR state machine; pokeemerald sets 5 at init with master volume 12/15 at 13379 Hz (from the `m4aSoundInit` read; other games choose 4..12) |
| PSG | the 4 hardware channels are driven by register writes (`CgbSound`), once per frame, not mixed in software; one note per hardware channel, so a 4th simultaneous pulse is impossible |
| Players / tracks | a MusicPlayer holds up to 16 tracks; several players run side by side (BGM, SFX, cries) with priority-based channel stealing (details of the steal rule unverified) |
| Sequencer clock | `tempoD` base 150, `tempoU` user multiplier (256 = 1.0), `tempoI = tempoD * tempoU / 256`; each frame adds `tempoI` to an accumulator, each wrap of 150 = one tick. At 24 ticks/quarter (clock table not seen: inferred) default is ~149 BPM. Timing granularity is therefore **one frame (16.7 ms)** |
| Track cmds | note, rest, key-shift, tune, bend + bend range, vol, pan, mod depth + LFO speed/delay + mod type (vibrato or tremolo or pan), loops/patterns (3-deep pattern stack), jump, priority, tempo, voice select, extended: tone-env override (xatta/xdeca/xsust/xrele), xtype, xwave, xleng, xswee, xiecv/xiecl (pseudo-echo), `memacc` (shared byte area ops used for game-driven music changes) |
| Volume maths | `x = vol * volX / 32`; tremolo scales by `(modM+128)/128`; pan `y = 2*pan + panX` clamped -128..127; `volR = (y+128)*x/256`, `volL = (127-y)*x/256` |
| Pitch maths | 256 units per semitone: `(tune + bend*bendRange)*4 + keyShift*256 + pitX`; vibrato adds `16*modM` |
| Fades | fade value 64..0 in steps of 4, each step `speed` frames: `speed=4` is ~1.07 s |

### 5.2 Instruments ("voices") and voice groups

A **voice group** is an array of 128 12-byte `ToneData` entries (one per MIDI program); `ToneData` = `type, key, length, pan_sweep, wav/pointer, attack, decay, sustain, release`.

| Type byte | Name | Meaning |
|---|---|---|
| 0x00 | `voice_directsound` | PCM sample (signed 8-bit) with root MIDI key, pan, ADSR; pitch shifts by resampling |
| 0x08 | `..._no_resample` (FIX) | plays at the sample's own rate regardless of the key: drums, one-shots, voice clips (agbplay: such samples are tied to one of the 12 mix rates) |
| 0x10 | `..._reverse` | reversed playback |
| 0x20 / 0x30 | `..._compressed` (+reverse) | **4-bit delta** blocks: 33 bytes -> 64 samples through a 16-entry delta table (about half the ROM of 8-bit PCM); decoded on the fly into a shared cache |
| 0x01 / 0x09 | `voice_square_1` (+alt) | PSG pulse with sweep, duty (2 bits) |
| 0x02 / 0x0A | `voice_square_2` | PSG pulse, duty |
| 0x03 / 0x0B | `voice_programmable_wave` | PSG CH3 with a 16-byte wave pointer |
| 0x04 / 0x0C | `voice_noise` | PSG CH4; "period" 1 bit = 15-bit or 7-bit LFSR |
| 0x40 | `voice_keysplit` | key -> sub-voice through a 128-byte key table (a piano low/high layer) |
| 0x80 | `voice_keysplit_all` (rhythm/drum kit) | the key itself indexes a voice group: one drum per key, each with its own sample/pan/ADSR |

- PSG ADSR is narrower: attack/decay/release 0..7 and sustain 0..15 (masked in the macros) because they become hardware envelope values; DirectSound ADSR bytes are 0..255.
- `WaveData` header: `type, status (loop flag), freq, loopStart, size` then signed 8-bit samples. A sample carries its own rate; the engine converts note + sample rate + mix rate into a fixed-point step.

### 5.3 ADSR in the software mixer (per frame, not per sample)

| Phase | Rule (per VBlank, 8-bit fixed point) |
|---|---|
| Attack | add `attack` to the envelope; clamp at 255, then decay. `attack = 255` = instant. (NBA HLE: attack 0xFF jumps straight to decay) |
| Decay | multiply by `decay / 256`; stop at the sustain level `sustain/255` of full |
| Sustain | hold until key-off (note length / `gateTime` elapsed) |
| Release | multiply by `release / 256` each frame; at the pseudo-echo level the channel either ends or enters **pseudo-echo**: volume `pseudoEchoVolume/256`, kept for `pseudoEchoLength` frames, a cheap tail |
| Per output | envelope * master (`(masterVol+1)/16`) * per-side volume `>>8`; the NBA HLE interpolates the envelope linearly across the 224 samples to avoid zipper noise (hardware steps per frame: unverified) |
| PSG note | `CgbSound`: attack/decay/release are frame counters that step the 4-bit volume by 1; `sustainGoal = (goal*sustain + 15) >> 4`; the hardware envelope unit is 64 Hz, so every 15th frame runs two steps (59.73 vs 64 Hz) |

### 5.4 Sample stepping and quality

- Phase is fixed-point (23-bit fraction), step = `freq * divFreq`; **linear interpolation** between neighbour samples on normal channels (the assembly; agbplay says "Linear" is the closest match to Nintendo's driver). FIX channels step 1 sample per output sample. Loops wrap at `loopStart`, reversed and compressed variants exist.
- Mixing is 8-bit data * 8-bit gains into packed accumulators; the left and right buffers are 8-bit; no dither (hence the "sizzle" that pinyol's Lo-fi GBA mimics).

### 5.5 Reverb (the "tunnel" sound)

- One global reverb value 0..127 (mode bits), not per channel, and **PCM only; PSG stays dry**.
- From the `m4a_1.s` read: before channel mixing, for each output sample the driver sums four numbers (the L and R buffer values at the write position and at the position one frame ahead of it), multiplies by `reverb`, `>>9`, adds 1 if bit 7 of the result is set, stores the byte to **both** sides (reverb is mono-fied), and the stored result is itself read again later: a feedback delay.
- Because the ring has `pcmDmaPeriod` frames, the write position holds what was written `period` frames ago and the next one `period-1` frames ago: **two taps, `period-1` and `period` frames (6 and 7 at 13379 Hz = 100 and 117 ms)**. This matches the numbers in `src/studio_fx.c` (`GBA_TAP1/2`). Gain: for mono content each of the two taps adds `reverb/256`, total feedback `reverb/128`; so values below 128 always decay, 127 is a very long ring (derived from the prose reading).
- Derived consequence: **the echo time depends on the mix rate** (ring size fixed at 1584 bytes in pokeemerald): see 5.6.
- HLE players (agbplay, NBA) approximate or replace this; NBA's HLE uses a different 3-tap model; do not copy their numbers if hardware-faithful sound matters.

### 5.6 Mix-rate table (SOUND_MODE_FREQ_*)

| Mode | Rate (Hz) | Samples / VBlank (derived) | Ring frames (derived, 1584 B) | Reverb taps (ms, derived) | Note |
|---|---|---|---|---|---|
| 05734 | 5734 | 96 | 16 | 251 / 268 | |
| 07884 | 7884 | 132 | 12 | 184 / 201 | |
| 10512 | 10512 | 176 | 9 | 134 / 151 | cheap, common for small games |
| **13379** | 13379 | 224 | 7 | 100 / 117 | **default of `SoundInit`; pokeemerald** |
| 15768 | 15768 | 264 | 6 | 84 / 100 | Maxmod's "16 kHz" |
| 18157 | 18157 | 304 | 5 | 67 / 84 | |
| 21024 | 21024 | 352 | 4 | 50 / 67 | |
| 26758 | 26758 | 448 | 3 | 33 / 50 | |
| 31536 | 31536 | 528 | 3 | 33 / 50 | |
| 36314 | 36314 | 608 | 2 | 17 / 33 | |
| 40137 | 40137 | 672 | 2 | 17 / 33 | |
| 42048 | 42048 | 704 | 2 | 17 / 33 | |

- Rate = samples/VBlank x 59.7275. Source of the constants: `m4a_internal.h` (mode defines), `m4a.c` (formulas); the per-rate samples/frame list is derived and every value reproduces the rate (e.g. 176 x 59.7275 = 10512), but the table itself was not seen: unverified.
- `SOUND_MODE_DA_BIT_9/8/7/6` select SOUNDBIAS resolution (section 4).
- Maxmod's own rates (BlocksDS docs): 8121, 10512, 13379, 15768, 18157, 21024 Hz (also 27/31 kHz in the enum), buffer lengths 544 / 704 / 896 / 1056 / 1216 / 1408 bytes; default 15768 ("16 kHz").

### 5.7 CPU / RAM cost

| Item | Value | Source |
|---|---|---|
| Frame budget | 280,896 cycles = 100 % in Maxmod's measure | Maxmod cpu docs |
| Maxmod base | ~2.6 % with no channel playing | Maxmod cpu docs |
| Maxmod per channel (16 kHz) | 1.23 % hard L/R, 1.29 % centre, 1.49 % arbitrary pan; module playback adds ~2 % per channel; estimate `2.6 + 2 x channels` %; 8 ch measured ~18 % | Maxmod cpu docs (mixing buffer in IWRAM, data in EWRAM, WAITCNT 4317h) |
| Derived | ~3600 cycles / frame / voice at 264 samples = ~14 cycles per voice-sample | derived |
| Maxmod RAM | 8 ch @ 16 kHz: IWRAM 5.69 KB, EWRAM 1.79 KB, ROM 6.54 KB (soundbank extra) | Maxmod memory docs; EWRAM mixing buffer = "much higher CPU load" |
| m4a | no first-hand number found: unverified. Rule of thumb in the community: several % to ~15 % at 13 kHz / 8 ch: unverified |

## 6. What GBA music sounds like, and why

(Section mostly inference from the verified mechanics above; flagged where not confirmed in a source.)

| Trait | Cause |
|---|---|
| Dull top end, "radio" / telephone brightness | software mix at 13379 Hz (default) = Nyquist 6.7 kHz; samples are often recorded even lower (4-8 kHz) |
| Grit and sizzle, noise floor | 8-bit samples and 8-bit mix buffers, no dither; zero-order hold into the 32.768 kHz DAC leaves imaging; 1-bit PWM output |
| Quick, plucky, "all the same instrument" feel | a single short looped sample per instrument, pitch-shifted across a 128-key range, ADSR as the only shaping; no filters, no per-voice effects |
| Tunnel / washed pad | global feedback reverb with 100/117 ms taps (section 5.5) |
| Chip layer on top | the PSG channels are mixed in beside the PCM: pulse leads, wave bass, noise hats; common in Pokemon-style scores (inference) |
| Tight small songs | MIDI-like note streams, 24 ticks/quarter, shared voice groups; scores are tens of KB |
| Pitch resolution | linear interpolation without oversampling aliases when a sample is shifted up more than ~an octave |
| Stereo | in games, true stereo only from headphones; many engines pan by volume difference L vs R (hard-pan sounds cheaper to mix, Maxmod cpu docs) |

## 7. Common alternatives and what real games shipped

| Engine | Input | Notes | Source |
|---|---|---|---|
| m4a / MP2K / Sappy | MIDI -> `mid2agb`; voice groups; WAV -> `wav2agb` | most commercial titles incl. Nintendo and Pokemon; PCM + PSG mix | pokeemerald; Battle of the Bits |
| Maxmod | .mod .s3m .xm .it via `mmutil` into a soundbank | PCM only (the 4 PSG channels free for your own use); runtime channels configurable (8 in examples); sfx with rate 6.10 fixed point, volume and pan 0..255; `mmFrame()` once per frame; ships with devkitPro; free | Maxmod guide; Battle of the Bits |
| Krawall | .s3m (16 ch) and .xm (32 ch) | mono 8-bit samples, PCM only; commercial games (LOTR, Spider-Man, The Sims); LGPL 2.1+; open sourced 2013, not developed since | Battle of the Bits Krawall |
| GBT Player, GBA MML player | .s3m/.mod; MML | PSG only | Battle of the Bits |
| Others (Shin'en GAX, studio-private drivers, Camelot's reverb variants in Golden Sun, Mario Golf Advance) | custom | the agbplay README names Camelot reverb variants; GAX not verified | agbplay README; GAX: unverified |

- Tracker modules decode to "sample + period + effects" and need no instrument ADSR; m4a needs MIDI-like data plus voice groups; trade-off is the size of the data against flexibility: unverified generalisation.

## 8. Gap vs pinyol

### 8.1 What pinyol already has (from `src/psg.c`, `src/audio.c`, `src/modplay.c`, `src/studio_fx.c`, `docs/lua.md`)

| Area | pinyol today | GBA parallel |
|---|---|---|
| Output | mono PCM16 at `AUDIO_HZ` 22050 Hz (`bp.h`); float mix in `audio_mix` with a soft-knee limiter | GBA: mono speaker, 32.768 kHz out, 10-bit clip |
| Voices | `psg.c`: 4 voices, waves square (any float duty) / triangle / saw / sine / noise; attack/decay/sustain/release (exponential), `len`, `release`, linear Hz/s `slide`; naive non-band-limited oscillators | PSG: 2 pulse, wave, noise |
| Noise | 15-bit LFSR clocked once per voice period (a new value per period); no 7-bit mode | CH4 with 7/15-bit, divisor table |
| Sample voices | 12 `sfx_voice`s, linear-interpolated pitch 1/16..16, loop whole clip, gain, handle; RAM cache of 1.5 MB, up to 4 variants; a stealing rule | Direct Sound software voices |
| Studio | step sequencer in the audio thread (16 sample or synth tracks, swing, choke, velocity), band-limited TB-303-style synth voice, echo and plate reverb, **GBA reverb (two taps 2216/2585 samples = 6 and 7 frames of 224 at 13379 Hz)** and **Lo-fi GBA** (hold at 13379 Hz, 8 bit, no dither) over the master | m4a reverb + 13379 Hz/8-bit mixer |
| Music | WAV stems with bar-quantised layering (`music_layer`), or `.mod` through pocketmod (4 MB cap, up to 32 channels, ~3 % of a core on the console per `docs/lua.md`) | Maxmod/Krawall-style modules; m4a-style layering by `memacc` |
| Other | `music_time()` sample-accurate clock; microphone | |

### 8.2 Missing vs GBA (concrete), ranked

Ranking = value for game feel against CPU/RAM on ESP32-S3 (240 MHz dual core, PSRAM). CPU estimates assume one voice-sample at ~25-40 cycles with float + linear interpolation + envelope: ~0.4 % of one core per voice at 22050 Hz (estimate, not measured; `docs/measurements.md` has no audio figure).

| # | Feature | What it is on GBA | Value | Cost | Where in pinyol |
|---|---|---|---|---|---|
| 1 | **Sample instruments with ADSR** | m4a `voice_directsound`: sample + root key + loop start/end + A/D/S/R + gain; note -> pitch step | 5/5: turns `.wav`s into playable instruments, pairs with the studio's pitch and `note()`; GBA-style music from small samples | ~0.4 % core per voice, bytes per instrument (~32 B); samples as 8-bit/PCM16 at 11-22 kHz are tens of KB | extend `sfx_voice` in `audio.c` (env state, loop_start, root key) + a Lua `instrument(id, {...})` and `play(inst, note, vel)`; let studio tracks play instruments |
| 2 | **Programmable wave voice (CH3)** | 16-byte, 32 x 4-bit table, 4 volume steps; used for bass, bells, organ | 4/5: the most distinctive timbre pinyol lacks (`psg.c` only has 5 fixed waves); trivial | 16 B/voice, one table lookup per sample | add `PSG_WAVE` to `psg_note` + `tone(v, p, {wave = {0..15 x 32}})` |
| 3 | **Authentic PSG options** | 7-bit noise ("metallic"), noise from (r, s) divisor table, discrete duty 12.5/25/50/75, exponential sweep `R +- R/2^n`, 4-bit/15-step stepped envelope, optional 4-bit quantised output | 3/5: cheap flavour and instantly "GBA"; pinyol's float duty and continuous envelope are the opposite | negligible | `psg.c` only (`lfsr` width switch, `duty` snap option, `sweep` fields) |
| 4 | **Vibrato / pitch bend / tremolo LFO per voice** | m4a track mod (vibrato depth, speed, delay), bend range | 4/5 for expressiveness; Lua cannot do it per sample cleanly at 60 Hz | negligible (one sine LFO per voice) | `psg.c`, and the new instrument voices |
| 5 | **Global reverb send for non-studio sources** | m4a reverb value applies to all PCM voices, PSG dry | 3/5: `sfx`, `music`, `.mod`, instruments currently bypass the GBA reverb (sends exist only on studio tracks) | one 2.6k-sample mono delay (already allocated, ~5 KB) + a few multiplies per sample | `audio_mix` sums into `sr` for chosen buses; a `reverb(amount)` call (0..127 like m4a) |
| 6 | **Voice priority and polyphony per track** | m4a priority + channel stealing, per-player maxChans | 2/5: matters when instruments + sfx compete; present rule only steals the one closest to its end | none | `audio_voice_start_locked` takes a priority |
| 7 | **Key-split and drum-kit instruments** | types 0x40 / 0x80 | 3/5 once #1 exists; a table `key -> instrument` is the cheap version | a 128-byte table per instrument | Lua data, same API as #1 |
| 8 | **Selectable Lo-fi rate/bit depth** | `SOUND_MODE_FREQ_*` 5734..42048 Hz, DA_BIT 9/8/7/6; reverb time moves with the rate | 2/5; `studio.fx{lofi = true}` is hard-wired to 13379 Hz | none | `studio_fx.c` (`lph += rate / AUDIO_HZ`), scale the reverb taps by rate/13379 to follow m4a |
| 9 | **Pseudo-echo tail** | m4a `pseudoEchoVolume/Length` | 1/5 | none | in the new ADSR |
| 10 | **Tracker formats beyond MOD (XM/IT/S3M)** | Maxmod / Krawall: S3M/XM/IT with instrument envelopes, more channels | 2/5: `.mod` already covers the "small tracker music" case; XM/IT would need a new library (licence not checked: unverified) | RAM + a new dependency; CPU ~ pocketmod x2-3 | `modplay.c`, third_party |
| 11 | **4-bit delta compressed samples** | m4a `compressed` type | 1/5: PSRAM is plentiful (1.5 MB sfx budget today); only worth it for a bigger instrument library | decode per block | `audio.c` loader |
| 12 | **Stereo / per-voice pan** | m4a pan in track and voice | 0-1/5: the console has a mono speaker; keep for a headphone path only | doubles the bus | skip |
| 13 | **VBlank-quantised sequencing (60 Hz)** | m4a tick per frame | 0/5: the audio thread already times to the sample; keep. If a "GBA-feel" mode is wanted, quantise note starts to 16.7 ms: not needed | | skip |

Suggested order: (1) + (4) together as "instruments" (a tiny voice-group in Lua tables), (2) and (3) as a half-day `psg.c` job, then (5). Items 6-13 only on demand.

### 8.3 Notes on current code relevant to the ranking

- `psg.c` oscillators are naive (no band limiting): at 22050 Hz the saw/square fold aliases; the studio synth already uses PolyBLEP (`studio_synth.c`). The GBA PSG aliased too, so this can be an option rather than a defect.
- `psg.c` envelope is exponential in float; m4a/GBA PSG envelope is 1/15 steps at 64 Hz. A "stepped" flag gives the GBA staircase.
- `sfx_voice` has no per-voice envelope; looping is whole-clip (`loop` flag) without loop points, which blocks instrument-style sustained notes.
- `audio_mix` runs per 256-sample chunk; per-sample envelope math adds linearly (same ramp style as the `ramp` helper).
- The GBA reverb in `studio_fx.c` is applied only to the studio's sends: see #5 for GBA parity (PCM wet, PSG dry).
- Reverb taps in `studio_fx.c` are a fixed pair; m4a's depend on rate (section 5.6).

## 9. Open questions (unverified)

- Exact m4a per-frame envelope arithmetic for the first frame and key-off at the same tick (read via summaries of the assembly, not line by line).
- Real-hardware (not mGBA/NBA) behaviour of PSG at SOUNDBIAS 6-bit and of the wave-RAM bank swap.
- m4a's channel-stealing rule and the exact `gClockTable` (24 ticks per quarter inferred from tempo constants).
- BIOS sound-driver SWIs (1Ah-28h) and Nintendo's own mixing-buffer size per mode other than pokeemerald's 1584 B.
- Bregalad's Sappy document and Nintendo's original documentation were not read; GAX/other commercial drivers not researched.
