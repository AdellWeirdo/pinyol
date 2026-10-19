/* lib/physics.lua's world, stepped in C: on the console Lua took 32 ms a tick for ten turning boxes, and 25 boxes
 * and 30 circles did not fit in a frame. One call a tick, from World:step:
 *
 *   physics_step(world, substeps, iterations, bounce_min, push_back, slop) -> hits {{a, b, speed}, ...}
 *
 * It reads the bodies, ropes and waters once, runs the substeps here and writes back what moved:
 *   - each substep: gravity; bodies that do not turn move; water lifts, slows and carries what is in it;
 *   - bodies that do not turn, against each other: pushed apart and bounced as the Lua code always did, operation
 *     for operation in 32-bit floats and with no fused multiply-adds (-ffp-contract=off), so old games move exactly
 *     as before and two consoles playing together agree;
 *   - where something that turns touches anything (circles, boxes, convex polygons): the faces they press on, clipped
 *     to one or two points as Box2D-lite does, sequential impulses accumulated and warm-started from the substep
 *     before, a Baumgarte push out of overlaps, a bounce only above bounce_min; then what turns moves;
 *   - ropes: never further than their length (sticks: always exactly). */
#include <math.h>
#include <stdlib.h>

#include "lua_api.h"

#define MAXB 256    /* bodies in a world */
#define MAXC 16     /* corners of a polygon (physics.lua checks it) */
#define MAXK 512    /* contacts of turning bodies in one substep */
#define MAXR 128    /* ropes */
#define MAXW 16     /* waters */
#define MAXH 256    /* hits reported in one step */
#define DEG (180.0f / 3.14159265f)
#define RAD (3.14159265f / 180.0f)

typedef struct {
    int kind;                  /* 0 circle, 1 box, 2 polygon; -1 something else (left alone) */
    float x, y, w, h, r;       /* as in Lua: a box's x, y is its top-left corner */
    float cx, cy, vx, vy, spin, angle, inv, iinv, bounce, friction;
    float sx, sy, sa, tx, ty, ta; /* a driven body: where the tick began and where it goes (kin) */
    bool turns, touched, kin;
    const void *ptr;           /* its table: ropes and the warm start find it by this */
    int n, nl;                 /* corners on the screen, and its own (relative to its centre) */
    float lp[2 * MAXC], v[2 * MAXC], nrm[2 * MAXC];
    float x0, y0, x1, y1;      /* bounds */
} pbody;

typedef struct { float rax, ray, rbx, rby, kn, kt, pn, pt, bias, px, py; } cpoint;
typedef struct { int a, b, np; float nx, ny, depth, mu; cpoint p[2]; } contact;
typedef struct { const void *a, *b; int np; float px[2], py[2], pn[2], pt[2]; } warm_t;
typedef struct { int a, b; float len, stiff; bool stick; } rope;
typedef struct { float x, y, w, h, lift, drag, fx, fy; } water;
typedef struct { int a, b; float speed; } hit;

/* ~180 KB, in the slow memory (PSRAM on the console), made the first time a game steps a world */
static struct work {
    pbody b[MAXB];
    contact c[MAXK];
    warm_t w[2][MAXK]; /* the last substep's contacts of turning bodies, and this one's */
    rope r[MAXR];
    water z[MAXW];
    hit h[MAXH];
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

static bool bool_field(lua_State *L, int t, const char *k) {
    lua_getfield(L, t, k);
    bool v = lua_toboolean(L, -1);
    lua_pop(L, 1);
    return v;
}

static void centre(pbody *b) {
    if (b->kind == 1) b->cx = b->x + b->w / 2, b->cy = b->y + b->h / 2;
    else b->cx = b->x, b->cy = b->y;
}

/* Where a box or polygon's corners are now (turned about its centre), each edge's outward normal, its bounds. */
static void shape(pbody *b) {
    centre(b);
    if (b->kind == 0) {
        b->x0 = b->x - b->r, b->y0 = b->y - b->r, b->x1 = b->x + b->r, b->y1 = b->y + b->r;
        return;
    }
    if (!b->turns && b->kind == 1) { /* (as the Lua code bounds a box that does not turn) */
        b->x0 = b->x, b->y0 = b->y, b->x1 = b->x + b->w, b->y1 = b->y + b->h;
    }
    float a = b->angle * RAD, c = cosf(a), s = sinf(a);
    float x0 = 1e30f, y0 = 1e30f, x1 = -1e30f, y1 = -1e30f;
    b->n = b->nl;
    for (int i = 0; i < b->n; i++) {
        float x = b->lp[2 * i], y = b->lp[2 * i + 1], wx = b->cx + x * c - y * s, wy = b->cy + x * s + y * c;
        b->v[2 * i] = wx, b->v[2 * i + 1] = wy;
        x0 = wx < x0 ? wx : x0, x1 = wx > x1 ? wx : x1, y0 = wy < y0 ? wy : y0, y1 = wy > y1 ? wy : y1;
    }
    if (b->turns || b->kind == 2) b->x0 = x0, b->y0 = y0, b->x1 = x1, b->y1 = y1;
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
    b->ptr = lua_topointer(L, t);
    b->x = num_field(L, t, "x", 0), b->y = num_field(L, t, "y", 0);
    b->vx = num_field(L, t, "vx", 0), b->vy = num_field(L, t, "vy", 0);
    b->inv = num_field(L, t, "inv", 0), b->iinv = num_field(L, t, "iinv", 0);
    b->bounce = num_field(L, t, "bounce", 0.3f), b->friction = num_field(L, t, "friction", 0.4f);
    b->turns = bool_field(L, t, "turns");
    b->spin = b->turns ? num_field(L, t, "spin", 0) : 0, b->angle = b->turns ? num_field(L, t, "angle", 0) : 0;
    b->touched = false, b->n = b->nl = 0;
    b->kin = b->turns && b->inv <= 0 && bool_field(L, t, "kin"); /* (set by w:drive: a static body the game moves) */
    if (b->kin) {
        b->sx = b->x, b->sy = b->y, b->sa = b->angle;
        b->tx = num_field(L, t, "tx", b->x), b->ty = num_field(L, t, "ty", b->y), b->ta = num_field(L, t, "ta", b->angle);
    }
    if (b->kind == 0) {
        b->r = num_field(L, t, "r", 1);
    } else if (b->kind == 1) {
        b->w = num_field(L, t, "w", 1), b->h = num_field(L, t, "h", 1);
        float hw = b->w / 2, hh = b->h / 2, q[8] = {-hw, -hh, hw, -hh, hw, hh, -hw, hh};
        memcpy(b->lp, q, sizeof q);
        b->nl = 4;
    } else {
        lua_getfield(L, t, "pts");
        int n = lua_istable(L, -1) ? (int)lua_rawlen(L, -1) / 2 : 0;
        if (n > MAXC) n = MAXC;
        for (int i = 0; i < 2 * n; i++) {
            lua_rawgeti(L, -1, i + 1);
            b->lp[i] = fin(lua_tonumber(L, -1));
            lua_pop(L, 1);
        }
        lua_pop(L, 1);
        b->nl = n;
        if (n < 3) return false;
    }
    shape(b);
    return true;
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

/* ------------------------------------------------------------------ bodies that do not turn: as the Lua code did */

/* How a overlaps b: the direction to push b away from a and how deep; false if they do not touch. */
static bool plain_contact(const pbody *a, const pbody *b, float *nx, float *ny, float *d) {
    if (a->kind == 1 && b->kind == 0) {
        if (!plain_contact(b, a, nx, ny, d)) return false;
        *nx = -*nx, *ny = -*ny;
        return true;
    }
    if (a->kind == 0 && b->kind == 0) {
        float dx = b->x - a->x, dy = b->y - a->y;
        float dist = sqrtf(dx * dx + dy * dy), sum = a->r + b->r;
        if (dist >= sum) return false;
        if (dist < 1e-6f) return *nx = 0, *ny = -1, *d = sum, true;
        return *nx = dx / dist, *ny = dy / dist, *d = sum - dist, true;
    }
    if (a->kind == 0) { /* a circle against a box: from the box's nearest point */
        float bx1 = b->x + b->w, by1 = b->y + b->h;
        float px = fmaxf(b->x, fminf(a->x, bx1)), py = fmaxf(b->y, fminf(a->y, by1));
        float dx = px - a->x, dy = py - a->y, d2 = dx * dx + dy * dy;
        if (d2 >= a->r * a->r) return false;
        if (d2 > 1e-9f) {
            float dist = sqrtf(d2);
            return *nx = dx / dist, *ny = dy / dist, *d = a->r - dist, true;
        }
        float left = a->x - b->x, right = bx1 - a->x, top = a->y - b->y, bottom = by1 - a->y; /* the centre inside */
        float m = left;
        if (right < m) m = right;
        if (top < m) m = top;
        if (bottom < m) m = bottom;
        if (m == top) return *nx = 0, *ny = 1, *d = top + a->r, true;
        if (m == bottom) return *nx = 0, *ny = -1, *d = bottom + a->r, true;
        if (m == left) return *nx = 1, *ny = 0, *d = left + a->r, true;
        return *nx = -1, *ny = 0, *d = right + a->r, true;
    }
    float ox = fminf(a->x + a->w, b->x + b->w) - fmaxf(a->x, b->x); /* two boxes: by the axis they overlap least on */
    float oy = fminf(a->y + a->h, b->y + b->h) - fmaxf(a->y, b->y);
    if (ox <= 0 || oy <= 0) return false;
    float ax = a->x + a->w / 2, ay = a->y + a->h / 2, bx = b->x + b->w / 2, by = b->y + b->h / 2;
    if (ox < oy) return *nx = bx >= ax ? 1 : -1, *ny = 0, *d = ox, true;
    return *nx = 0, *ny = by >= ay ? 1 : -1, *d = oy, true;
}

static int nhits;

static void add_hit(int a, int b, float speed) {
    if (nhits < MAXH) X->h[nhits++] = (hit){a, b, speed};
}

static void resolve(int ia, int ib) {
    pbody *a = &B[ia], *b = &B[ib];
    float nx, ny, depth;
    if (!plain_contact(a, b, &nx, &ny, &depth)) return;
    float im = a->inv + b->inv;
    if (im == 0) return;
    float push = fmaxf(depth - 0.01f, 0) / im * 0.9f; /* apart, by how light each is */
    a->x = a->x - nx * push * a->inv, a->y = a->y - ny * push * a->inv;
    b->x = b->x + nx * push * b->inv, b->y = b->y + ny * push * b->inv;
    float rvx = b->vx - a->vx, rvy = b->vy - a->vy;
    float vn = rvx * nx + rvy * ny;
    if (vn >= 0) return; /* already parting */
    float e = fminf(a->bounce, b->bounce);
    if (-vn < 0.4f) e = 0; /* resting: no endless tiny bounces */
    float j = -(1 + e) * vn / im;
    a->vx = a->vx - j * nx * a->inv, a->vy = a->vy - j * ny * a->inv;
    b->vx = b->vx + j * nx * b->inv, b->vy = b->vy + j * ny * b->inv;
    float tx = rvx - vn * nx, ty = rvy - vn * ny; /* friction, along the surface */
    float tl = sqrtf(tx * tx + ty * ty);
    if (tl > 1e-6f) {
        tx = tx / tl, ty = ty / tl;
        float jt = fmaxf(-j * sqrtf(a->friction * b->friction),
                         fminf(j * sqrtf(a->friction * b->friction), -(rvx * tx + rvy * ty) / im));
        a->vx = a->vx - jt * tx * a->inv, a->vy = a->vy - jt * ty * a->inv;
        b->vx = b->vx + jt * tx * b->inv, b->vy = b->vy + jt * ty * b->inv;
    }
    if (-vn > 0.5f) add_hit(ia, ib, -vn);
}

static void pull(const rope *r) { /* a rope: never further than its length (a stick: always exactly) */
    pbody *a = &B[r->a], *b = &B[r->b];
    centre(a), centre(b);
    float dx = b->cx - a->cx, dy = b->cy - a->cy;
    float d = sqrtf(dx * dx + dy * dy);
    float im = a->inv + b->inv;
    if (d < 1e-6f || im == 0 || (!r->stick && d <= r->len)) return;
    float nx = dx / d, ny = dy / d, off = (d - r->len) * r->stiff / im;
    a->x = a->x + nx * off * a->inv, a->y = a->y + ny * off * a->inv;
    b->x = b->x - nx * off * b->inv, b->y = b->y - ny * off * b->inv;
    float vn = (b->vx - a->vx) * nx + (b->vy - a->vy) * ny; /* and their speeds along it agree */
    if (r->stick || vn > 0) {
        float j = vn / im;
        a->vx = a->vx + j * nx * a->inv, a->vy = a->vy + j * ny * a->inv;
        b->vx = b->vx - j * nx * b->inv, b->vy = b->vy - j * ny * b->inv;
    }
}

static void float_in(pbody *b, const water *z, int nz, float gravity, int substeps) { /* what water does */
    if (b->turns || b->kind == 2) shape(b);
    else if (b->kind == 0) b->x0 = b->x - b->r, b->y0 = b->y - b->r, b->x1 = b->x + b->r, b->y1 = b->y + b->r;
    else b->x0 = b->x, b->y0 = b->y, b->x1 = b->x + b->w, b->y1 = b->y + b->h;
    for (int k = 0; k < nz; k++) {
        const water *q = &z[k];
        if (!(b->x1 > q->x && b->x0 < q->x + q->w && b->y1 > q->y && b->y0 < q->y + q->h)) continue;
        float h = b->y1 - b->y0;
        float under = fminf(1, (b->y1 - fmaxf(b->y0, q->y)) / fmaxf(h, 1e-6f));
        float lift = gravity * q->lift * under / (float)substeps, drag = q->drag * under / (float)substeps;
        b->vy = b->vy - lift;
        b->vx = b->vx + (q->fx - b->vx) * drag, b->vy = b->vy + (q->fy - b->vy) * drag;
        if (b->turns && b->kind != 0 && b->inv > 0) { /* pushed up where it is under: it tips back level */
            float sx = 0, n = 0;
            for (int i = 0; i < b->n; i++) {
                float d = b->v[2 * i + 1] - q->y;
                if (d > 0) sx += b->v[2 * i] * d, n += d;
            }
            if (n > 0) b->spin = b->spin - (sx / n - b->cx) * lift / b->inv * b->iinv * DEG;
        }
        if (b->turns) b->spin = b->spin * (1 - drag);
    }
}

/* The contacts of bodies that turn, worked out and solved; then they move. */
static void turning(lua_State *L, int n, int iterations, float bounce_min, float push_back, float slop, int substeps) {
    for (int i = 0; i < n; i++)
        if (B[i].kind >= 0) shape(&B[i]);
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
            const warm_t *old = NULL;
            for (int k = 0; k < nw[prev] && !old; k++)
                if (W[prev][k].a == a->ptr && W[prev][k].b == b->ptr) old = &W[prev][k];
            bool hitting = false;
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
                if (vn < -0.5f && !hitting) hitting = true, add_hit(i, j, -vn);
                push(a, b, p, p->pn * c->nx - p->pt * c->ny, p->pn * c->ny + p->pt * c->nx);
            }
            if (nw[next] < MAXK) W[next][nw[next]++] = (warm_t){.a = a->ptr, .b = b->ptr, .np = c->np};
            a->touched = b->touched = true;
            nc++;
        }
    }
    (void)L;
    for (int it = 0; it < iterations; it++)
        for (int k = 0; k < nc; k++) solve(&C[k]);
    for (int k = 0; k < nc && k < nw[next]; k++) /* this substep's pushes, for the next */
        for (int m = 0; m < C[k].np; m++)
            W[next][k].px[m] = C[k].p[m].px, W[next][k].py[m] = C[k].p[m].py, W[next][k].pn[m] = C[k].p[m].pn,
            W[next][k].pt[m] = C[k].p[m].pt;
    cur = next;
    for (int i = 0; i < n; i++) { /* what turns moves now */
        pbody *b = &B[i];
        if (b->kind < 0 || b->inv <= 0 || !b->turns) continue;
        b->x += b->vx / (float)substeps, b->y += b->vy / (float)substeps;
        float a = fmodf(b->angle + b->spin / (float)substeps, 360);
        b->angle = a < 0 ? a + 360 : a;
    }
}

/* physics_step(world, substeps, iterations, bounce_min, push_back, slop) -> the hits of the step */
static int l_physics_step(lua_State *L) {
    luaL_checktype(L, 1, LUA_TTABLE);
    int substeps = (int)luaL_checkinteger(L, 2), iterations = (int)luaL_checkinteger(L, 3);
    float bounce_min = fin(luaL_checknumber(L, 4)), push_back = fin(luaL_checknumber(L, 5)), slop = fin(luaL_checknumber(L, 6));
    if (iterations < 1 || iterations > 32 || substeps < 1 || substeps > 8) return luaL_error(L, "physics: bad step settings");
    float gravity = num_field(L, 1, "gravity", 0.25f);
    lua_getfield(L, 1, "bodies"); /* 7 */
    lua_getfield(L, 1, "ropes");  /* 8 */
    lua_getfield(L, 1, "waters"); /* 9 */
    if (!lua_istable(L, 7)) return luaL_error(L, "physics: a world has bodies");
    int n = (int)lua_rawlen(L, 7);
    if (n > MAXB) return luaL_error(L, "physics: %d bodies at most in a world", MAXB);
    if (!X && !(X = hal_realloc_slow(NULL, sizeof *X))) return luaL_error(L, "physics: out of memory");
    bool any_turns = false;
    for (int i = 0; i < n; i++) {
        lua_rawgeti(L, 7, i + 1);
        if (!lua_istable(L, -1) || !read_body(L, lua_gettop(L), &B[i])) B[i].kind = -1;
        any_turns |= B[i].kind >= 0 && B[i].turns;
        lua_pop(L, 1);
    }
    int nr = 0, nz = 0;
    for (int k = 1; lua_istable(L, 8) && k <= (int)lua_rawlen(L, 8) && nr < MAXR; k++) { /* ropes, by their bodies */
        lua_rawgeti(L, 8, k);
        if (lua_istable(L, -1)) {
            int t = lua_gettop(L), ia = -1, ib = -1;
            lua_getfield(L, t, "a");
            const void *pa = lua_topointer(L, -1);
            lua_getfield(L, t, "b");
            const void *pb = lua_topointer(L, -1);
            lua_pop(L, 2);
            for (int i = 0; i < n && (ia < 0 || ib < 0); i++) {
                if (B[i].kind < 0) continue;
                if (B[i].ptr == pa) ia = i;
                if (B[i].ptr == pb) ib = i;
            }
            if (ia >= 0 && ib >= 0 && ia != ib)
                X->r[nr++] = (rope){ia, ib, num_field(L, t, "len", 0), num_field(L, t, "stiff", 0.8f), bool_field(L, t, "stick")};
        }
        lua_pop(L, 1);
    }
    for (int k = 1; lua_istable(L, 9) && k <= (int)lua_rawlen(L, 9) && nz < MAXW; k++) {
        lua_rawgeti(L, 9, k);
        if (lua_istable(L, -1)) {
            int t = lua_gettop(L);
            X->z[nz++] = (water){num_field(L, t, "x", 0), num_field(L, t, "y", 0), num_field(L, t, "w", 0),
                                  num_field(L, t, "h", 0), num_field(L, t, "lift", 2), num_field(L, t, "drag", 0.05f),
                                  num_field(L, t, "flow_x", 0), num_field(L, t, "flow_y", 0)};
        }
        lua_pop(L, 1);
    }
    nhits = 0;
    for (int step = 0; step < substeps; step++) {
        for (int i = 0; i < n; i++) { /* a driven body is where it is this far through the tick, so what it meets is not jumped */
            pbody *b = &B[i];
            if (b->kind < 0 || !b->kin) continue;
            float f = (float)(step + 1) / (float)substeps;
            if (step + 1 == substeps) b->x = b->tx, b->y = b->ty, b->angle = b->ta;
            else b->x = b->sx + (b->tx - b->sx) * f, b->y = b->sy + (b->ty - b->sy) * f, b->angle = fmodf(b->sa + b->spin * f + 360, 360);
        }
        for (int i = 0; i < n; i++) { /* (what turns moves after its contacts are worked out) */
            pbody *b = &B[i];
            if (b->kind < 0 || b->inv <= 0) continue;
            b->vy = b->vy + gravity / (float)substeps;
            if (!b->turns) b->x = b->x + b->vx / (float)substeps, b->y = b->y + b->vy / (float)substeps;
        }
        for (int i = 0; nz && i < n; i++)
            if (B[i].kind >= 0 && B[i].inv > 0) float_in(&B[i], X->z, nz, gravity, substeps);
        for (int i = 0; i < n; i++) /* bounds of what does not turn, before any is pushed (as the Lua code) */
            if (B[i].kind >= 0 && !B[i].turns) shape(&B[i]);
        for (int i = 0; i < n; i++) {
            const pbody *a = &B[i];
            if (a->kind < 0 || a->turns) continue;
            float ax0 = a->x0, ay0 = a->y0, ax1 = a->x1, ay1 = a->y1;
            for (int j = i + 1; j < n; j++) {
                const pbody *b = &B[j];
                if (b->kind < 0 || b->turns || !(a->inv > 0 || b->inv > 0)) continue;
                if (ax0 < b->x1 && b->x0 < ax1 && ay0 < b->y1 && b->y0 < ay1) resolve(i, j);
            }
        }
        if (any_turns) turning(L, n, iterations, bounce_min, push_back, slop, substeps);
        for (int k = 0; k < nr; k++) pull(&X->r[k]);
    }
    for (int i = 0; i < n; i++) { /* back into Lua: what moves */
        pbody *b = &B[i];
        if (b->kind < 0 || (b->inv <= 0 && !b->kin)) continue;
        if (b->kin) b->vx = b->vy = b->spin = 0; /* it stops being driven: one that nobody turns next tick does not throw */
        lua_rawgeti(L, 7, i + 1);
        if (b->kin) lua_pushboolean(L, 0), lua_setfield(L, -2, "kin");
        lua_pushnumber(L, b->x), lua_setfield(L, -2, "x");
        lua_pushnumber(L, b->y), lua_setfield(L, -2, "y");
        lua_pushnumber(L, b->vx), lua_setfield(L, -2, "vx");
        lua_pushnumber(L, b->vy), lua_setfield(L, -2, "vy");
        if (b->turns) {
            lua_pushnumber(L, b->spin), lua_setfield(L, -2, "spin");
            lua_pushnumber(L, b->angle), lua_setfield(L, -2, "angle");
        }
        lua_pop(L, 1);
    }
    lua_createtable(L, nhits, 0);
    for (int k = 0; k < nhits; k++) {
        lua_createtable(L, 3, 0);
        lua_rawgeti(L, 7, X->h[k].a + 1), lua_rawseti(L, -2, 1);
        lua_rawgeti(L, 7, X->h[k].b + 1), lua_rawseti(L, -2, 2);
        lua_pushnumber(L, X->h[k].speed), lua_rawseti(L, -2, 3);
        lua_rawseti(L, -2, k + 1);
    }
    return 1;
}

void physics_register(lua_State *L) { lua_register(L, "physics_step", l_physics_step); }
