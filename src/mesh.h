/* A 3D model made of quads, turned, projected, culled, lit and sorted in C, then drawn as quads: what views.draw3d does in Lua,
 * at the cost of a few hundred faces instead of a few dozen (a PlayStation's GTE and ordering table, in a function).
 * mesh_model_new keeps the vertices and faces once; mesh_build, each frame, gives the faces that show, far to near. */
#ifndef MESH_H
#define MESH_H

#include <stdbool.h>
#include <stdint.h>

#define MESH_MAX_VERTS 512
#define MESH_MAX_FACES 256

typedef struct mesh_model mesh_model;
struct quad_mip;

/* verts: nv x (x, y, z). idx: nf x 4 vertex numbers (0-based) in the order quad() takes its corners (top-left, top-right,
 * bottom-right, bottom-left; a triangle repeats its last). uv: nf x 8 texels (u, v of each corner), or NULL for the whole picture.
 * NULL when a number is out of range or the model is too big. */
mesh_model *mesh_model_new(const float *verts, int nv, const uint16_t *idx, const float *uv, int nf);
void mesh_model_free(mesh_model *m);

typedef struct {
    int16_t xy[8];             /* the four corners, in eighths of a pixel */
    uint8_t light[3];          /* the colour to light it by (128: as it is) */
    const int16_t *uv;         /* its texture corners in eighths of a texel, or NULL: the whole picture */
    const struct quad_mip *mip; /* left NULL: the caller fills it */
} mesh_face;

typedef struct {
    float pos[3];              /* where the model's origin is, from the camera (z away, y down) */
    float rot[3];              /* degrees about x, y, z, applied as Rx * Ry * Rz */
    float scale;
    float focal, cx, cy;       /* screen x = cx + x * focal / z */
    float near;                /* a face with a corner nearer than this is not drawn */
    bool lit;                  /* light the faces: ambient + gain * (light . normal), light pointing toward the lamp, camera space */
    float light_dir[3], ambient, gain;
    bool snap;                 /* corners on whole pixels, as a PlayStation drew them */
    bool cull;                 /* leave out the faces turned away (the corners running counterclockwise on the screen) */
    bool fade;                 /* darken with distance: full at fade0, black at fade1 */
    float fade0, fade1;
} mesh_params;

/* The faces that show, far to near (an ordering table of 256 slots: faces of about one depth keep their order). At most `max` of
 * them: the nearest. bbox: the pixels they cover (x0, y0, x1, y1). Returns how many. */
int mesh_build(mesh_model *m, const mesh_params *p, mesh_face *out, int max, int bbox[4]);

#endif
