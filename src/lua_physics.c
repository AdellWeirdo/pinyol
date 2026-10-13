/* The heavy part of lib/physics.lua for bodies that turn, in C: on the console Lua took 32 ms a tick for ten boxes.
 * One call per substep, from World:step:
 *
 *   physics_turning(bodies, iterations, bounce_min, push_back, slop, substeps) -> hits {{a, b, speed}, ...}
 *
 * It finds where bodies touch when one of them turns (circles, boxes, convex polygons: the faces they press on,
 * clipped to one or two points, as Box2D-lite), works out the pushes between them (sequential impulses, accumulated
 * and warm-started from the last substep, a Baumgarte push out of overlaps, a bounce only above bounce_min), then
 * moves the bodies that turn. Bodies that do not turn are left to the Lua code (lib/physics.lua), which also moved
 * them already: here they are only something to push against (and they take the push back). */
#include <math.h>
#include <stdlib.h>

#include "lua_api.h"

#define MAXB 256    /* bodies in a world looked at here */
#define MAXC 16     /* corners of a polygon (physics.lua checks it) */
#define MAXK 512    /* contacts in one substep */
#define DEG (180.0f / 3.14159265f)
#define RAD (3.14159265f / 180.0f)

typedef struct {
    int kind;                  /* 0 circle, 1 box, 2 polygon */
    float x, y, w, h, r;       /* as in Lua: a box's x, y is its top-left corner */
    float cx, cy, vx, vy, spin, angle, inv, iinv, bounce, friction;
    bool turns, touched;
    int n;                     /* corners */
    float v[2 * MAXC], nrm[2 * MAXC];
    float x0, y0, x1, y1;      /* bounds */
} pbody;

typedef struct { float rax, ray, rbx, rby, kn, kt, pn, pt, bias, px, py; } cpoint;
typedef struct { int a, b, np; float nx, ny, depth, mu; cpoint p[2]; } contact;
typedef struct { const void *a, *b; int np; float px[2], py[2], pn[2], pt[2]; } warm_t;

/* ~170 KB, in the slow memory (PSRAM on the console), made the first time a game has a body that turns */
static struct work {
    pbody b[MAXB];
    contact c[MAXK];
    warm_t w[2][MAXK]; /* the last substep's contacts, and this one's */
} *X;
static int nw[2], cur;
#define B (X->b)
#define C (X->c)
#define W (X->w)

void physics_free(void) { free(X), X = NULL, nw[0] = nw[1] = 0; }

static float num_field(lua_State *L, int t, const char *k, float d) {
    lua_getfield(L, t, k);
    float v = lua_isnumber(L, -1) ? fin(lua_tonumber(L, -1)) : d;
    lua_pop(L, 1);
    return v;
}

/* The corners of a box or polygon on the screen, turned about its centre, and each edge's outward normal. */
static void shape(lua_State *L, int t, pbody *b) {
    float lp[2 * MAXC];
    if (b->kind == 1) {
        float hw = b->w / 2, hh = b->h / 2;
        float q[8] = {-hw, -hh, hw, -hh, hw, hh, -hw, hh};
        memcpy(lp, q, sizeof q);
        b->n = 4;
    } else {
        lua_getfield(L, t, "pts");
        int n = lua_istable(L, -1) ? (int)lua_rawlen(L, -1) / 2 : 0;
        if (n > MAXC) n = MAXC;
        for (int i = 0; i < 2 * n; i++) {
            lua_rawgeti(L, -1, i + 1);
            lp[i] = fin(lua_tonumber(L, -1));
            lua_pop(L, 1);
        }
        lua_pop(L, 1);
        b->n = n;
    }
    float a = b->angle * RAD, c = cosf(a), s = sinf(a);
    b->x0 = b->y0 = 1e30f, b->x1 = b->y1 = -1e30f;
    for (int i = 0; i < b->n; i++) {
        float x = lp[2 * i], y = lp[2 * i + 1], wx = b->cx + x * c - y * s, wy = b->cy + x * s + y * c;
        b->v[2 * i] = wx, b->v[2 * i + 1] = wy;
        if (wx < b->x0) b->x0 = wx;
        if (wx > b->x1) b->x1 = wx;
        if (wy < b->y0) b->y0 = wy;
        if (wy > b->y1) b->y1 = wy;
    }
    for (int i = 0; i < b->n; i++) {
        int j = (i + 1) % b->n;
        float ex = b->v[2 * j] - b->v[2 * i], ey = b->v[2 * j + 1] - b->v[2 * i + 1], l = sqrtf(ex * ex + ey * ey);
        float nx = l > 1e-9f ? ey / l : 0, ny = l > 1e-9f ? -ex / l : 0;
        if ((b->v[2 * i] - b->cx) * nx + (b->v[2 * i + 1] - b->cy) * ny < 0) nx = -nx, ny = -ny;
        b->nrm[2 * i] = nx, b->nrm[2 * i + 1] = ny;
    }
}

static bool read_body(lua_State *L, int t, pbody *b) {
    lua_getfield(L, t, "kind");
    const char *k = lua_tostring(L, -1);
    b->kind = !k ? -1 : !strcmp(k, "circle") ? 0 : !strcmp(k, "box") ? 1 : !strcmp(k, "poly") ? 2 : -1;
    lua_pop(L, 1);
    if (b->kind < 0) return false;
    b->x = num_field(L, t, "x", 0), b->y = num_field(L, t, "y", 0);
    b->vx = num_field(L, t, "vx", 0), b->vy = num_field(L, t, "vy", 0);
    b->inv = num_field(L, t, "inv", 0), b->iinv = num_field(L, t, "iinv", 0);
    b->bounce = num_field(L, t, "bounce", 0.3f), b->friction = num_field(L, t, "friction", 0.4f);
    lua_getfield(L, t, "turns");
    b->turns = lua_toboolean(L, -1);
    lua_pop(L, 1);
    b->spin = b->turns ? num_field(L, t, "spin", 0) : 0, b->angle = b->turns ? num_field(L, t, "angle", 0) : 0;
    b->touched = false;
    if (b->kind == 0) {
        b->r = num_field(L, t, "r", 1);
        b->cx = b->x, b->cy = b->y;
        b->x0 = b->x - b->r, b->y0 = b->y - b->r, b->x1 = b->x + b->r, b->y1 = b->y + b->r;
        b->n = 0;
        return true;
    }
    if (b->kind == 1) {
        b->w = num_field(L, t, "w", 1), b->h = num_field(L, t, "h", 1);
        b->cx = b->x + b->w / 2, b->cy = b->y + b->h / 2;
    } else {
        b->cx = b->x, b->cy = b->y;
    }
    shape(L, t, b);
    return b->n >= 3;
}

/* The least push to part two polygons along one of a's normals, and that edge; false if one separates them. */
static bool least(const pbody *a, const pbody *b, float *depth, int *edge) {
    float best = 1e30f;
    for (int i = 0; i < a->n; i++) {
        float nx = a->nrm[2 * i], ny = a->nrm[2 * i + 1], x1 = a->v[2 * i], y1 = a->v[2 * i + 1], m = 1e30f;
        for (int k = 0; k < b->n; k++) {
            float d = (b->v[2 * k] - x1) * nx + (b->v[2 * k + 1] - y1) * ny;
            if (d < m) m = d;
        }
        if (m > 0) return false;
        if (-m < best) best = -m, *edge = i;
    }
    *depth = best;
    return true;
}

/* The part of segment p-q where (x - o).s >= 0; false if none. */
static bool clip(float *p, float *q, float ox, float oy, float sx, float sy) {
    float dp = (p[0] - ox) * sx + (p[1] - oy) * sy, dq = (q[0] - ox) * sx + (q[1] - oy) * sy;
    if (dp < 0 && dq < 0) return false;
    if (dp < 0 || dq < 0) {
        float t = dp / (dp - dq), x = p[0] + (q[0] - p[0]) * t, y = p[1] + (q[1] - p[1]) * t;
        if (dp < 0) p[0] = x, p[1] = y;
        else q[0] = x, q[1] = y;
    }
    return true;
}

static bool poly_poly(const pbody *a, const pbody *b, contact *c) {
    float da, db;
    int ai = 0, bi = 0;
    if (!least(a, b, &da, &ai) || !least(b, a, &db, &bi)) return false;
    const pbody *ref = a, *inc = b;
    int ri = ai;
    bool flip = false;
    if (db < da * 0.95f - 0.01f) ref = b, inc = a, ri = bi, flip = true;
    float nx = ref->nrm[2 * ri], ny = ref->nrm[2 * ri + 1], most = 1e30f;
    int ii = 0;
    for (int i = 0; i < inc->n; i++) {
        float d = inc->nrm[2 * i] * nx + inc->nrm[2 * i + 1] * ny;
        if (d < most) most = d, ii = i;
    }
    int ij = (ii + 1) % inc->n, rj = (ri + 1) % ref->n;
    float p[2] = {inc->v[2 * ii], inc->v[2 * ii + 1]}, q[2] = {inc->v[2 * ij], inc->v[2 * ij + 1]};
    float r1x = ref->v[2 * ri], r1y = ref->v[2 * ri + 1], r2x = ref->v[2 * rj], r2y = ref->v[2 * rj + 1];
    float tx = r2x - r1x, ty = r2y - r1y, tl = sqrtf(tx * tx + ty * ty);
    tx /= tl, ty /= tl;
    c->np = 0, c->depth = 0;
    if (clip(p, q, r1x, r1y, tx, ty) && clip(p, q, r2x, r2y, -tx, -ty)) {
        const float *pts[2] = {p, q};
        for (int k = 0; k < 2; k++) {
            float sep = (pts[k][0] - r1x) * nx + (pts[k][1] - r1y) * ny;
            if (sep <= 0.01f) {
                c->p[c->np].px = pts[k][0], c->p[c->np].py = pts[k][1], c->np++;
                if (-sep > c->depth) c->depth = -sep;
            }
        }
    }
    if (!c->np) { /* edges crossing, no corner inside: halfway between the two */
        c->p[0].px = (a->cx + b->cx) / 2, c->p[0].py = (a->cy + b->cy) / 2, c->np = 1;
        c->depth = da < db ? da : db;
    }
    c->nx = flip ? -nx : nx, c->ny = flip ? -ny : ny;
    return true;
}

static bool inside(const pbody *b, float px, float py) {
    for (int i = 0; i < b->n; i++)
        if ((px - b->v[2 * i]) * b->nrm[2 * i] + (py - b->v[2 * i + 1]) * b->nrm[2 * i + 1] > 0.01f) return false;
    return true;
}

/* A circle against a polygon: the direction from the circle to the polygon, how deep, where. */
static bool circle_poly(const pbody *o, const pbody *b, contact *c) {
    float best = 1e30f, qx = 0, qy = 0;
    for (int i = 0; i < b->n; i++) {
        int j = (i + 1) % b->n;
        float x1 = b->v[2 * i], y1 = b->v[2 * i + 1], ex = b->v[2 * j] - x1, ey = b->v[2 * j + 1] - y1;
        float l2 = ex * ex + ey * ey, t = l2 > 0 ? ((o->cx - x1) * ex + (o->cy - y1) * ey) / l2 : 0;
        t = t < 0 ? 0 : t > 1 ? 1 : t;
        float px = x1 + ex * t, py = y1 + ey * t, d = (px - o->cx) * (px - o->cx) + (py - o->cy) * (py - o->cy);
        if (d < best) best = d, qx = px, qy = py;
    }
    float dist = sqrtf(best);
    c->np = 1, c->p[0].px = qx, c->p[0].py = qy;
    if (inside(b, o->cx, o->cy)) {
        if (dist < 1e-6f) return c->nx = 0, c->ny = 1, c->depth = o->r, c->p[0].px = o->cx, c->p[0].py = o->cy, true;
        return c->nx = (o->cx - qx) / dist, c->ny = (o->cy - qy) / dist, c->depth = o->r + dist, true;
    }
    if (dist >= o->r || dist < 1e-9f) return false;
    return c->nx = (qx - o->cx) / dist, c->ny = (qy - o->cy) / dist, c->depth = o->r - dist, true;
}

static bool collide(const pbody *a, const pbody *b, contact *c) {
    if (a->kind == 0 && b->kind == 0) {
        float dx = b->cx - a->cx, dy = b->cy - a->cy, d = sqrtf(dx * dx + dy * dy), sum = a->r + b->r;
        if (d >= sum) return false;
        if (d < 1e-6f) c->nx = 0, c->ny = -1;
        else c->nx = dx / d, c->ny = dy / d;
        c->depth = sum - d, c->np = 1;
        c->p[0].px = a->cx + c->nx * a->r, c->p[0].py = a->cy + c->ny * a->r;
        return true;
    }
    if (a->kind == 0) return circle_poly(a, b, c);
    if (b->kind == 0) {
        if (!circle_poly(b, a, c)) return false;
        c->nx = -c->nx, c->ny = -c->ny;
        return true;
    }
    return poly_poly(a, b, c);
}

static void push(pbody *a, pbody *b, const cpoint *p, float jx, float jy) {
    a->vx -= jx * a->inv, a->vy -= jy * a->inv, a->spin -= (p->rax * jy - p->ray * jx) * a->iinv * DEG;
    b->vx += jx * b->inv, b->vy += jy * b->inv, b->spin += (p->rbx * jy - p->rby * jx) * b->iinv * DEG;
}

static void solve(contact *c) {
    pbody *a = &B[c->a], *b = &B[c->b];
    float nx = c->nx, ny = c->ny, tx = -ny, ty = nx, ia = a->inv, ib = b->inv, iia = a->iinv, iib = b->iinv;
    float avx = a->vx, avy = a->vy, aw = a->spin * RAD, bvx = b->vx, bvy = b->vy, bw = b->spin * RAD;
    for (int k = 0; k < c->np; k++) {
        cpoint *p = &c->p[k];
        float rvx = (bvx - bw * p->rby) - (avx - aw * p->ray), rvy = (bvy + bw * p->rbx) - (avy + aw * p->rax);
        float pn = p->pn - (rvx * nx + rvy * ny - p->bias) / p->kn;
        if (pn < 0) pn = 0;
        float d = pn - p->pn, jx = d * nx, jy = d * ny;
        p->pn = pn;
        avx -= jx * ia, avy -= jy * ia, aw -= (p->rax * jy - p->ray * jx) * iia;
        bvx += jx * ib, bvy += jy * ib, bw += (p->rbx * jy - p->rby * jx) * iib;
        rvx = (bvx - bw * p->rby) - (avx - aw * p->ray), rvy = (bvy + bw * p->rbx) - (avy + aw * p->rax);
        float lim = c->mu * pn, pt = p->pt - (rvx * tx + rvy * ty) / p->kt;
        pt = pt > lim ? lim : pt < -lim ? -lim : pt;
        d = pt - p->pt, jx = d * tx, jy = d * ty;
        p->pt = pt;
        avx -= jx * ia, avy -= jy * ia, aw -= (p->rax * jy - p->ray * jx) * iia;
        bvx += jx * ib, bvy += jy * ib, bw += (p->rbx * jy - p->rby * jx) * iib;
    }
    a->vx = avx, a->vy = avy, a->spin = aw * DEG, b->vx = bvx, b->vy = bvy, b->spin = bw * DEG;
}

static int l_physics_turning(lua_State *L) {
    luaL_checktype(L, 1, LUA_TTABLE);
    int iterations = (int)luaL_checkinteger(L, 2), substeps = (int)luaL_checkinteger(L, 6);
    float bounce_min = fin(luaL_checknumber(L, 3)), push_back = fin(luaL_checknumber(L, 4)), slop = fin(luaL_checknumber(L, 5));
    int n = (int)lua_rawlen(L, 1);
    if (n > MAXB) return luaL_error(L, "physics: %d bodies at most in a world with bodies that turn", MAXB);
    if (iterations < 1 || iterations > 32 || substeps < 1) return luaL_error(L, "physics: bad step settings");
    if (!X && !(X = hal_realloc_slow(NULL, sizeof *X))) return luaL_error(L, "physics: out of memory");
    bool any = false;
    for (int i = 0; i < n; i++) {
        lua_rawgeti(L, 1, i + 1);
        if (!read_body(L, lua_gettop(L), &B[i])) B[i].kind = -1;
        any |= B[i].turns && B[i].kind >= 0;
        lua_pop(L, 1);
    }
    lua_newtable(L); /* the hits */
    if (!any) return 1;
    int nc = 0, prev = cur, next = cur ^ 1;
    nw[next] = 0;
    for (int i = 0; i < n; i++) {
        pbody *a = &B[i];
        if (a->kind < 0) continue;
        for (int j = i + 1; j < n && nc < MAXK; j++) {
            pbody *b = &B[j];
            if (b->kind < 0 || !(a->turns || b->turns) || (a->inv <= 0 && b->inv <= 0)) continue;
            if (a->x0 >= b->x1 || b->x0 >= a->x1 || a->y0 >= b->y1 || b->y0 >= a->y1) continue;
            contact *c = &C[nc];
            if (!collide(a, b, c)) continue;
            c->a = i, c->b = j;
            c->mu = sqrtf(a->friction * b->friction);
            float e = a->bounce < b->bounce ? a->bounce : b->bounce, aw = a->spin * RAD, bw = b->spin * RAD;
            const void *pa = (lua_rawgeti(L, 1, i + 1), lua_topointer(L, -1)), *pb = (lua_rawgeti(L, 1, j + 1), lua_topointer(L, -1));
            const warm_t *old = NULL;
            for (int k = 0; k < nw[prev] && !old; k++)
                if (W[prev][k].a == pa && W[prev][k].b == pb) old = &W[prev][k];
            bool hit = false;
            for (int k = 0; k < c->np; k++) {
                cpoint *p = &c->p[k];
                p->rax = p->px - a->cx, p->ray = p->py - a->cy, p->rbx = p->px - b->cx, p->rby = p->py - b->cy;
                float rna = p->rax * c->ny - p->ray * c->nx, rnb = p->rbx * c->ny - p->rby * c->nx;
                float rta = p->rax * c->nx + p->ray * c->ny, rtb = p->rbx * c->nx + p->rby * c->ny; /* r x t, t = (-ny, nx) */
                p->kn = a->inv + b->inv + rna * rna * a->iinv + rnb * rnb * b->iinv;
                p->kt = a->inv + b->inv + rta * rta * a->iinv + rtb * rtb * b->iinv;
                p->pn = p->pt = p->bias = 0;
                for (int m = 0; old && m < old->np; m++)
                    if ((old->px[m] - p->px) * (old->px[m] - p->px) + (old->py[m] - p->py) * (old->py[m] - p->py) < 4)
                        p->pn = old->pn[m], p->pt = old->pt[m];
                float vn = ((b->vx - bw * p->rby) - (a->vx - aw * p->ray)) * c->nx +
                           ((b->vy + bw * p->rbx) - (a->vy + aw * p->rax)) * c->ny;
                if (vn < -bounce_min) p->bias = -e * vn; /* resting, rocking: no endless tiny bounces */
                float out = push_back * (c->depth > slop ? c->depth - slop : 0) * (float)substeps;
                if (out > p->bias) p->bias = out; /* and out of each other */
                if (vn < -0.5f && !hit) {
                    hit = true;
                    lua_createtable(L, 3, 0);
                    lua_pushvalue(L, -3), lua_rawseti(L, -2, 1);
                    lua_pushvalue(L, -2), lua_rawseti(L, -2, 2);
                    lua_pushnumber(L, -vn), lua_rawseti(L, -2, 3);
                    lua_rawseti(L, -4, (lua_Integer)lua_rawlen(L, -4) + 1);
                }
                push(a, b, p, p->pn * c->nx - p->pt * c->ny, p->pn * c->ny + p->pt * c->nx);
            }
            lua_pop(L, 2);
            if (nw[next] < MAXK) W[next][nw[next]++] = (warm_t){.a = pa, .b = pb, .np = c->np};
            a->touched = b->touched = true;
            nc++;
        }
    }
    for (int it = 0; it < iterations; it++)
        for (int k = 0; k < nc; k++) solve(&C[k]);
    for (int k = 0; k < nc && k < nw[next]; k++) /* this substep's pushes, for the next */
        for (int m = 0; m < C[k].np; m++)
            W[next][k].px[m] = C[k].p[m].px, W[next][k].py[m] = C[k].p[m].py, W[next][k].pn[m] = C[k].p[m].pn,
            W[next][k].pt[m] = C[k].p[m].pt;
    cur = next;
    for (int i = 0; i < n; i++) { /* what turns moves now; what was pushed takes its new speed */
        pbody *b = &B[i];
        if (b->kind < 0 || b->inv <= 0 || !(b->turns || b->touched)) continue;
        lua_rawgeti(L, 1, i + 1);
        lua_pushnumber(L, b->vx), lua_setfield(L, -2, "vx");
        lua_pushnumber(L, b->vy), lua_setfield(L, -2, "vy");
        if (b->turns) {
            float a = fmodf(b->angle + b->spin / (float)substeps, 360);
            lua_pushnumber(L, b->x + b->vx / (float)substeps), lua_setfield(L, -2, "x");
            lua_pushnumber(L, b->y + b->vy / (float)substeps), lua_setfield(L, -2, "y");
            lua_pushnumber(L, b->spin), lua_setfield(L, -2, "spin");
            lua_pushnumber(L, a < 0 ? a + 360 : a), lua_setfield(L, -2, "angle");
        }
        lua_pop(L, 1);
    }
    return 1;
}

void physics_register(lua_State *L) { lua_register(L, "physics_turning", l_physics_turning); }
