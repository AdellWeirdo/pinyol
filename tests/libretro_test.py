"""The libretro core as a frontend sees it (tests/libretro_test.c is the frontend):

    python3 tests/libretro_test.py FRONTEND CORE GAME_DIR WORK

The game plays the same from its folder, its game.json, its zip (tools/pack_game.py) and that zip with no save
folder from the frontend; the zip is unpacked into <saves>/pinyol/<id>/game, once while it stays the same. A zip with
a damaged file, or with a name that climbs out of its folder, is refused and writes nothing outside.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

FRAMES = 300


def play(frontend: str, core: str, content: Path, saves: Path | None, fresh: bool = True) -> dict[str, str] | None:
    if saves:
        saves.mkdir(parents=True, exist_ok=not fresh)
    r = subprocess.run([frontend, core, str(content), str(saves) if saves else "-", str(FRAMES)],
                       capture_output=True, text=True)
    if r.returncode == 1 and r.stdout.strip() == "refused":
        return None
    if r.returncode:
        sys.exit(f"{content}: the frontend failed ({r.returncode})\n{r.stderr}")
    words = r.stdout.split()
    return dict(zip(words[::2], words[1::2]))


def check(cond: bool, what: str) -> None:
    if not cond:
        sys.exit(f"FAIL: {what}")
    print(f"ok: {what}")


def main() -> None:
    frontend, core, game, work = sys.argv[1], sys.argv[2], Path(sys.argv[3]), Path(sys.argv[4])
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    root = Path(__file__).resolve().parents[1]

    folder = play(frontend, core, game, work / "s_folder")
    check(folder is not None, "a game's folder opens")
    check(folder["size"] == "480x320" and folder["fps"] == "60" and folder["hz"] == "22050", "480x320, 60 fps, 22050 Hz")
    check(int(folder["samples"]) == FRAMES * 22050 // 60, f"{FRAMES * 22050 // 60} samples in {FRAMES} frames")
    check(folder["varied"] == "1", "the picture is not one flat colour")
    gid = game.name
    check((work / f"s_folder/pinyol/{gid}/saves").is_dir(), "its saves go to <saves>/pinyol/<id>/saves")

    check(play(frontend, core, game / "game.json", work / "s_json")["crc"] == folder["crc"], "its game.json: the same")

    subprocess.run([sys.executable, str(root / "tools/pack_game.py"), str(game), "-o", str(work)], check=True,
                   capture_output=True)
    packed = work / f"{gid}.zip"
    zipped = play(frontend, core, packed, work / "s_zip")
    check(zipped is not None and zipped["crc"] == folder["crc"], "its zip: the same")
    unpacked = work / f"s_zip/pinyol/{gid}/game"
    check((unpacked / "game.json").is_file(), "unpacked into <saves>/pinyol/<id>/game")
    gone = next(p for p in sorted(unpacked.rglob("*")) if p.is_file() and p.name != "game.json")
    gone.unlink()
    shutil.rmtree(work / "s_zip/pinyol" / gid / "saves")
    check(play(frontend, core, packed, work / "s_zip", fresh=False) is not None and not gone.exists(),
          "the same zip again is not unpacked again")
    stat = packed.stat()
    os.utime(packed, (stat.st_atime, stat.st_mtime + 10))
    check(play(frontend, core, packed, work / "s_zip", fresh=False)["crc"] == folder["crc"] and gone.exists(),
          "a changed zip is")
    again = play(frontend, core, packed, None)
    check(again is not None and again["crc"] == folder["crc"], "its zip with no save folder: the same")
    check((work / f"pinyol/{gid}/game/game.json").is_file(), "then unpacked beside the zip")

    evil = work / "evil.zip"
    shutil.copy(packed, evil)
    with zipfile.ZipFile(evil, "a") as z:
        z.writestr(f"{gid}/../../outside.txt", "no")
    check(play(frontend, core, evil, work / "s_evil") is None, "a zip with ../ in a name is refused")
    check(not list(work.rglob("outside.txt")), "and writes nothing outside")

    damaged = work / "damaged.zip"
    with zipfile.ZipFile(packed) as src, zipfile.ZipFile(damaged, "w", zipfile.ZIP_STORED) as dst:
        for info in src.infolist():
            dst.writestr(info.filename, src.read(info))
    data = bytearray(damaged.read_bytes())
    at = data.index(b'"', data.index(f"{gid}/game.json".encode()) + 1)  # a byte of game.json itself
    data[at] ^= 0x20
    damaged.write_bytes(data)
    check(play(frontend, core, damaged, work / "s_damaged") is None, "a zip with a damaged file is refused")
    check(play(frontend, core, work / "nothing.zip", work / "s_none") is None, "a missing zip is refused")
    print("PASS")


if __name__ == "__main__":
    main()
