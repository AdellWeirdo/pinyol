# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10", "fonttools>=4", "brotli>=1"]
# ///
"""Build pinyol's site (https://pinyol.ipaud.dev/) into site/dist/: the page, a page for each game (gamepage.py),
the web player, every example as a zip, the editor.

    uv run site/build.py
    python3 -m http.server -d site/dist        # open http://localhost:8000

The web player is built once with Emscripten into site/.cache/build-web (EMSDK_PYTHON must be a python >= 3.10), and
the test count comes from build/ (cmake -B build && cmake --build build first). The site is published from the
gh-pages branch: site/dist/ as it is.
"""
from __future__ import annotations

import argparse
import hashlib
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
import gamepage  # noqa: E402
import i18n  # noqa: E402
import page  # noqa: E402


def player(np2d: Path) -> Path:
    out = CACHE / "build-web"
    env = {**os.environ, "EMSDK_PYTHON": os.environ.get("EMSDK_PYTHON", "/opt/homebrew/bin/python3.12")}
    if not (out / "CMakeCache.txt").exists():
        subprocess.run(["emcmake", "cmake", "-S", str(np2d), "-B", str(out), "-DCMAKE_BUILD_TYPE=Release"], check=True, env=env)
    subprocess.run(["cmake", "--build", str(out), "--target", "pinyol_player", "-j8"], check=True, env=env)  # only what changed
    return out


def games(np2d: Path) -> None:
    sys.path.insert(0, str(np2d / "tools"))
    import pack_game
    out = DIST / "games"
    out.mkdir(parents=True)
    ids = [k["example"] for k in page.LOOKS] + [g for g, _ in page.OTHERS] + [j["id"] for j in page.CODEX]
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
    logo.resize((192, round(192 * logo.height / logo.width)), Image.LANCZOS).save(DIST / "img/logo.png", optimize=True)
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


def covers(np2d: Path) -> None:
    """Each game's cover for its page, the ranking and the cover of the week: the examples' cover.rgb565 (240x160, as
    the console's menu shows it) as PNG, and the Library's cover.png as it is."""
    out = DIST / "img/covers"
    out.mkdir(parents=True)
    for rgb in (np2d / "examples").glob("*/cover.rgb565"):
        raw = rgb.read_bytes()
        px = [int.from_bytes(raw[i:i + 2], "little") for i in range(0, 240 * 160 * 2, 2)]
        img = Image.new("RGB", (240, 160))
        img.putdata([((v >> 11) * 255 // 31, (v >> 5 & 63) * 255 // 63, (v & 31) * 255 // 31) for v in px])
        img.save(out / f"{rgb.parent.name}.png", optimize=True)
    for png in (np2d / "library").glob("*/cover.png"):
        shutil.copy(png, out / f"{png.parent.name}.png")


FIRMWARE_PARTS = (("bootloader.bin", 0x0), ("partition-table.bin", 0x8000), ("ota_data_initial.bin", 0xF000),
                  ("pinyol_console.bin", 0x20000), ("game.bin", 0x420000))  # firmware/partitions.csv


def firmware(src: Path) -> dict | None:
    """The console's firmware for the install button: the five pieces idf.py flashes (copied into src with a
    firmware.json saying its version, release tag and number of flash games), and ESP Web Tools' manifest for them."""
    if not (src / "firmware.json").exists():
        print(f"no firmware in {src}: the page goes without its install button")
        return None
    meta = json.loads((src / "firmware.json").read_text())
    out = DIST / "firmware"
    out.mkdir()
    for name, _ in FIRMWARE_PARTS:
        shutil.copy(src / name, out / name)
    manifest = {"name": "pinyol", "version": meta["version"], "new_install_prompt_erase": True,
                "new_install_improv_wait_time": 0,  # the console speaks no Improv (Wi-Fi set-up): don't wait for it
                "builds": [{"chipFamily": "ESP32-S3", "parts": [{"path": n, "offset": o} for n, o in FIRMWARE_PARTS]}]}
    (out / "manifest.json").write_text(json.dumps(manifest, indent=1))
    shutil.copytree(HERE / "vendor/esp-web-tools", DIST / "vendor/esp-web-tools")
    mb = sum((out / n).stat().st_size for n, _ in FIRMWARE_PARTS) / 1e6
    return {**meta, "mb": f"{mb:.1f}".replace(".", ",")}


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


def sitemap(paths: list[str]) -> None:
    """sitemap.xml: every page in every language, for search engines (to give to them: Search Console and the like)."""
    urls = "".join(f"<url><loc>{page.SITE}{i18n.page_path(lang)}{path}</loc></url>\n" for path in paths for lang in i18n.LANGS)
    (DIST / "sitemap.xml").write_text('<?xml version="1.0" encoding="UTF-8"?>\n'
                                      f'<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n{urls}</urlset>\n')


def not_found() -> None:
    """404.html, which Pages serves at any address it has nothing for: its links absolute, in the three languages."""
    (DIST / "404.html").write_text(f"""<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>pinyol · 404</title>
<link rel="icon" href="{page.SITE}img/icon.png">
<link rel="stylesheet" href="{page.SITE}styles.css">
</head>
<body>
<main class="lost"><div class="wrap">
<a href="{page.SITE}"><img src="{page.SITE}img/logo.png" alt="pinyol" width="96" height="63"></a>
<p class="kicker pixel">404</p>
<h1 class="page-title">Esta página no existe</h1>
<p class="lede" lang="ca">Aquesta pàgina no existeix.</p>
<p class="lede" lang="en">This page doesn't exist.</p>
<div class="actions"><a class="btn btn-primary" href="{page.SITE}">Inicio</a><a class="btn btn-ghost" href="{page.SITE}ca/" lang="ca">Inici</a><a class="btn btn-ghost" href="{page.SITE}en/" lang="en">Home</a></div>
</div></main>
</body>
</html>
""", encoding="utf-8")


def versioned(html: str) -> str:
    """The page with its stylesheet and scripts named with their hash: a new version is fetched at once, not after the
    10 minutes Pages caches a file."""
    for f in ("styles.css", "site.js", "games.js", "juega.js"):
        html = html.replace(f'"{f}"', f'"{f}?v={hashlib.sha256((DIST / f).read_bytes()).hexdigest()[:8]}"')
    return html


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--np2d", type=Path, default=HERE.parent, help="the engine's repository (this one)")
    ap.add_argument("--firmware", type=Path, default=CACHE / "firmware",
                    help="the console's firmware pieces and firmware.json (without them, no install button)")
    args = ap.parse_args()
    np2d = args.np2d.expanduser().resolve()
    if not (np2d / "tools/pack_game.py").exists():
        raise SystemExit(f"{np2d} is not pinyol's repository")
    if DIST.exists():
        shutil.rmtree(DIST)
    DIST.mkdir()
    for f in ("styles.css", "site.js", "games.js", "juega.js"):
        shutil.copy(HERE / "src" / f, DIST / f)
    build_web = player(np2d)
    (DIST / "play").mkdir()
    for ext in ("html", "js", "wasm"):
        shutil.copy(build_web / f"player.{ext}", DIST / "play" / f"player.{ext}")
    games(np2d)
    fonts(np2d)
    images(np2d)
    covers(np2d)
    shutil.copytree(HERE / "src/img", DIST / "img", dirs_exist_ok=True)
    shutil.copytree(HERE / "vendor/goatcounter", DIST / "vendor/goatcounter")  # the visit counter (page.COUNTER)
    if (HERE / "src/video").exists():  # the editor's video (LÍNEA 0 being made)
        shutil.copytree(HERE / "src/video", DIST / "video", dirs_exist_ok=True)
    fw = firmware(args.firmware)
    editor(np2d, build_web)
    board = json.loads((HERE / "src/data/board.json").read_text(encoding="utf-8"))
    games_list = gamepage.catalog(np2d, page.measured(board))
    library_ids = " ".join(g["id"] for g in games_list if g["kind"] == "library")
    tabs = page.site(board, stats(np2d), fw, gamepage.public(games_list), library_ids, gamepage.picker(games_list))
    for path, html in tabs.items():
        page.publish(DIST, versioned(html), path)
    page.publish(DIST, page.moved("biblioteca/"), "juegos/")  # the old games tab (its games' pages stay under it)
    print(f"{len(tabs)} tabs, juegos/: {gamepage.write(DIST, games_list, versioned)} games, each in {len(i18n.LANGS)} languages")
    sitemap(list(tabs) + [f"juegos/{g['id']}/" for g in games_list])
    not_found()
    (DIST / ".nojekyll").write_text("")  # GitHub Pages: serve the folders as they are
    (DIST / "CNAME").write_text(page.SITE.split("/")[2] + "\n")  # GitHub Pages: the site's own domain
    (DIST / ".gitattributes").write_text("".join(f"*.{e} binary\n" for e in ("bin", "wasm", "zip", "png", "woff2", "mp4", "jpg")))
    size = sum(p.stat().st_size for p in DIST.rglob("*") if p.is_file())
    print(f"dist/: {sum(1 for _ in DIST.rglob('*'))} files, {size / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
