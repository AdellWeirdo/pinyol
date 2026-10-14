# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10", "fonttools>=4", "brotli>=1"]
# ///
"""Build pinyol's site (https://ipaud.github.io/pinyol/) into site/dist/: the page, the web player, every example
as a zip, the editor.

    uv run site/build.py
    python3 -m http.server -d site/dist        # open http://localhost:8000

The web player is built once with Emscripten into site/.cache/build-web (EMSDK_PYTHON must be a python >= 3.10), and
the test count comes from build/ (cmake -B build && cmake --build build first). The site is published from the
gh-pages branch: site/dist/ as it is.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

from fontTools.ttLib import TTFont
from PIL import Image

HERE = Path(__file__).resolve().parent
DIST = HERE / "dist"
CACHE = HERE / ".cache"

sys.path.insert(0, str(HERE))
import page  # noqa: E402


def player(np2d: Path) -> Path:
    out = CACHE / "build-web"
    if not (out / "player.wasm").exists():
        env = {**os.environ, "EMSDK_PYTHON": os.environ.get("EMSDK_PYTHON", "/opt/homebrew/bin/python3.12")}
        subprocess.run(["emcmake", "cmake", "-S", str(np2d), "-B", str(out), "-DCMAKE_BUILD_TYPE=Release"], check=True, env=env)
        subprocess.run(["cmake", "--build", str(out), "--target", "pinyol_player", "-j8"], check=True, env=env)
    return out


def games(np2d: Path) -> None:
    sys.path.insert(0, str(np2d / "tools"))
    import pack_game
    out = DIST / "games"
    out.mkdir(parents=True)
    ids = [k["example"] for k in page.LOOKS] + [g for g, _ in page.OTHERS]
    for gid in ids:
        pack_game.pack(np2d / "examples" / gid, out, False)
    missing = [g for g in ids if not (out / f"{g}.zip").exists()]
    if missing:
        raise SystemExit(f"these examples did not pack under their own id: {missing}")


def fonts(np2d: Path) -> None:
    out = DIST / "fonts"
    out.mkdir(parents=True)
    for src, name in (("jersey15/Jersey15-Regular.ttf", "jersey15"), ("silkscreen/Silkscreen-Regular.ttf", "silkscreen")):
        f = TTFont(np2d / "third_party/fonts" / src)
        f.flavor = "woff2"
        f.save(out / f"{name}.woff2")


def images(np2d: Path) -> None:
    looks = DIST / "img/looks"
    looks.mkdir(parents=True)
    for png in (np2d / "docs/looks").glob("*.png"):
        shutil.copy(png, looks / png.name)
    logo = Image.open(np2d / "docs/logo.png").convert("RGBA")
    logo.resize((128, round(128 * logo.height / logo.width)), Image.LANCZOS).save(DIST / "img/logo.png", optimize=True)
    icon = Image.new("RGBA", (64, 64))
    small = logo.resize((64, round(64 * logo.height / logo.width)), Image.LANCZOS)
    icon.alpha_composite(small, (0, (64 - small.height) // 2))
    icon.save(DIST / "img/icon.png", optimize=True)
    og = Image.new("RGB", (1200, 630), (11, 14, 31))  # the card a shared link shows: the logo over four looks
    for i, name in enumerate(("neogeo", "cps2", "32bits", "gba")):
        shot = Image.open(looks / f"{name}.png").convert("RGB").resize((300, 200), Image.NEAREST)
        og.paste(shot, (0 + i * 300, 430))
    big = logo.resize((560, round(560 * logo.height / logo.width)), Image.LANCZOS)
    og.paste(big, ((1200 - big.width) // 2, max(10, (430 - big.height) // 2)), big)
    og.save(DIST / "img/og.png", optimize=True)


def editor(np2d: Path, build_web: Path) -> None:
    subprocess.run([sys.executable, str(np2d / "tools/make_editor.py"), str(DIST / "editor"), "--player", str(build_web)],
                   check=True, stdout=subprocess.DEVNULL)


def stats(np2d: Path) -> dict:
    c_lines = sum(len(p.read_text(errors="replace").splitlines()) for p in (np2d / "src").glob("*.[ch]"))
    tests = 0
    if (np2d / "build/CTestTestfile.cmake").exists():
        listed = subprocess.run(["ctest", "--test-dir", str(np2d / "build"), "-N"], capture_output=True, text=True).stdout
        tests = next((int(l.split(":")[1]) for l in listed.splitlines() if l.startswith("Total Tests:")), 0)
    commits = int(subprocess.run(["git", "-C", str(np2d), "rev-list", "--count", "HEAD"], capture_output=True, text=True,
                                 check=True).stdout)
    examples = sum(1 for p in (np2d / "examples").iterdir() if (p / "game.json").exists())
    if not tests:
        raise SystemExit(f"no test count: build the engine first (cmake -B build && cmake --build build in {np2d})")
    return {"c_lines": c_lines, "tests": tests, "commits": commits, "examples": examples}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--np2d", type=Path, default=HERE.parent, help="the engine's repository (this one)")
    np2d = ap.parse_args().np2d.expanduser().resolve()
    if not (np2d / "tools/pack_game.py").exists():
        raise SystemExit(f"{np2d} is not pinyol's repository")
    if DIST.exists():
        shutil.rmtree(DIST)
    DIST.mkdir()
    for f in ("styles.css", "site.js"):
        shutil.copy(HERE / "src" / f, DIST / f)
    build_web = player(np2d)
    (DIST / "play").mkdir()
    for ext in ("html", "js", "wasm"):
        shutil.copy(build_web / f"player.{ext}", DIST / "play" / f"player.{ext}")
    games(np2d)
    fonts(np2d)
    images(np2d)
    editor(np2d, build_web)
    board = json.loads((HERE / "src/data/board.json").read_text(encoding="utf-8"))
    (DIST / "index.html").write_text(page.render(board, stats(np2d)), encoding="utf-8")
    (DIST / ".nojekyll").write_text("")  # GitHub Pages: serve the folders as they are
    size = sum(p.stat().st_size for p in DIST.rglob("*") if p.is_file())
    print(f"dist/: {sum(1 for _ in DIST.rglob('*'))} files, {size / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
