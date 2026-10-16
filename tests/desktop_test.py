"""The desktop app's install (platform/sdl/desktop.c) on what people may drop on its window: a game zipped either way,
paths that climb out or start at the root, links, odd names, the console's menu, a file that is no zip, a game
installed again over its saves. In a folder with accents, as a player's may be.

    python3 tests/desktop_test.py build/desktop_test
"""
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

GAME = '{"id": "x", "title": "X", "engine": "pinyol@2"}'


def install(games: Path, *zips: Path) -> list[str]:
    out = subprocess.run([sys.argv[1], str(games), *map(str, zips)], capture_output=True, text=True, check=True,
                         encoding="utf-8")
    return out.stdout.split()


def zipped(path: Path, files: dict, links: dict | None = None) -> Path:
    with zipfile.ZipFile(path, "w") as z:
        for name, text in files.items():
            z.writestr(name, text)
        for name, target in (links or {}).items():  # a Unix link, as a zip made on a Mac or Linux can hold
            info = zipfile.ZipInfo(name)
            info.create_system, info.external_attr = 3, 0o120777 << 16
            z.writestr(info, target)
    return path


with tempfile.TemporaryDirectory() as t:
    t = Path(t) / "Jocs d'Àvila"
    games = t / "games"
    games.mkdir(parents=True)
    top = zipped(t / "suelto.zip", {"game.json": GAME, "main.lua": "-- 1"})
    folder = zipped(t / "descarga (1).zip", {"naves/game.json": GAME, "naves/main.lua": "-- 1"})
    odd = zipped(t / "..zip", {"game.json": GAME})
    spaced = zipped(t / "mi juego (2).zip", {"game.json": GAME})
    assert install(games, top, folder, odd, spaced) == ["suelto", "naves", "_", "mi_juego__2_"]
    assert (games / "suelto/main.lua").read_text() == "-- 1" and (games / "naves/game.json").exists()

    evil = zipped(t / "evil.zip", {"juego/game.json": GAME, "../../escape.lua": "x", str(t / "abs.lua"): "x"})
    assert install(games, evil) == ["-"]  # (tar refuses the "..", and so the whole zip)
    assert not (t / "escape.lua").exists() and not (t.parent / "escape.lua").exists() and not (t / "abs.lua").exists()

    victim = t / "victim"
    victim.mkdir()
    (victim / "keep.txt").write_text("mine")
    linked = zipped(t / "link.zip", {"g/game.json": GAME}, {"g/docs": str(victim), "g/note": str(victim / "keep.txt")})
    assert install(games, linked, linked) == ["-", "-"]
    assert (victim / "keep.txt").read_text() == "mine" and not (games / "g").exists()

    menu = zipped(t / "menu.zip", {"Cirera/game.json": GAME})
    nozip = t / "nozip.zip"
    nozip.write_text("hola")
    empty = zipped(t / "empty.zip", {"readme.txt": "no game"})
    assert install(games, menu, nozip, empty) == ["-", "-", "-"]
    assert not (games / "Cirera").exists()

    (games / "naves/saves").mkdir()
    (games / "naves/saves/slot0.sav").write_text("partida")
    again = zipped(t / "naves.zip", {"naves/game.json": GAME, "naves/main.lua": "-- 2", "naves/saves/slot0.sav": "suya"})
    assert install(games, again) == ["naves"]
    assert (games / "naves/main.lua").read_text() == "-- 2" and (games / "naves/saves/slot0.sav").read_text() == "partida"
    assert sorted(p.name for p in games.iterdir()) == ["_", "mi_juego__2_", "naves", "suelto"]  # (no .instalando left)
print("desktop install: ok")
