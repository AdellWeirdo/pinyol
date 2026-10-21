/* One colour mixed into a run of pixels next to each other in memory (gfx_span.c) */
#pragma once
#include <stdbool.h>
#include <stdint.h>

#include "bp.h"

/* p[0..n): mixed with c (RGB565 as it is) by mode (BLEND_ALPHA, ADD, SUB, QUARTER) at alpha 0..256, as gfx_quad.c's mixed_run
 * mixes; swap: p holds its pixels byte-swapped. Not for canvases (it does not look for CANVAS_KEY). */
void span_mix_const(uint16_t *p, int n, uint16_t c, unsigned alpha, int mode, bool swap);
void span_mix_const_c(uint16_t *p, int n, uint16_t c, unsigned alpha, int mode, bool swap); /* the C one, everywhere */
