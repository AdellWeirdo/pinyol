#!/usr/bin/env python3
"""Turns a video, an animated GIF or a folder of PNGs into a clip np2d plays on a canvas (video() in docs/lua.md):
GAME/video/<id>.npv, and GAME/audio/<id>.wav when the video has sound (mono 22050 Hz, for music() or sfx()).

  clip2npv.py SOURCE GAME ID [--width W] [--height H] [--fps N] [--colours N] [--dither] [--key N]
                             [--start S] [--duration S] [--no-sound]

The picture is fitted inside W x H (default 240 x 160, half the screen: drawn at scale 2 it fills it), with one
palette of up to 256 colours for the whole clip, and each frame stored as what changed since the one before
(a keyframe every --key frames stores it whole, so a clip can jump anywhere). A video needs ffmpeg.

The format (little-endian), as src/lua_clip.c reads it:
  "NPV1", u16 w, u16 h, u16 fps x 100, u16 colours, u32 frames, u32 key (frames between keyframes),
  colours x u16 RGB565, (frames + 1) x u32 offsets from the file's start, then the frames: each a run of ops over
  its pixels row after row: 0x00-0x7F skip op+1 (as the frame before), 0x80-0xBF op-0x7F literal colour indices
  follow, 0xC0-0xFF the next index op-0xBF times. A frame may stop short: the rest stays.
"""
import argparse
import glob
import os
import shutil
import struct
import subprocess
import sys
import tempfile

from PIL import Image

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
        step = max(1, len(frames) // 24)  # one palette for the whole clip, from frames across it
        sheet = Image.new("RGB", (w, h * len(frames[::step])))
        for k, f in enumerate(frames[::step]):
            sheet.paste(f, (0, k * h))
        pal_im = sheet.quantize(colors=a.colours, method=Image.Quantize.MEDIANCUT)
        pal = pal_im.getpalette()[: 3 * a.colours]
        ncol = len(pal) // 3
        dither = Image.Dither.FLOYDSTEINBERG if a.dither else Image.Dither.NONE
        key = a.key or max(1, round(fps * 2))
        data, offsets, prev = bytearray(), [], None
        for k, f in enumerate(frames):
            cur = f.quantize(palette=pal_im, dither=dither).tobytes()
            offsets.append(len(data))
            data += encode(cur, None if k % key == 0 else prev, w, h)
            prev = cur
        offsets.append(len(data))
        head = b"NPV1" + struct.pack("<HHHHII", w, h, round(fps * 100), ncol, len(frames), key)
        pal565 = b"".join(struct.pack("<H", rgb565(*pal[3 * i: 3 * i + 3])) for i in range(ncol))
        start = len(head) + len(pal565) + 4 * len(offsets)
        index = b"".join(struct.pack("<I", start + o) for o in offsets)
        os.makedirs(os.path.join(a.game, "video"), exist_ok=True)
        path = os.path.join(a.game, "video", a.id + ".npv")
        with open(path, "wb") as out:
            out.write(head + pal565 + index + data)
        print(f"{path}: {len(frames)} frames {w}x{h} at {fps:g} fps, {ncol} colours, "
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
