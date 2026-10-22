#include "mesh.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

#define OT_LEN 256        /* ordering table slots (a PlayStation's own were of this order) */
#define LIMIT 1900.0f     /* a corner farther than this from the screen's origin makes the face too big for quad() (it takes +-2000) */

struct mesh_model {
    int nv, nf;
    float *verts;         /* nv x 3 */
    uint16_t *idx;        /* nf x 4 */
    int16_t *uv;          /* nf x 8, eighths of a texel, or NULL */
    float *cam;           /* scratch: each vertex in camera space (x, y, z), then on the screen (sx, sy) */
    float *zf;            /* scratch: each face's depth */
    int16_t *slot;        /* scratch: each face's ordering table slot, or -1: not shown */
    uint16_t *next;       /* scratch: the next face in its slot */
};

mesh_model *mesh_model_new(const float *verts, int nv, const uint16_t *idx, const float *uv, int nf) {
    if (nv < 1 || nv > MESH_MAX_VERTS || nf < 1 || nf > MESH_MAX_FACES) return NULL;
    for (int i = 0; i < nf * 4; i++)
        if (idx[i] >= nv) return NULL;
    mesh_model *m = calloc(1, sizeof *m);
    if (!m) return NULL;
    m->nv = nv, m->nf = nf;
    m->verts = malloc((size_t)nv * 3 * sizeof(float));
    m->idx = malloc((size_t)nf * 4 * sizeof(uint16_t));
    m->uv = uv ? malloc((size_t)nf * 8 * sizeof(int16_t)) : NULL;
    m->cam = malloc((size_t)nv * 5 * sizeof(float));
    m->zf = malloc((size_t)nf * sizeof(float));
    m->slot = malloc((size_t)nf * sizeof(int16_t));
    m->next = malloc((size_t)nf * sizeof(uint16_t));
    if (!m->verts || !m->idx || (uv && !m->uv) || !m->cam || !m->zf || !m->slot || !m->next) return mesh_model_free(m), NULL;
    memcpy(m->verts, verts, (size_t)nv * 3 * sizeof(float));
    memcpy(m->idx, idx, (size_t)nf * 4 * sizeof(uint16_t));
    for (int i = 0; uv && i < nf * 8; i++) m->uv[i] = (int16_t)floorf(fminf(fmaxf(uv[i], -2000.0f), 2000.0f) * 8 + 0.5f);
    return m;
}

void mesh_model_free(mesh_model *m) {
    if (!m) return;
    free(m->verts), free(m->idx), free(m->uv), free(m->cam), free(m->zf), free(m->slot), free(m->next);
    free(m);
}

/* Rx * Ry * Rz */
static void rotation(const float deg[3], float r[3][3]) {
    const float k = 3.14159265f / 180.0f;
    const float sx = sinf(deg[0] * k), cx = cosf(deg[0] * k), sy = sinf(deg[1] * k), cy = cosf(deg[1] * k);
    const float sz = sinf(deg[2] * k), cz = cosf(deg[2] * k);
    const float X[3][3] = {{1, 0, 0}, {0, cx, -sx}, {0, sx, cx}}, Y[3][3] = {{cy, 0, sy}, {0, 1, 0}, {-sy, 0, cy}},
                Z[3][3] = {{cz, -sz, 0}, {sz, cz, 0}, {0, 0, 1}};
    float t[3][3];
    for (int i = 0; i < 3; i++)
        for (int j = 0; j < 3; j++) t[i][j] = X[i][0] * Y[0][j] + X[i][1] * Y[1][j] + X[i][2] * Y[2][j];
    for (int i = 0; i < 3; i++)
        for (int j = 0; j < 3; j++) r[i][j] = t[i][0] * Z[0][j] + t[i][1] * Z[1][j] + t[i][2] * Z[2][j];
}

static int16_t eighths(float v) { return (int16_t)floorf(v * 8 + 0.5f); }

int mesh_build(mesh_model *m, const mesh_params *p, mesh_face *out, int max, int bbox[4]) {
    bbox[0] = bbox[1] = 32767, bbox[2] = bbox[3] = -32768;
    if (max < 1) return 0;
    float r[3][3];
    rotation(p->rot, r);
    for (int i = 0; i < m->nv; i++) { /* each vertex once: into camera space, then onto the screen */
        const float *v = &m->verts[3 * i];
        float *c = &m->cam[5 * i];
        for (int k = 0; k < 3; k++) c[k] = (r[k][0] * v[0] + r[k][1] * v[1] + r[k][2] * v[2]) * p->scale + p->pos[k];
        if (c[2] >= p->near && c[2] > 1e-6f) c[3] = p->cx + c[0] * p->focal / c[2], c[4] = p->cy + c[1] * p->focal / c[2];
        else c[3] = c[4] = NAN; /* behind the near plane */
    }
    int shown = 0;
    float zmin = INFINITY, zmax = -INFINITY;
    for (int f = 0; f < m->nf; f++) {
        const uint16_t *ix = &m->idx[4 * f];
        const float *c[4] = {&m->cam[5 * ix[0]], &m->cam[5 * ix[1]], &m->cam[5 * ix[2]], &m->cam[5 * ix[3]]};
        m->slot[f] = -1;
        bool ok = true;
        for (int k = 0; k < 4; k++) ok = ok && !isnan(c[k][3]) && fabsf(c[k][3]) < LIMIT + 480 && fabsf(c[k][4]) < LIMIT + 320;
        if (!ok) continue;
        const float area = (c[1][3] - c[0][3]) * (c[2][4] - c[0][4]) - (c[1][4] - c[0][4]) * (c[2][3] - c[0][3]);
        if (p->cull && area <= 0) continue;
        m->zf[f] = (c[0][2] + c[1][2] + c[2][2] + c[3][2]) * 0.25f;
        zmin = fminf(zmin, m->zf[f]), zmax = fmaxf(zmax, m->zf[f]);
        m->slot[f] = 0, shown++;
    }
    if (!shown) return 0;
    int head[OT_LEN];
    for (int s = 0; s < OT_LEN; s++) head[s] = -1;
    const float span = zmax - zmin;
    for (int f = m->nf - 1; f >= 0; f--) { /* an ordering table: each face in the slot of its depth, the lists in face order */
        if (m->slot[f] < 0) continue;
        const int s = span > 1e-6f ? (int)((m->zf[f] - zmin) / span * (OT_LEN - 1) + 0.5f) : 0;
        m->slot[f] = (int16_t)s, m->next[f] = (uint16_t)(head[s] < 0 ? 0xFFFF : head[s]), head[s] = f;
    }
    int skip = shown > max ? shown - max : 0; /* too many: the farthest are the ones to go */
    int n = 0;
    for (int s = OT_LEN - 1; s >= 0; s--) {
        for (int f = head[s]; f >= 0; f = m->next[f] == 0xFFFF ? -1 : m->next[f]) {
            if (skip > 0) {
                skip--;
                continue;
            }
            const uint16_t *ix = &m->idx[4 * f];
            const float *c[4] = {&m->cam[5 * ix[0]], &m->cam[5 * ix[1]], &m->cam[5 * ix[2]], &m->cam[5 * ix[3]]};
            mesh_face *o = &out[n++];
            for (int k = 0; k < 4; k++) {
                float sx = c[k][3], sy = c[k][4];
                if (p->snap) sx = floorf(sx + 0.5f), sy = floorf(sy + 0.5f);
                o->xy[2 * k] = eighths(sx), o->xy[2 * k + 1] = eighths(sy);
                bbox[0] = (int)floorf(sx) - 1 < bbox[0] ? (int)floorf(sx) - 1 : bbox[0];
                bbox[1] = (int)floorf(sy) - 1 < bbox[1] ? (int)floorf(sy) - 1 : bbox[1];
                bbox[2] = (int)ceilf(sx) + 2 > bbox[2] ? (int)ceilf(sx) + 2 : bbox[2];
                bbox[3] = (int)ceilf(sy) + 2 > bbox[3] ? (int)ceilf(sy) + 2 : bbox[3];
            }
            o->uv = m->uv ? &m->uv[8 * f] : NULL, o->mip = NULL;
            float level = 128;
            if (p->lit) { /* the face's normal in camera space, turned to face the camera, against the light */
                const float ux = c[1][0] - c[0][0], uy = c[1][1] - c[0][1], uz = c[1][2] - c[0][2];
                const float vx = c[2][0] - c[0][0], vy = c[2][1] - c[0][1], vz = c[2][2] - c[0][2];
                float nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
                const float len = sqrtf(nx * nx + ny * ny + nz * nz);
                if (len > 1e-9f) {
                    nx /= len, ny /= len, nz /= len;
                    if (nx * c[0][0] + ny * c[0][1] + nz * c[0][2] > 0) nx = -nx, ny = -ny, nz = -nz;
                    const float k = fmaxf(0, p->light_dir[0] * nx + p->light_dir[1] * ny + p->light_dir[2] * nz);
                    level = fminf(255, floorf((p->ambient + p->gain * k) * 256));
                } else level = fminf(255, floorf(p->ambient * 256));
            }
            if (p->fade) {
                const float d = p->fade1 - p->fade0;
                const float k = d > 1e-6f ? (p->fade1 - m->zf[f]) / d : (m->zf[f] < p->fade1 ? 1.0f : 0.0f);
                level *= fminf(1, fmaxf(0, k));
            }
            o->light[0] = o->light[1] = o->light[2] = (uint8_t)level;
        }
    }
    return n;
}
