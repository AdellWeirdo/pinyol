/* mesh.c: a cube turned, projected, culled, sorted and lit: how many faces show, whole pixels with snap, the lamp and the fade, the
 * ordering table (far to near), at most `max` faces (the nearest kept), the model's own checks. */
#include <math.h>
#include <stdio.h>
#include <string.h>

#include "mesh.h"

static int fails;
#define CHECK(c) do { if (!(c)) { printf("mesh_test: %s (line %d)\n", #c, __LINE__); fails++; } } while (0)

static const float V[8][3] = {{-100,-100,-100},{100,-100,-100},{-100,100,-100},{100,100,-100},{100,-100,100},{-100,-100,100},{100,100,100},{-100,100,100}};
static const uint16_t F[6][4] = {{0,1,3,2},{4,5,7,6},{5,4,1,0},{6,7,2,3},{0,2,7,5},{3,1,4,6}}; /* quad() corner order */

static mesh_params params(void) {
    return (mesh_params){.pos = {0, 0, 400}, .scale = 1, .focal = 213.33f, .cx = 240, .cy = 160, .near = 1, .cull = true,
                         .light_dir = {-0.5f, -0.5f, -0.5f}, .ambient = 0.25f, .gain = 0.75f};
}

int main(void) {
    mesh_model *m = mesh_model_new(&V[0][0], 8, &F[0][0], NULL, 6);
    CHECK(m);
    mesh_face out[8];
    int box[4];
    mesh_params p = params();

    CHECK(mesh_build(m, &p, out, 8, box) == 1);                         /* face on: one face of six */
    CHECK(box[0] < 240 && box[2] > 240 && box[1] < 160 && box[3] > 160); /* around the centre */
    p.cull = false;
    CHECK(mesh_build(m, &p, out, 8, box) == 6);                         /* every face, culled or not */
    p.cull = true;

    p.rot[0] = 40, p.rot[1] = 25, p.rot[2] = 10;
    const int n = mesh_build(m, &p, out, 8, box);
    CHECK(n >= 2 && n <= 3);                                            /* a turned cube shows two or three faces */
    p.snap = true;
    CHECK(mesh_build(m, &p, out, 8, box) == n);
    for (int i = 0; i < n; i++)
        for (int k = 0; k < 8; k++) CHECK(out[i].xy[k] % 8 == 0);        /* snap: whole pixels */
    p.snap = false;

    CHECK(mesh_build(m, &p, out, 1, box) == 1);                         /* max: one face, the nearest */
    p.cull = false;                                                     /* all six: far to near, so a near one is last */
    mesh_face all[8];
    CHECK(mesh_build(m, &p, all, 8, box) == 6);
    mesh_face last;
    CHECK(mesh_build(m, &p, &last, 1, box) == 1 && !memcmp(last.xy, all[5].xy, sizeof last.xy));
    p.cull = true;

    p.rot[0] = p.rot[1] = p.rot[2] = 0;                                 /* lit: the front face's normal is (0, 0, -1): light . n = 0.5 */
    p.lit = true;
    CHECK(mesh_build(m, &p, out, 8, box) == 1);
    CHECK(out[0].light[0] == (uint8_t)floorf((0.25f + 0.75f * 0.5f) * 256) && out[0].light[0] == out[0].light[2]);
    p.light_dir[0] = p.light_dir[1] = p.light_dir[2] = 0;               /* no lamp: ambient only */
    CHECK(mesh_build(m, &p, out, 8, box) == 1 && out[0].light[0] == 64);
    p.lit = false, p.fade = true, p.fade0 = 0, p.fade1 = 400;           /* fade: z 300 of 0..400, a quarter of the light left... */
    CHECK(mesh_build(m, &p, out, 8, box) == 1 && out[0].light[0] == 32); /* ...of the unlit 128 */
    p.fade = false;

    p.pos[2] = 50;                                                      /* a corner behind the near plane: no face */
    p.cull = false;
    CHECK(mesh_build(m, &p, out, 8, box) <= 5);
    p.pos[2] = -500;
    CHECK(mesh_build(m, &p, out, 8, box) == 0);
    p.pos[2] = 400, p.cull = true;

    const float uv[6 * 8] = {0, 0, 64, 0, 64, 64, 0, 64};               /* the model's own uv: eighths of a texel */
    float uvs[6 * 8];
    for (int f = 0; f < 6; f++) memcpy(&uvs[8 * f], uv, sizeof uv[0] * 8);
    mesh_model *u = mesh_model_new(&V[0][0], 8, &F[0][0], uvs, 6);
    CHECK(u && mesh_build(u, &p, out, 8, box) == 1 && out[0].uv && out[0].uv[2] == 512 && out[0].uv[5] == 512);
    CHECK(mesh_build(m, &p, out, 8, box) == 1 && out[0].uv == NULL);

    uint16_t bad[4] = {0, 1, 2, 8};
    CHECK(mesh_model_new(&V[0][0], 8, bad, NULL, 1) == NULL);           /* a vertex that is not there */
    CHECK(mesh_model_new(&V[0][0], 0, F[0], NULL, 1) == NULL && mesh_model_new(&V[0][0], 8, F[0], NULL, 0) == NULL);

    mesh_model_free(m), mesh_model_free(u), mesh_model_free(NULL);
    if (!fails) puts("mesh_test: ok");
    return fails != 0;
}
