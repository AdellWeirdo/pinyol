#pragma once

/* -DBP_BENCH=ON: measure the pieces of a GBA-like software renderer on the board, log them, show the result (bench.c). */
void bench_run(void);
/* -DBP_BENCH=v1: how long the v1 engine takes to draw each zone of the games on the card. */
void bench_v1_run(void);
/* -DBP_BENCH=ppu: the real ppu_render (src/ppu.c) on the board, the scenes of the host harness (bench_ppu.c). */
void bench_ppu_run(void);
/* -DBP_BENCH=audio: the share of a core the sound takes, for voices, instruments, tones and reverb (bench_audio.c). */
void bench_audio_run(void);
