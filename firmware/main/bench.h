#pragma once

/* -DBP_BENCH=ON: measure the pieces of a GBA-like software renderer on the board, log them, show the result (bench.c). */
void bench_run(void);
/* -DBP_BENCH=v1: how long the v1 engine takes to draw each zone of the games on the card. */
void bench_v1_run(void);
