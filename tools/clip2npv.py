#!/usr/bin/env python3
"""Turns a video, an animated GIF or a folder of PNGs into a clip pinyol plays on a canvas (video() in docs/lua.md):
GAME/video/<id>.npv, and GAME/audio/<id>.wav when the video has sound (mono 22050 Hz, for music() or sfx()).

  clip2npv.py SOURCE GAME ID [--width W] [--height H] [--fps N] [--colours N] [--dither | --ordered] [--key N]
                             [--cut T] [--one-palette] [--start S] [--duration S] [--no-sound]

The picture is fitted inside W x H (default 240 x 160, half the screen: drawn at scale 2 it fills it). The clip is cut into
scenes where a frame differs from the one before by more than --cut (0 to 1, default 0.12), and each scene gets its own
palette of up to 256 colours, as the cutscenes of the 32-bit consoles changed theirs (--one-palette: one for all, as before).
Each frame is stored as what changed since the one before; a scene starts whole, and so does a frame every --key frames
within it (default two seconds), so a clip can jump anywhere. --ordered spreads the colours' rounding in the PlayStation's
4x4 pattern, which stays in place from frame to frame (so it costs little in a delta); --dither does Floyd-Steinberg (finer,
but its noise moves every frame and the file grows). A video needs ffmpeg.

The format (little-endian), as src/lua_clip.c reads it:
  "NPV2", u16 w, u16 h, u16 fps x 100, u16 colours, u32 frames, u32 key (the regular keyframe spacing),
  colours x u16 RGB565 (the first scene's palette), (frames + 1) x u32 offsets from the file's start, bit 31 set on a
  keyframe's; then the frames: a byte, 1 and a palette (u16 colours, colours x u16) on a keyframe, else 0; then a run of
  ops over its pixels row after row: 0x00-0x7F skip op+1 (as the frame before), 0x80-0xBF op-0x7F literal colour indices
  follow, 0xC0-0xFF the next index op-0xBF times. A frame may stop short: the rest stays. (NPV1, still played: no first
  byte, one palette, a keyframe every `key` frames.)
"""
import argparse
import glob
import os
import shutil
import struct
import subprocess
import sys
import tempfile

from PIL import Image, ImageChops

KEY = 0xF81F  # a canvas's see-through colour: never one of a clip's


def rgb565(r, g, b):
    c = (r >> 3) << 11 | (g >> 2) << 5 | b >> 3
    return c ^ 1 if c == KEY else c


def fit(im, w, h):
    s = min(w / im.width, h / im.height)
    return im.convert("RGB").resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.LANCZOS)


def frames_of(src, a, tmp):
    """The source's frames as RGB images, and its frame rate."""
    if os.path.isdir(src):
        files = sorted(glob.glob(os.path.join(src, "*.png")))
        if not files:
            sys.exit(f"{src}: no PNG files")
        return [Image.open(f) for f in files], a.fps or 12
    if src.lower().endswith((".gif", ".png", ".webp")):
        im = Image.open(src)
        out, ms = [], []
        for i in range(getattr(im, "n_frames", 1)):
            im.seek(i)
            out.append(im.convert("RGB"))
            ms.append(im.info.get("duration", 100) or 100)
        return out, a.fps or round(1000 / (sum(ms) / len(ms)), 2)
    if not shutil.which("ffmpeg"):
        sys.exit("a video needs ffmpeg (brew install ffmpeg)")
    fps = a.fps or 15
    cmd = ["ffmpeg", "-loglevel", "error", "-y"]
    if a.start:
        cmd += ["-ss", str(a.start)]
    cmd += ["-i", src]
    if a.duration:
        cmd += ["-t", str(a.duration)]
    subprocess.run(cmd + ["-vf", f"fps={fps}", os.path.join(tmp, "f%06d.png")], check=True)
    files = sorted(glob.glob(os.path.join(tmp, "f*.png")))
    if not files:
        sys.exit(f"{src}: no frames")
    return [Image.open(f) for f in files], fps


def sound_of(src, a, out):
    """The video's sound as mono 22050 Hz PCM16, if it has any."""
    if os.path.isdir(src) or src.lower().endswith((".gif", ".png", ".webp")) or not shutil.which("ffmpeg"):
        return False
    cmd = ["ffmpeg", "-loglevel", "error", "-y"]
    if a.start:
        cmd += ["-ss", str(a.start)]
    cmd += ["-i", src]
    if a.duration:
        cmd += ["-t", str(a.duration)]
    r = subprocess.run(cmd + ["-vn", "-ac", "1", "-ar", "22050", "-c:a", "pcm_s16le", out], capture_output=True)
    return r.returncode == 0 and os.path.exists(out) and os.path.getsize(out) > 44


BAYER4 = (0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5)


def ordered(im, amount=24):
    """The image with the PlayStation's 4x4 pattern added (each channel moved by -amount/2 .. +amount/2), so the nearest colour
    of the palette alternates in a fixed pattern where a gradient falls between two: the same at the same place every frame."""
    w, h = im.size
    tile = Image.new("L", (4, 4))
    tile.putdata([round(v * amount / 15) for v in BAYER4])
    pat = Image.new("L", (w, h))
    for y in range(0, h, 4):
        for x in range(0, w, 4):
            pat.paste(tile, (x, y))
    pat = Image.merge("RGB", (pat, pat, pat))
    return ImageChops.add(im, pat, 1.0, -amount // 2)


def small(im):
    """The frame at 32x24, its three channels apart: a change of colours (a red room, then a blue one) counts, not only of light."""
    return im.convert("RGB").resize((32, 24), Image.BILINEAR).tobytes()


def scenes_of(frames, cut):
    """The frames where a scene starts: the first, and each that differs from the one before by more than cut (0 to 1)."""
    starts, prev = [0], small(frames[0])
    for k in range(1, len(frames)):
        cur = small(frames[k])
        if sum(abs(a - b) for a, b in zip(cur, prev)) / (len(cur) * 255) > cut:
            starts.append(k)
        prev = cur
    return starts


def palette_for(frames, colours):
    """One palette of up to `colours` from frames across them."""
    w, h = frames[0].size
    pick = frames[::max(1, len(frames) // 12)]
    sheet = Image.new("RGB", (w, h * len(pick)))
    for k, f in enumerate(pick):
        sheet.paste(f, (0, k * h))
    return sheet.quantize(colors=colours, method=Image.Quantize.MEDIANCUT)


def encode(cur, prev, w, h):
    """One frame's ops: what differs from prev (None: all of it)."""
    out = bytearray()
    n, i = w * h, 0
    while i < n:
        if prev is not None and cur[i] == prev[i]:  # unchanged
            j = i
            while j < n and j - i < 128 and cur[j] == prev[j]:
                j += 1
            if j == n:
                break  # the rest stays: the frame stops here
            out.append(j - i - 1)
            i = j
            continue
        j = i
        while j < n and j - i < 64 and cur[j] == cur[i]:
            j += 1
        if j - i >= 3:  # the same colour again and again
            out += bytes((0xBF + j - i, cur[i]))
            i = j
            continue
        j = i  # literal colours, until a run worth a fill or a skip starts
        while j < n and j - i < 64:
            if j + 2 < n and cur[j] == cur[j + 1] == cur[j + 2]:
                break
            if prev is not None and j + 1 < n and cur[j] == prev[j] and cur[j + 1] == prev[j + 1]:
                break
            j += 1
        j = max(j, i + 1)
        out.append(0x7F + j - i)
        out += bytes(cur[i:j])
        i = j
    return bytes(out)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("source")
    p.add_argument("game")
    p.add_argument("id")
    p.add_argument("--width", type=int, default=240)
    p.add_argument("--height", type=int, default=160)
    p.add_argument("--fps", type=float)
    p.add_argument("--colours", type=int, default=256)
    p.add_argument("--dither", action="store_true", help="smoother gradients, bigger file (noise changes every frame)")
    p.add_argument("--ordered", action="store_true", help="the PlayStation's 4x4 pattern: smooth gradients that stay put")
    p.add_argument("--cut", type=float, default=0.12, help="how different a frame is to start a new scene (0 to 1)")
    p.add_argument("--one-palette", action="store_true", help="one palette for the whole clip (no scenes)")
    p.add_argument("--key", type=int, help="frames between keyframes (default: two seconds)")
    p.add_argument("--start", type=float)
    p.add_argument("--duration", type=float)
    p.add_argument("--no-sound", action="store_true")
    a = p.parse_args()
    if not a.id.replace("_", "").isalnum():
        sys.exit("ID: letters, digits and _")
    if not (1 <= a.width <= 1024 and 1 <= a.height <= 1024 and 2 <= a.colours <= 256):
        sys.exit("1 to 1024 pixels a side, 2 to 256 colours")
    with tempfile.TemporaryDirectory() as tmp:
        frames, fps = frames_of(a.source, a, tmp)
        frames = [fit(f, a.width, a.height) for f in frames]
        w, h = frames[0].size
        key = a.key or max(1, round(fps * 2))
        starts = [0] if a.one_palette else scenes_of(frames, a.cut)
        ends = starts[1:] + [len(frames)]
        dither = Image.Dither.FLOYDSTEINBERG if a.dither else Image.Dither.NONE
        data, offsets, prev, first_pal, nscenes = bytearray(), [], None, None, 0
        for s0, s1 in zip(starts, ends):
            pal_im = palette_for(frames[s0:s1], a.colours)
            pal = pal_im.getpalette()[: 3 * a.colours]
            ncol = min(len(pal) // 3, a.colours)
            pal565 = b"".join(struct.pack("<H", rgb565(*pal[3 * i: 3 * i + 3])) for i in range(ncol))
            first_pal = first_pal or (ncol, pal565)
            nscenes += 1
            for k in range(s0, s1):
                f = ordered(frames[k]) if a.ordered else frames[k]
                cur = f.quantize(palette=pal_im, dither=dither).tobytes()
                whole = (k - s0) % key == 0
                offsets.append(len(data) | (1 << 31 if whole else 0))
                data += (b"\x01" + struct.pack("<H", ncol) + pal565) if whole else b"\x00"
                data += encode(cur, None if whole else prev, w, h)
                prev = cur
        offsets.append(len(data))
        ncol, pal565 = first_pal
        head = b"NPV2" + struct.pack("<HHHHII", w, h, round(fps * 100), ncol, len(frames), key)
        start = len(head) + len(pal565) + 4 * len(offsets)
        index = b"".join(struct.pack("<I", (start + (o & 0x7FFFFFFF)) | (o & (1 << 31))) for o in offsets)
        os.makedirs(os.path.join(a.game, "video"), exist_ok=True)
        path = os.path.join(a.game, "video", a.id + ".npv")
        with open(path, "wb") as out:
            out.write(head + pal565 + index + data)
        print(f"{path}: {len(frames)} frames {w}x{h} at {fps:g} fps, {nscenes} scene(s) of up to {a.colours} colours, "
              f"{os.path.getsize(path) // 1024} KB")
        if not a.no_sound:
            os.makedirs(os.path.join(a.game, "audio"), exist_ok=True)
            wav = os.path.join(a.game, "audio", a.id + ".wav")
            if sound_of(a.source, a, wav):
                print(f"{wav}: its sound")
            elif os.path.exists(wav) and os.path.getsize(wav) <= 44:
                os.remove(wav)


if __name__ == "__main__":
    main()
