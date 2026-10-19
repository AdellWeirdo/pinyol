# Audit 03: np2d audio vs the GBA's

Scope: `src/psg.c`, `audio.c`, `modplay.c`, `synth.c`, `studio.c`, `studio_synth.c/.h`, `studio_fx.c`, `lua_sound.c`, `lua_studio.c`, `music.c`, `docs/lua.md` (sound sections), `examples/sonidos`, plus the platform audio glue (`platform/sdl/main.c`, `firmware/main/audio_out.c`). Reference: `docs/gba/03-audio.md` (the GBA digest).
Read-only audit; nothing outside `docs/gba/` was touched. Line numbers are as of this reading. "unverified" = not confirmed in code or a measurement; "estimate" = my arithmetic, not measured.

## 0. Digest claims checked against code

| Digest claim (03-audio.md section 8) | Verdict |
|---|---|
| Mono PCM16 at 22050 Hz, soft-knee limiter | Confirmed: `bp.h:12`, `audio.c:585-590`. |
| `psg.c`: 4 voices, 5 waves, float duty, exponential ADSR, linear slide, no 7-bit noise, naive oscillators | Confirmed: `psg.c:51-60` (waves), `:35-38` (envelope), `:89` (slide), `:83-87` (LFSR, 15-bit only). |
| 12 `sfx_voice`s, pitch 1/16..16, linear interpolation, whole-clip loop, steal rule | Confirmed: `audio.c:19`, `:407`, `:642-655`, `:409-414`. Steal rule = free voice, else the non-looping one nearest its end, else voice 0. |
| Reverb/echo only on studio tracks | Confirmed and slightly worse than stated: `tone()`/`psg_mix` also have no send, and `sfx()` calls `audio_voice_start_locked(..., 0, 0, 0)` (`audio.c:399`). The send fields already exist in `sfx_voice` (`audio.c:60`), they are just not reachable. |
| GBA reverb = two taps 2216/2585 samples | Confirmed `studio_fx.c:21-22`; 100.5 ms and 117.2 ms. Feedback per tap `0.2 + size*0.28` (`:135`), so total max 0.96: always decays. Wet only, mono, 16-bit buffer (5.2 KB). |
| Lo-fi hard-wired to 13379 Hz | Confirmed `studio_fx.c:166`; 8 bit, no dither, applies to the whole mix (psg, mod, streams, sfx) before master gain and limiter (`audio.c:661-662`). Note: real m4a reverb is PCM-only and PSG dry; pinyol's lo-fi is global. |
| "sfx_voice has no envelope; looping is whole-clip" | Confirmed. Also no per-voice ramp: `sfx_set` writes `gain` directly (`audio.c:432`) and the mixer uses it constant per 256-sample chunk, so a game fading by `sfx_set` at 60 Hz steps the gain every ~367 samples (zipper noise; audibility unverified). |
| "Lua cannot do vibrato per voice cleanly" | Confirmed: `tone()` has `slide` only (`lua_sound.c:175`); vibrato exists only inside `sound()` and is baked into a clip (`synth.c:75-79`). There is no way to change a playing `tone` (no `tone_set`), unlike `sfx_set`. |
| Music: `.mod` via pocketmod 4 MB cap, 32 channels, ~3 % of a core | Cap and channels confirmed (`modplay.c:21`, `pocketmod.h:16`); the 3 % figure is only in `docs/lua.md:451`, not in `docs/measurements.md` (unverified). |

Things the digest did not say:
- `psg_play` replaces the voice instantly (`psg.c:40`): with `attack = 0` retriggering a sounding voice starts at full amplitude with a phase of 0, a likely click (unverified by ear).
- `tone()` and `sfx()` start at the next audio callback after the game's tick, not on a sample. Only the studio is sample-accurate (`studio.c:101-113`, `wait` samples). The callback size differs per platform (section 3).
- Four PSG voices at `AMP 8000` sum to 32000, above the limiter knee of 23000 (`psg.c:10`, `audio.c:586`): four loud voices are soft-clipped by design.

## 1. Feature matrix

Status: have / partial / missing / better (pinyol exceeds the GBA).

| GBA feature | pinyol equivalent | Status |
|---|---|---|
| CH1 pulse with 4 duty values | `PSG_SQUARE`, float duty 0.01..0.99 (`psg.c:54`, `lua_sound.c:172`) | better (any duty) |
| CH1 frequency sweep (`R +- R/2^n`, per 7.8 ms step) | linear `slide` in Hz/s (`psg.c:89`) | partial (no exponential sweep; arguably better for effects) |
| CH2 pulse | same voices (any of 4 can be a pulse) | have (the GBA has only 2 pulses; pinyol 4 of anything) |
| CH3 programmable 32 x 4-bit wave RAM | 5 fixed waves, one is sine (`psg.c:51-60`); no user table | missing |
| CH4 noise, 15-bit and 7-bit LFSR, divisor table | 15-bit LFSR, one new value per period (`psg.c:83-87`); pitch = `freq` directly | partial (no 7-bit "metallic" mode) |
| 4-bit volume, stepped 64 Hz hardware envelope | continuous exponential ADSR (`psg.c:70-78`) | partial (smoother, not authentic) |
| Length counter | `len` option (`psg.c:68`, `lua_sound.c:174`) | have |
| 4-bit quantised PSG output | none (only the global 8-bit lo-fi) | missing (cheap) |
| Direct Sound PCM voices (software mixer) | 12 `sfx_voice`s with pitch and gain (`audio.c:626-655`) | have |
| PCM at its own rate per sample | WAVs must be exactly PCM16 mono 22050 Hz (`audio.c:96`); no rate field | partial |
| Root key + note-to-pitch for samples | Lua computes `2^(n/12)` by hand and passes `pitch`; range 1/16..16 (`audio.c:407`) | partial |
| Per-voice ADSR on PCM (m4a voice_directsound) | none; gain only, unramped | missing |
| Loop start/end per sample | whole-clip loop only (`audio.c:640`, `:651`); music streams have `loop_at` (`audio.c:258`) | missing (sfx) |
| Linear interpolation when pitch-shifting | yes (`audio.c:645-646`); no anti-aliasing above pitch 1, like the GBA | have |
| Reverse samples | none | missing (trivial) |
| 4-bit delta compressed samples | none; 1.5 MB RAM cache + 1 MB made-sound cap (`audio.c:22`, `lua_sound.c:12`) | missing, not needed (PSRAM) |
| Key-split / drum-kit voice groups | `studio.track{sound, choke}` gives a drum grid with choke groups (`lua_studio.c:38`) | partial (no key->sample map) |
| Pan / stereo | mono everywhere (the console duplicates to both I2S slots, `audio_out.c:107`) | n/a by design |
| Voice priority and channel stealing | PCM: nearest-to-end rule (`audio.c:409-414`); PSG: voice index chosen by the game | partial |
| Sequencer (MIDI-like tracks, tempo, loops) | studio: 16 tracks x 64 steps, swing, choke, queued patterns on the bar, sample-accurate (`studio.c`) | better for steps; missing for free-length notes on sample tracks |
| Tracker music (Maxmod/Krawall class) | `.mod` through pocketmod (`modplay.c`); no S3M/XM/IT | partial |
| Vibrato / tremolo / bend per track | none on `tone`; vibrato only baked into `sound()` | missing |
| Game-driven music changes (`memacc`) | `music_layer` quantised to bar lines (`audio.c:268-277`), `studio.steps(..., next_bar)`, `music.json` director (`music.c`) | better |
| m4a reverb (two taps, PCM only) | `studio.fx{reverb="gba"}` (`studio_fx.c:134`) | partial (studio tracks only) |
| Pseudo-echo release tail | none | missing (low value) |
| Mixer rate / bit-depth modes (5734..42048 Hz, 9..6 bit) | one fixed lo-fi: 13379 Hz, 8 bit (`studio_fx.c:166`) | partial |
| Hard clip at 10 bits | soft-knee limiter (`audio.c:585`) | better |
| 60 Hz tick sequencing | sample-accurate; `music_time()` and `studio.pos()` follow the speaker (`audio.c:517`) | better |
| (no GBA equivalent) filters, echo, plate reverb, sfxr recipes, acid synth voice, microphone | `sound()` (`synth.c`), `studio.synth` (`studio_synth.c`), `studio.fx`, `mic()` | better |

## 2. Reachable from Lua vs studio-only

Reachable from game Lua today (`lua_sound.c`, `lua_studio.c`):
- `sfx(id, gain, {pitch, loop})`, `sfx_set(h, {gain, pitch})`, `sfx_stop`, `sfx_on`; `volume(v)`; `music(id)` (.mod or .wav stems), `music_layer`, `music_time`; `sound(id, recipe|numbers)` rendering up to 4 s into a clip; `tone(voice, note, {wave, vol, duty, attack, decay, sustain, len, release, slide})`, `note(name)`; `mic`, `mic_record`.
- The whole studio is Lua-visible: `studio.tempo/length/track/steps/play/stop/pos/hit/synth/notes/note/fx` (`lua_studio.c:200-206`). Reverb, echo, the GBA reverb and Lo-fi are therefore reachable, but only through this API.

Studio-only (not reachable by any other sound source):
- Echo and both reverbs (plate, GBA): fed only by track sends (`studio.c` `send_d/send_r`); `sfx`, `tone`, `.mod`, ambience and music streams bypass them (`audio.c:626-661`).
- The acid synth voice (`studio.synth`/`studio.notes`): 16 tracks max, one note at a time per track, 2 waves (saw, square) (`studio_synth.h`).
- Choke groups, swing, queued patterns, sample-accurate step starts (`wait` samples).
- Per-track `pitch` for samples; free-length pitched sample notes are not expressible (only the track's fixed pitch).

Reachable by data (not Lua): `music.json` cues, layers, ducking, ambient events (`music.c`).

Not reachable at all: sample loop points, voice envelopes, PSG sends, voice priority, mixer rate/bit modes other than 13379/8.

What a game author can do today for "instrument" sounds: `sfx(id, g, {pitch = 2^(n/12), loop = true})` and fade with `sfx_set` at 60 Hz. Works (`examples/sonidos` toys "Theremin" and "Motor" do exactly this), but there is no attack/release shaping, loops are whole-clip, and note starts are tick-quantised.

## 3. Mixing facts

| Item | Value | Source |
|---|---|---|
| Output rate / format | 22050 Hz, mono PCM16 everywhere; WAV assets must match | `bp.h:12`, `audio.c:96` |
| Mixer chunk | 256 samples (11.6 ms); `audio_mix` loops chunks | `audio.c:18` |
| Console block | 256 samples per mix task iteration; I2S stereo duplicate; 6 DMA descriptors x 256 = 1536 samples = 70 ms queued; `auto_clear` on underrun | `firmware/main/audio_out.c:30, 125-126`, `:174` |
| Desktop (SDL) callback | 512 samples (23 ms); latency reported as block + block/2 | `platform/sdl/main.c:549, 69-76` |
| Browser callback | 2048 samples (93 ms), mixed on the main thread; latency from the AudioContext | `platform/sdl/main.c:547` |
| libretro | latency fixed at 64 ms | `platform/libretro/libretro.c:51` |
| Voices | 12 PCM `sfx_voice`; 4 PSG; 16 studio tracks (sample or synth, 1 voice each); up to 3 ambience + 1 music + 2 voice-line streams; 1 `.mod` (up to 32 channels) | `audio.c:19, 63`; `psg.c`; `studio.c` |
| Streams | ambience 3 slots (mono), music 1 (up to 3 interleaved stems, `MAX_STEMS`), voice 2; read from the SD in the audio thread | `audio.c:63`, `bp.h:13` |
| RAM | clip cache budget 1.5 MB (48 clips, evict LRU, `made` clips never evicted); made sounds at most 1 MB; echo buffer 1.5 s float = ~132 KB in PSRAM; plate 16-bit buffers ~18 KB in internal RAM on the console; GBA reverb 5.2 KB; `.mod` file up to 4 MB in RAM | `audio.c:22-23`, `lua_sound.c:12`, `studio_fx.c:20-35` |
| Effects idle | effects stop costing after 8 s with nothing sent | `studio_fx.c:37, 151-153` |
| CPU cost, documented | `docs/measurements.md` has no audio figure: it says "Not measured yet: audio mixing and Lua running at the same time" (line 72) and "0 audio underruns" in the editor autotest (line 185). `docs/lua.md:451` claims ~3 % of a core for `.mod`. `studio_fx.c:8-12` records that the plate from PSRAM cost "a fifth of a core" before moving to internal RAM | cited |
| Measurement hook that exists | the firmware accumulates `audio_out_mix_us` / `audio_out_blocks` / `audio_out_underruns` and prints a percentage (`firmware/main/main.c:182`); nobody has written the number into the docs | `audio_out.c:46-47` |
| Cost estimates (all unmeasured) | one voice-sample ~30-60 cycles (float, interpolation, envelope): 22050 x 45 = ~1 Mcycles/s = ~0.4 % of a 240 MHz core per busy voice; 12 + 4 busy voices ~6-7 % of a core, `.mod` +3 % (documented), studio synth voices are heavier (SVF, per-8-sample coefficients, `powf`/`tanf` on filter motion, `studio_synth.c:88-99`) | estimate |
| Double-precision | the ESP32-S3 has a single-precision FPU only; `studio.c:56` computes step positions in `double` (software on the console, once per step, so cheap) | `studio.c:56`, `studio_fx.c:155-156` comment |

## 4. Ranked additions (at most 8)

Costs are estimates for the ESP32-S3 (240 MHz, 4.0 M cycles per 60 fps frame per `docs/measurements.md:12`) unless noted; nothing here was measured.

### 1. `instrument()`: sample voices with root key, loop points, ADSR (value 5/5)
- What: turns any WAV into a playable instrument with envelope and sustain; the missing piece for "GBA music from small samples" and the base for items 5-7.
- Cost: per voice +1 envelope state (3 floats + stage + 2 ints = ~28 B), ~10-15 extra cycles per sample => ~0.1-0.15 % of a core per voice (estimate); sample RAM is the existing clip cache (pin like studio tracks do, `audio_clip_pin`, `audio.c:450`); a 22 kHz 1 s sample is 44 KB, so budget by sample length; this raises pressure on the 1.5 MB cache.
- API sketch (Lua):
  ```lua
  local pad = instrument{ sample = "PAD", root = "C4",            -- the pitch the recording is at
                          loop = {from = 0.12, to = 0.80},        -- seconds, rounded to samples at load
                          adsr = {a = 0.01, d = 0.2, s = 0.6, r = 0.4}, gain = 0.8 }
  local h = pad:play("E4", 0.9)       -- note name or MIDI, velocity 0..1; returns a handle
  pad:release(h)                      -- enters release; sfx_stop(h) still cuts
  sfx_set(h, {pitch = 1.01})          -- existing handle calls keep working
  ```
  Implementation outline: new fields in `sfx_voice` (`audio.c:52-61`): `loop_from/loop_to`, `env`, `stage`, rates; a per-voice pitch ratio `2^((note-root)/12)` computed on the game thread. Also ramp `gain` per sample (fixes the zipper issue in section 0) and add an optional `priority`.
- Dependencies: none. Items 5, 6, 7 build on it.

### 2. Reach the existing sends: `reverb`/`echo` on `sfx`, `tone`, instruments, plus global amount (value 3-4/5, cost near zero)
- What: `sfx_voice` already carries `send_d`/`send_r` (`audio.c:60`); only the Lua surface and `audio_sfx_play` hard-code 0. Gives the "tunnel" to sample/PSG sources without a studio track; the m4a reverb is global and PCM-only, so also offer a bus-wide amount.
- Cost: zero extra RAM (buffers exist); CPU = the two taps per sample when active (GBA mode: 2 reads + 1 write, ~20 cycles/sample, ~0.2 % of a core, estimate; plate: unmeasured since the move to internal RAM, `studio_fx.c:8-12`). The effect wakes only while something sends to it (`studio_fx.c:147-152`).
- API sketch:
  ```lua
  studio.fx{reverb = "gba", size = 0.5}                -- unchanged
  sfx("BELL", 1, {reverb = 0.4, echo = 0.2})           -- per sound
  tone(0, "C5", {wave = "square", reverb = 0.3})       -- per PSG voice (needs send fields in psg.c)
  reverb_bus{music = 0.2, sfx = 0.3, tones = 0.1}      -- optional global sends, m4a style
  ```
- Dependencies: none (works with 1 when it exists). Caveat: `.mod`/streams need a bus-level send, not per-voice.

### 3. Programmable wave voice (CH3) (value 4/5, trivial)
- What: user wavetable for bass, bells, organ: the timbre `psg.c` lacks.
- Cost: 32 bytes per voice and one table lookup per sample (~+5 cycles).
- API sketch: `tone(1, "C2", {wave = {0,2,4,6,8,10,12,14,15,14,...}, vol = 0.5, steps = 4})` (32 values 0..15; table length 32 or 64; `steps` quantises volume to GBA's 4 levels). Store as `uint8_t[32]` copied at `psg_play` so later Lua edits do not race the audio thread.
- Dependencies: none.

### 4. Authentic PSG options (value 3/5, trivial)
- What: switches for the GBA flavour: 12.5/25/50/75 % duty snap, 7-bit LFSR ("metallic" noise), stepped 4-bit envelope at 64 Hz, optional 4-bit output, hardware-style sweep.
- Cost: negligible (`psg.c` branches; a 7-bit LFSR is a different feedback width).
- API sketch: `tone(3, 8000, {wave = "noise", lfsr = 7, steps = true, bits = 4})`; `tone(0, "A4", {sweep = {time = 3, shift = 2, dir = -1}})`.
- Dependencies: none; combine with 3 in one pass over `psg.c`.

### 5. Per-voice modulation: vibrato, bend, tremolo and `tone_set` (value 4/5)
- What: m4a's track `mod`/`bend`; lets Lua do expression without writing a value per 17 ms tick. Add a `tone_set(voice, {pitch, vol, bend})` to match `sfx_set`.
- Cost: one LFO per voice (integer phase, table lookup): ~+8 cycles per sample (~0.1 % per voice, estimate); a few floats per voice.
- API sketch:
  ```lua
  tone(0, "A4", {vibrato = {depth = 25, speed = 5.5, delay = 0.2}})   -- cents, Hz, s
  tone_set(0, {bend = 2})                                              -- semitones
  h = pad:play("E4", 1, {vibrato = {depth = 20, speed = 6}})           -- same table for instruments
  ```
- Dependencies: ideally after 1 (shared LFO code in the sample voice); independent for `tone`.

### 6. Sample-accurate scheduling from Lua (value 4/5 for rhythm and tight sfx, cost near zero)
- What: `sfx_voice` already supports `wait` samples (`audio.c:405`, used by the studio). Expose it so a game can say "play this exactly at `music_time() + 0.25`" instead of landing on the next callback (11.6 ms console, 23 ms desktop, 93 ms browser jitter).
- Cost: none beyond a field; needs a conversion from `music_time` seconds to a sample offset in the locked region (the mark clock exists: `audio.c:507-536`).
- API sketch: `sfx("HAT", 0.7, {at = music_time() + 0.250})` or `{delay = 0.05}`; same for `tone`/`pad:play`.
- Dependencies: none (best with 1). A shared sample-time base across platforms is the only subtlety.

### 7. Key-split and drum-kit instruments (value 3/5)
- What: m4a voice types 0x40 / 0x80 as data: key -> instrument.
- Cost: a 128-entry byte table per kit (128 B); no CPU.
- API sketch: `local kit = drumkit{[36] = kick, [38] = snare, [42] = {hat, choke = 1}}`; `kit:play(38, 0.8)`; `studio.notes` could play a kit on a sample track.
- Dependencies: 1.

### 8. Selectable Lo-fi rate/bits and rate-scaled reverb taps (value 2/5)
- What: `SOUND_MODE_FREQ_*` equivalent; the m4a echo time follows the mix rate (digest 5.6) so the same lo-fi switch should move the GBA taps.
- Cost: none; the held-sample loop already exists (`studio_fx.c:164-169`).
- API sketch: `studio.fx{lofi = {rate = 10512, bits = 8}}` (true = 13379/8 for compatibility); `reverb = "gba"` taps scaled by `rate / 13379`.
- Dependencies: reads well after 2 (global reverb); independent technically.

Skipped on purpose (value below cost, or wrong for this device): pan/stereo (mono speaker), 4-bit delta compression (PSRAM is plentiful), S3M/XM/IT (new dependency, licence unchecked: unverified), pseudo-echo, 60 Hz sequencer quantisation (pinyol's sample-accuracy is better).

## 5. Risks: determinism across desktop, browser, console

Requirement: the same game folder must sound the same everywhere. Realistic target: perceptually identical, not bit-identical. State that target in the docs and test for it.

1. libm differences. Audio uses `sinf`, `expf`, `powf`, `exp2f`, `tanf` (`psg.c:32, 37-38, 104`; `synth.c:61`; `studio_synth.c:49, 66, 90-95`). glibc, Apple libm, emscripten's musl-based libm and newlib on the ESP differ by up to 1 ulp. Recursive paths (SVF, plate reverb, exponential envelopes, feedback) can carry this but at ~1e-7 relative: inaudible (unverified by listening). Mitigation: new features should use tables built from integer math or compute at load with `double`, and avoid per-sample transcendentals.
2. Fused multiply-add and contraction. Only `lua_physics.c` is built with `-ffp-contract=off` (`CMakeLists.txt:44-46`); audio files use the compiler default, so AArch64 (Mac), Xtensa (`madd.s`) and x86/wasm builds can round differently. Same order of magnitude as point 1. A single unit-wide `-ffp-contract=off` for audio sources would remove one variable cheaply (needs a build check; unverified cost).
3. Structure must be integer-exact. Any quantity that decides length or position (loop points, note on/off sample, ADSR stage boundaries, `wait` offsets, `synth_render` length `(int)((a+s+d)*AUDIO_HZ)` at `synth.c:62`) is computed in float today; a one-sample difference moves loop seams or clip length across platforms. For new APIs convert seconds to integer samples once, on the game thread, with an explicit rounding rule, and run state machines in integers.
4. Unseeded or libc-dependent randomness. Variant choice uses `rand()` (`audio.c:395`): different generators per libc, and not tied to the game's seed; whether the engine seeds it is unverified. The noise in `psg.c` and `synth.c` is integer LFSR/xorshift and exact (good, keep it). New random features should use the xorshift already in `synth.c:24`.
5. Callback-size dependent timing. Parameter changes land between callbacks: 256 samples (console), 512 (desktop), 2048 (browser) (`audio_out.c:30`, `sdl/main.c:547-549`), so `tone()`/`sfx()` onsets and `sfx_set` steps jitter by up to 11.6 / 23 / 93 ms, and the latency differs (70 / ~35 / browser-reported ms). Pitches and timbres are identical; "feel" is not. Item 6 (scheduling against `music_time()`) is the fix; until then document that `tone`/`sfx` are not sample-accurate and only the studio is.
6. Real-time budget differs, not the sound. On the console an over-budget mix produces silence (underrun, `auto_clear`), on desktop it glitches, in the browser the mixer shares the main thread with the game. More voices raise this risk on the console first. No audio CPU number exists in the docs: measure with the existing `audio_out_mix_us` counter before and after each addition and record it in `docs/measurements.md`.
7. Memory budgets are identical constants (cache 1.5 MB, made 1 MB) so eviction is deterministic across platforms; instruments that pin large samples can starve the cache everywhere equally. Count pinned instrument samples in a documented budget, and decide whether to refuse or warn on overflow.
8. Asset rate contract. WAVs must be exactly 22050 Hz mono PCM16 (`audio.c:96`); a per-sample rate field would force a resampler. If ever added, do it offline or with a fixed integer-ratio method, never with float `powf` at load time on the device.
9. Lo-fi and reverb state. Both live in the audio thread and clear on idle (`studio_fx.c:149-153`); a game that depends on a tail longer than 8 s of silence will differ from one that keeps sending. Low risk, worth a line in the docs.
10. Test gap. `tests/psg_test.c`, `synth_test.c`, `studio_test.c` check ranges and repeatability on one machine (e.g. `synth_test.c:35`: "the same twice"), not cross-platform equality. Add a golden render per feature (fixed seed, fixed block size) compared with a tolerance (e.g. RMS error below about -60 dBFS) on desktop, wasm and, where possible, the console.

## 6. Suggested order

1 (with the gain ramp) -> 2 and 6 (both nearly free, existing fields) -> 3 + 4 in one `psg.c` pass -> 5 -> 7 -> 8. Take the CPU measurement first (section 3, "Measurement hook") so each step has a before/after.
