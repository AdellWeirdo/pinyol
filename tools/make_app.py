"""The Cirera desktop app, packed to download: Cirera.app for macOS, or a Cirera folder for Windows or Linux, each with
the console's menu (firmware/cirera) and the examples inside.

    cmake -B build-app -DCMAKE_BUILD_TYPE=Release -DPINYOL_APP=ON && cmake --build build-app --target pinyol_sim
    python3 tools/make_app.py build-app/Cirera -o dist/             # on a Mac: dist/Cirera-mac.zip
    python3 tools/make_app.py build-win-app/Cirera.exe -o dist/     # dist/Cirera-windows.zip (cross-built, README)
    python3 tools/make_app.py build-app/Cirera -o dist/             # on Linux: dist/Cirera-linux-x86_64.tar.gz

The games go in as tools/pack_game.py packs them: what the console reads, no art sources, no saves. games/.stamp
says which games they are, so the app copies them again to the player's folder when a newer app brings others
(platform/sdl/desktop.c). The Mac app is signed ad hoc: macOS opens it once the player allows it (the README says
how), as it does every app not notarized by Apple.
"""
from __future__ import annotations

import argparse
import hashlib
import platform
import plistlib
import shutil
import subprocess
import sys
import tarfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import pack_game  # noqa: E402

DESKTOP = ROOT / "platform/desktop"


def copy_game(folder: Path, to: Path) -> list[Path]:
    """The files of a game the console reads, copied into `to`."""
    out = []
    for p in sorted(folder.rglob("*")):
        rel = p.relative_to(folder)
        if p.is_file() and not p.is_symlink() and not pack_game.SKIP & set(rel.parts) and pack_game.runtime_file(rel):
            (to / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(p, to / rel)
            out.append(to / rel)
    return out


def fill(res: Path, games: list[Path]) -> None:
    """What the app reads beside itself: the menu, the games with their stamp, the window's icon, the licences."""
    copy_game(ROOT / "firmware/cirera", res / "menu")
    stamp = hashlib.sha256()
    for g in games:
        gid = pack_game.game_id(g)
        for f in copy_game(g, res / "games" / gid):
            stamp.update(f.relative_to(res).as_posix().encode() + b"\0" + f.read_bytes())
    (res / "games/.stamp").write_text(stamp.hexdigest() + "\n")
    shutil.copy2(DESKTOP / "icon.bmp", res / "icon.bmp")
    shutil.copy2(ROOT / "LICENSE", res / "LICENSE.txt")
    shutil.copy2(ROOT / "THIRD_PARTY_NOTICES.md", res / "THIRD_PARTY_NOTICES.md")


def mac(binary: Path, out: Path, games: list[Path], version: str) -> Path:
    app = out / "Cirera.app"
    shutil.rmtree(app, ignore_errors=True)
    (app / "Contents/MacOS").mkdir(parents=True)
    res = app / "Contents/Resources"
    res.mkdir()
    shutil.copy2(binary, app / "Contents/MacOS/Cirera")
    shutil.copy2(DESKTOP / "Cirera.icns", res / "Cirera.icns")
    fill(res, games)
    with open(app / "Contents/Info.plist", "wb") as f:
        plistlib.dump({
            "CFBundleName": "Cirera", "CFBundleDisplayName": "Cirera", "CFBundleExecutable": "Cirera",
            "CFBundleIdentifier": "io.github.ipaud.cirera", "CFBundlePackageType": "APPL",
            "CFBundleIconFile": "Cirera", "CFBundleShortVersionString": version, "CFBundleVersion": version,
            "LSMinimumSystemVersion": "11.0", "LSApplicationCategoryType": "public.app-category.games",
            "NSHighResolutionCapable": True, "NSHumanReadableCopyright": "MIT License, the pinyol authors",
        }, f)
    subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(app)], check=True)
    zip_path = out / "Cirera-mac.zip"
    zip_path.unlink(missing_ok=True)
    subprocess.run(["ditto", "-c", "-k", "--keepParent", str(app), str(zip_path)], check=True)  # (keeps the signature)
    return zip_path


def windows(binary: Path, out: Path, games: list[Path]) -> Path:
    folder = out / "Cirera"
    shutil.rmtree(folder, ignore_errors=True)
    folder.mkdir(parents=True)
    shutil.copy2(binary, folder / "Cirera.exe")
    fill(folder, games)
    zip_path = out / "Cirera-windows.zip"
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for p in sorted(folder.rglob("*")):
            if p.is_file():
                z.write(p, p.relative_to(out).as_posix())
    return zip_path


def linux(binary: Path, out: Path, games: list[Path]) -> Path:
    folder = out / "Cirera"
    shutil.rmtree(folder, ignore_errors=True)
    folder.mkdir(parents=True)
    shutil.copy2(binary, folder / "Cirera")
    (folder / "Cirera").chmod(0o755)
    fill(folder, games)
    tar_path = out / f"Cirera-linux-{platform.machine()}.tar.gz"
    with tarfile.open(tar_path, "w:gz") as t:  # (it keeps Cirera runnable, as a zip would not)
        t.add(folder, arcname="Cirera")
    return tar_path


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("binary", type=Path, help="the app built with -DPINYOL_APP=ON: Cirera (macOS) or Cirera.exe")
    ap.add_argument("-o", "--out", type=Path, default=Path("dist"))
    ap.add_argument("--games", type=Path, nargs="*", help="game folders to bring (default: examples/*)")
    ap.add_argument("--version", default="1.0")
    a = ap.parse_args()
    games = a.games or sorted(p.parent for p in (ROOT / "examples").glob("*/game.json"))
    a.out.mkdir(parents=True, exist_ok=True)
    if a.binary.suffix == ".exe":
        z = windows(a.binary, a.out, games)
    elif sys.platform == "darwin":
        z = mac(a.binary, a.out, games, a.version)
    elif sys.platform.startswith("linux"):
        z = linux(a.binary, a.out, games)
    else:
        sys.exit("the Mac app is made on a Mac (codesign, ditto), the Linux one on Linux")
    print(f"{z}: {len(games)} games, {z.stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
