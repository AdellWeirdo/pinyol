"""The backgrounds of examples/paella: three zones (far + two near chunks each), the boss arena, the title and the
character-select backdrop, at the game's size (480x320 native), each in at most 255 colours with hard alpha.

    python3 examples/paella/gen/art_backgrounds.py RAW_DIR

RAW_DIR holds the generated pictures (big, not kept in the game folder): raw_near_<zone>_<a|b>.png (3:1 strips with a
see-through sky), raw_far_<zone>.png, raw_title.png, raw_select.png and raw_props.png (three tall props: a mooring
mast, a street lamp and a palm). Each near chunk is scaled to 960 wide, its walking surface moved to the feet row
(292), and its two edges hidden behind the same zone prop centred on the seam, over a ground strip that is the same
in every chunk of the zone, so chunks join in any order, mirrored or not.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
ART = HERE.parent / "art"
W, H, FEET = 960, 320, 292
FAR_W, FAR_H = 614, 230
CHEF_H = 86


def solid(img: Image.Image) -> Image.Image:  # see-through or not, nothing between
    img = img.convert("RGBA")
    img.putalpha(img.getchannel("A").point(lambda v: 255 if v >= 128 else 0))
    return img


def quantized(img: Image.Image, colours: int = 254) -> Image.Image:  # one palette, no dithering; alpha kept
    a = img.getchannel("A") if img.mode == "RGBA" else None
    rgb = img.convert("RGB").quantize(colours, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    if a is None:
        return rgb
    rgb.putalpha(a)
    arr = np.array(rgb)
    arr[arr[..., 3] == 0, :3] = 0  # see-through pixels carry no colour
    return Image.fromarray(arr)


def save(img: Image.Image, name: str, meta: dict) -> None:
    img.save(ART / f"{name}.png")
    (ART / f"{name}.json").write_text(json.dumps(meta) + "\n")
    print(name, img.size, img.mode, len(img.getcolors(1 << 16) or []), "colours")


def keyed(img: Image.Image) -> Image.Image:
    """Real alpha if the picture has it; else the flat black or the fake grey checkerboard behind the scene, found as
    the neutral pixels joined to the picture's top or sides, plus a two-pixel bite into the pale fringe around it."""
    from scipy import ndimage

    img = img.convert("RGBA")
    arr = np.array(img)
    if (arr[..., 3] < 128).mean() > 0.02:
        return img
    rgb = arr[..., :3].astype(int)
    spread = rgb.max(2) - rgb.min(2)
    light = rgb.min(2)
    dark_bg = (arr[:40, :, :3].max() < 40)
    cand = (spread <= 14) & ((light <= 30) if dark_bg else (light >= 100))
    lab, _ = ndimage.label(cand)
    h = arr.shape[0]
    edge = np.concatenate([lab[0], lab[: h * 3 // 4, 0], lab[: h * 3 // 4, -1]])
    bg = np.isin(lab, np.unique(edge[edge > 0]))
    fringe = (spread <= 30) & ((light <= 60) if dark_bg else (light >= 90))
    for _ in range(3):
        bg |= ndimage.binary_dilation(bg) & fringe
    arr[bg, 3] = 0
    return Image.fromarray(arr)


def scaled(img: Image.Image, w: int) -> Image.Image:
    return img.resize((w, round(img.height * w / img.width)), Image.LANCZOS)


def keyed_holes(img: Image.Image) -> Image.Image:
    """keyed(), plus the closed pockets of fake background (between bunting, behind fences): big neutral blobs."""
    from scipy import ndimage

    out = keyed(img)
    if img.mode == "RGBA" and (np.array(img)[..., 3] < 128).mean() > 0.02:
        return out
    arr = np.array(out)
    rgb = arr[..., :3].astype(int)
    spread, light = rgb.max(2) - rgb.min(2), rgb.min(2)
    dark_bg = (np.array(img.convert("RGB"))[:40].max() < 40)
    cand = (spread <= 10) & ((light <= 20) if dark_bg else (light >= 110)) & (arr[..., 3] > 0)
    lab, n = ndimage.label(cand)
    sizes = ndimage.sum(cand, lab, range(1, n + 1))
    big = np.isin(lab, 1 + np.flatnonzero(sizes >= 600))
    fringe = (spread <= 30) & ((light <= 60) if dark_bg else (light >= 90))
    for _ in range(3):
        big |= ndimage.binary_dilation(big) & fringe
    arr[big, 3] = 0
    return Image.fromarray(arr)


# ------------------------------------------------------------------ the zones' street chunks

BACK = 276          # the screen row where the walking surface starts (behind it: the scene)
FRONT = 300         # the screen row where the surface ends and its front face (quay wall, kerb) begins
PROP_BASE = 282     # the edge props stand just behind the feet line
SCENE_K = 1.25      # the street's buildings are drawn this much bigger than the generated strip's own scale
BOLLARD = 20        # rows a quay bollard rose above the generated surface
TILE = 240          # the ground band repeats every TILE columns, so every chunk edge meets the same ground
FAR_SHOW = FAR_H    # rows of the far layer the game draws; below it the near layer must be opaque

# zone: surface rows in the 960-wide scaled 'a' picture (the ground band is made of them), its front-face rows, per
# chunk the row where its surface starts and the row where its scene is cut (below it: the ground band), the edge
# prop and its height, the far layer (scaled height, first row shown)
ZONES = {
    "puerto": dict(surface=(268, 282), face=(282, 302), tile_x=64, parts={"a": (268, 268), "b": (262, 262)}, prop="mast", prop_h=236, far=(300, 70)),
    "calle": dict(surface=(277, 292), face=(292, 312), parts={"a": (277, 277), "b": (265, 265)}, prop="lamp", prop_h=214, far=(250, 0)),
    "playa": dict(surface=(288, 320), face=None, parts={"a": (288, 294), "b": (268, 275)}, prop="palm", prop_h=250, far=(262, 10)),
}


def periodic(band: np.ndarray, period: int, blend: int = 24) -> np.ndarray:
    """A horizontal strip that repeats every `period` columns: its end fades into its start."""
    seg = band[:, : period + blend].astype(float)
    out = seg[:, :period].copy()
    t = np.linspace(0, 1, blend + 2)[1:-1][None, :, None]
    out[:, :blend] = seg[:, period:period + blend] * (1 - t) + seg[:, :blend] * t
    return out.round().astype(np.uint8)


def unmarked(arr: np.ndarray, pale: int = 150, grey: int = 45) -> np.ndarray:
    """Paints out the generator's pale scribbles on dark stone: each pale grey pixel takes its nearest dark one."""
    from scipy import ndimage

    rgb = arr[..., :3].astype(int)
    mark = (rgb.min(2) >= pale) & (rgb.max(2) - rgb.min(2) < grey)
    mark = ndimage.binary_dilation(mark, iterations=1)
    _, (iy, ix) = ndimage.distance_transform_edt(mark, return_indices=True)
    out = arr.copy()
    out[mark] = arr[iy[mark], ix[mark]]
    return out


def ground_band(scene: np.ndarray, zone: dict) -> np.ndarray:
    """Rows BACK..320 of a chunk: the zone's surface stretched to BACK..FRONT, then its front face, tiled."""
    s0, s1 = zone["surface"]
    rows = [s0 + (s1 - s0) * (r + 0.5) / (FRONT - BACK) for r in range(FRONT - BACK)] if zone["face"] else \
        [s0 + (s1 - s0) * (r + 0.5) / (H - BACK) for r in range(H - BACK)]
    surf = scene[[min(s1 - 1, int(r)) for r in rows]]
    if zone["face"]:
        f0, _ = zone["face"]
        face = scene[f0:f0 + H - FRONT]
        surf = np.concatenate([surf, unmarked(face)])
    x0 = zone.get("tile_x", 300)
    tile = periodic(surf[:, x0:], TILE)
    return np.concatenate([tile] * (W // TILE), axis=1)


PROPS = {"mast": (40, 500, 255), "lamp": (680, 990, 755), "palm": (1000, 1536, None)}  # raw columns, pole centre


def edge_prop(raw: Path, name: str, height: int) -> Image.Image:
    """A zone's seam prop, made symmetric (so a mirrored chunk meets it too): one half and its mirror image."""
    x0, x1, centre = PROPS[name]
    img = keyed(Image.open(raw / "raw_props.png")).crop((x0, 0, x1, 1024))
    arr = np.array(img)
    if centre is None:  # the palm leans: shift each row so its trunk stands straight under the crown
        a = arr[..., 3] > 0
        ys = [y for y in range(arr.shape[0]) if a[y].any()]
        top, bottom = ys[0], ys[-1]
        def runs(y: int) -> int:
            r = a[y].astype(np.int8)
            return int((np.diff(np.concatenate([[0], r, [0]])) == 1).sum())
        j = next(y for y in range(top + (bottom - top) // 4, bottom) if all(runs(k) == 1 for k in range(y, y + 30)))
        ys = np.arange(j, bottom + 1)
        cs = np.array([np.flatnonzero(a[y]).mean() for y in ys])
        fit = np.poly1d(np.polyfit(ys, cs, 2))
        out = arr.copy()
        for y in ys:  # straighten the bare trunk below the fronds
            out[y] = np.roll(arr[y], int(round(fit(j) - fit(y))), axis=0)
        arr = out
        centre_c = int(round(fit(j)))
    else:
        centre_c = centre - x0
    half = arr[:, : centre_c + 1] if name != "lamp" else arr[:, centre_c:][:, ::-1]
    sym = np.concatenate([half, half[:, -2::-1]], axis=1)
    if centre is None:  # the trunk's top bent away under the fronds: grow the straight trunk up into the crown
        c = sym.shape[1] // 2
        op = sym[..., 3] > 0
        width = op.sum(1)
        full = int(np.median(width[j + (bottom - j) // 3: bottom]))
        y_full = next(y for y in range(j, bottom) if width[y] >= 0.8 * full and op[y, c])
        crown_foot = max(y for y in range(top, j) if op[y, c] and not op[y + 1, c]) if any(
            op[y, c] and not op[y + 1, c] for y in range(top, j)) else top
        for y in range(crown_foot + 1, y_full):
            gap = ~op[y]
            sym[y, gap] = sym[y_full + (y - crown_foot) % 12, gap]
    img = Image.fromarray(sym)
    img = img.crop(img.getchannel("A").getbbox())
    return solid(img.resize((round(img.width * height / img.height), height), Image.LANCZOS))


def far_layer(raw: Path, zone: str) -> Image.Image:
    sh, top = ZONES[zone]["far"]
    img = Image.open(raw / f"raw_far_{zone}.png").convert("RGB")
    img = img.resize((round(img.width * sh / img.height), sh), Image.LANCZOS)
    x = (img.width - FAR_W) // 2
    return img.crop((x, top, x + FAR_W, top + FAR_H))


def fill_below_far(chunk: np.ndarray, far: Image.Image) -> np.ndarray:
    """Below the far layer's last row nothing is drawn behind the street, so holes there get the far's bottom colour
    continued as flat rows (one colour a row never shows the parallax): a calm near sea or haze with a lighter wave
    line every few rows, and a line of foam where it meets the ground."""
    f = np.array(far).astype(int)
    base = f[-6:].reshape(-1, 3).mean(axis=0)
    light = np.minimum(255, base * 1.12 + 26)
    out = chunk.copy()
    for y in range(FAR_SHOW, H):
        hole = out[y, :, 3] == 0
        k = y - FAR_SHOW
        c = light if (k < 2 or k % 9 == 6 or y >= BACK - 3) else base * (1 - 0.003 * k)
        out[y, hole, :3] = np.clip(c, 0, 255).astype(np.uint8)
        out[y, hole, 3] = 255
    return out


HAZE = {"puerto": (120, 90, 140), "calle": (200, 170, 120), "playa": (150, 80, 110)}  # the air of each zone's light
HAZE_K = 0.12  # how far the street's scene is pushed into it, so the chefs are the brightest, crispest thing


def hazed(arr: np.ndarray, zone: str) -> np.ndarray:
    out = arr.copy()
    out[..., :3] = (arr[..., :3] * (1 - HAZE_K) + np.array(HAZE[zone]) * HAZE_K).round().astype(np.uint8)
    return out


def near_chunk(raw: Path, zone: str, part: str, prop: Image.Image, ground: np.ndarray, far: Image.Image) -> Image.Image:
    z = ZONES[zone]
    big = solid(scaled(keyed_holes(Image.open(raw / f"raw_near_{zone}_{part}.png")), round(W * SCENE_K)))
    x0 = (big.width - W) // 2  # the scene a little bigger than the ground it was drawn on: houses at chef scale
    scene = np.array(big.crop((x0, 0, x0 + W, big.height)))
    back, cut = (round(v * SCENE_K) for v in z["parts"][part])
    dy = BACK - back
    canvas = np.zeros((H, W, 4), np.uint8)
    canvas[BACK:] = np.dstack([ground, np.full(ground.shape[:2], 255, np.uint8)])
    src = hazed(scene[max(0, -dy):cut], zone)
    y0 = max(0, dy)
    piece = canvas[y0:y0 + len(src)]
    m = src[..., 3] > 0
    piece[m] = src[m]
    # mooring bollards stood on the generated quay's front edge, where the chefs walk now: their tops, poking above
    # the cut, become a little more pavement reaching back between the crates
    rgb = scene[back + 2:back + 12, :, :3].astype(int).sum(2)
    cols = ((rgb < 200).sum(0) >= 3) & (z["face"] is not None)
    from scipy import ndimage
    cols = ndimage.binary_dilation(cols, iterations=5)
    lab, n = ndimage.label(cols)
    for k in range(1, n + 1):  # each bollard's top: the scene just left of it, carried over (crates beside crates)
        xs = np.flatnonzero(lab == k)
        x0, w = xs[0], len(xs)
        sx = x0 - w if x0 - w >= 0 else xs[-1] + 1
        rows = slice(BACK - BOLLARD, BACK)
        canvas[rows, x0:x0 + w] = canvas[rows, sx:sx + w]
    canvas = fill_below_far(canvas, far)
    img = Image.fromarray(canvas)
    p = Image.fromarray(hazed(np.array(prop), zone))
    half = p.width // 2
    # the same prop centred on both edges: two chunks side by side hide their seam behind it, in any order
    img.alpha_composite(p.crop((half, 0, p.width, p.height)), (0, PROP_BASE - p.height))
    img.alpha_composite(p.crop((0, 0, half, p.height)), (W - half, PROP_BASE - p.height))
    return img


def zone(raw: Path, name: str) -> list:
    z = ZONES[name]
    far = far_layer(raw, name)
    save(far.quantize(255, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB"), f"far_{name}",
         {"w": FAR_W, "h": FAR_H, "mirror": True})
    a = np.array(solid(scaled(keyed_holes(Image.open(raw / f"raw_near_{name}_a.png")), W)))[..., :3]
    ground = ground_band(a, z)
    prop = edge_prop(raw, z["prop"], z["prop_h"])
    chunks = []
    for part in ("a", "b"):
        c = quantized(near_chunk(raw, name, part, prop, ground, far))
        save(c, f"near_{name}_{part}", {"w": W, "h": H, "floor": FEET, "chunks": ["a", "b"]})
        chunks.append(c)
    return [far, *chunks, prop]


def arena(raw: Path, far: Image.Image, prop: Image.Image) -> Image.Image:
    """The boss fight's one screen of beach: open sand, the sea and the sun behind (the far layer shows through), a
    palm at the left edge and the lifeguard tower at the right, nothing in the middle."""
    a = np.array(solid(scaled(keyed_holes(Image.open(raw / "raw_near_playa_a.png")), W)))
    z = ZONES["playa"]
    canvas = np.zeros((H, 480, 4), np.uint8)
    canvas[BACK:] = np.dstack([ground_band(a[..., :3], z)[:, :480], np.full((H - BACK, 480), 255, np.uint8)])
    big = np.array(solid(scaled(keyed_holes(Image.open(raw / "raw_near_playa_a.png")), round(W * SCENE_K))))
    back, cut = (round(v * SCENE_K) for v in z["parts"]["a"])
    dy = BACK - back
    tower = hazed(big[-dy:cut, -150:], "playa")
    tower[: cut + dy - 40, :34, 3] = 0  # not the bar's awning poking in from the left, only its deckchair below  # the lifeguard tower and the parasol beside it, as in the chunks
    m = tower[..., 3] > 0
    region = canvas[: len(tower), 480 - tower.shape[1]:]
    region[m] = tower[m]
    # the beach reaches back to the water's edge: foam, wet sand, then dry sand down to the walking strip
    sand = canvas[BACK:BACK + 4, :, :3].reshape(-1, 3).astype(int).mean(0)
    wet = sand * 0.72
    foam = np.minimum(255, np.array(far)[-1].astype(int).mean(0) * 0.4 + 170)
    for y in range(FAR_SHOW, BACK):
        k = y - FAR_SHOW
        c = foam if k < 3 else wet if k < 8 else wet + (sand - wet) * min(1, (k - 8) / 18)
        hole = canvas[y, :, 3] == 0
        canvas[y, hole, :3] = np.clip(c, 0, 255).astype(np.uint8)
        canvas[y, hole, 3] = 255
    img = Image.fromarray(canvas)
    p = Image.fromarray(hazed(np.array(prop), "playa"))
    img.alpha_composite(p.crop((p.width // 2 - 20, 0, p.width, p.height)), (0, PROP_BASE - p.height))
    return quantized(img)


def picture(raw: Path, name: str, unmark_from: int | None = None) -> Image.Image:
    img = Image.open(raw / f"raw_{name}.png").convert("RGB").resize((480, 320), Image.LANCZOS)
    arr = np.array(img)
    if unmark_from is not None:
        arr[unmark_from:] = unmarked(arr[unmark_from:], pale=100, grey=75)
    return Image.fromarray(arr).quantize(255, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")


def screen(far: Image.Image, chunks: list[Image.Image], cam: int, chef: bool = True) -> Image.Image:
    """What the game shows at camera x `cam`: the far layer at 0.3 speed, mirrored every other time, then the street
    chunks (every other one mirrored, as asalto draws them), and a chef-size box standing on the feet row."""
    out = Image.new("RGBA", (480, H), (0, 0, 0, 255))
    fx = int(cam * 0.3)
    for k in range(fx // FAR_W - 1, (fx + 480) // FAR_W + 2):
        f = far if k % 2 == 0 else far.transpose(Image.FLIP_LEFT_RIGHT)
        out.paste(f, (k * FAR_W - fx, 0))
    for c in range(cam // W, (cam + 480) // W + 1):
        ch = chunks[c % len(chunks)]
        ch = ch if (c // len(chunks)) % 2 == 0 else ch.transpose(Image.FLIP_LEFT_RIGHT)
        out.alpha_composite(ch, (c * W - cam, 0)) if c * W - cam >= 0 else \
            out.alpha_composite(ch.crop((cam - c * W, 0, W, H)), (0, 0))
    if chef:
        from PIL import ImageDraw
        d = ImageDraw.Draw(out)
        d.rectangle((150, FEET - CHEF_H, 150 + 40, FEET), fill=(255, 255, 255), outline=(40, 10, 30), width=2)
        d.rectangle((300, FEET - CHEF_H, 300 + 40, FEET), fill=(230, 40, 60), outline=(40, 10, 30), width=2)
    return out.convert("RGB")


def main(raw: Path) -> None:
    ART.mkdir(exist_ok=True)
    shots = []
    for name in ZONES:
        far, a, b, prop = zone(raw, name)
        # chunk a; the a|b seam; the b|mirrored-a seam; the mirrored a|mirrored b seam
        shots.append([screen(far, [a, b], cam) for cam in (0, W - 240, 2 * W - 240, 3 * W - 240)])
    ar = arena(raw, far, prop)
    save(ar, "arena_playa", {"w": 480, "h": H, "floor": FEET})
    title = picture(raw, "title")
    save(title, "title", {"w": 480, "h": H})
    select = picture(raw, "select", unmark_from=290)
    save(select, "select", {"w": 480, "h": H, "banner": [84, 17, 313, 47],
                          "alcoves": [[39, 134, 50, 82], [109, 134, 50, 82], [180, 134, 50, 82], [250, 134, 50, 82],
                                      [320, 134, 48, 82], [391, 134, 50, 82]], "counter_y": 216})
    shots.append([screen(far, [ar], 0), title, select, screen(far, [ar], 0, chef=False)])
    sheet = Image.new("RGB", (4 * 480 + 3 * 8, len(shots) * (H + 8) - 8), (60, 60, 60))
    for r, row in enumerate(shots):
        for c, s in enumerate(row):
            sheet.paste(s, (c * 488, r * (H + 8)))
    sheet.save(ART / "preview_backgrounds.png")


if __name__ == "__main__":
    main(Path(sys.argv[1]))
