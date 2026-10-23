# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10"]
# ///
"""Create a new pinyol game folder: a tiny but complete game you can play, validate and then make your own.

    uv run tools/new_game.py games/mygame --lua --title "My Game"   # a game in Lua (pinyol@2): any genre
    uv run tools/new_game.py games/mygame --title "My Game"         # an adventure made of data (pinyol@1)
    uv run tools/new_game.py games/mygame --lua --look "metal slug" # a Lua game for a console's look (tools/looks.json)

--lua copies templates/lua: a room bigger than the screen to walk around, gems to pick up, a camera, sounds and a
best time saved; its art.py draws the art from code, to replace with your own (docs/lua.md).
Without --lua: two zones, a player, one NPC with a dialogue and a choice, an item, a locked door, a chest and the end
screen, all data (docs/game-format.md). Every image is placeholder art drawn by code; replace any of them with
tools/png2asset.py, keeping the ID.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import re
import shutil
import struct
import subprocess
import sys
import wave
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import png2asset  # noqa: E402
import looks  # noqa: E402
import ttf2fnt  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
INK, PAPER, OCHRE, TERRA = (0x19, 0x33, 0x2C), (0xF2, 0xE9, 0xD2), (0xAF, 0x74, 0x3A), (0xA9, 0x57, 0x43)
GRASS, PATH, WALL, ROOF = (0x5E, 0x8C, 0x4A), (0xC6, 0xB0, 0x86), (0xD8, 0xC8, 0xA8), (0x9A, 0x4A, 0x2E)
WOOD, FLOOR, SKIN, DARK = (0x8B, 0x65, 0x48), (0xB8, 0x8E, 0x62), (0xD9, 0xA8, 0x86), (0x2A, 0x24, 0x22)
DIRS = "NESW"  # frame order of every character sheet: 4 directions, N E S W
TILE = 16      # zones are grids of 16 px tiles; 15x10 tiles = the 240x160 logical screen


def canvas(w: int, h: int, fill: tuple | None = None) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    img = Image.new("RGBA", (w, h), (*fill, 255) if fill else (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def person(top: tuple, hair: tuple, d: str, step: int = 0, reach: bool = False, crouch: int = 0) -> Image.Image:
    """24x32 character, feet at (12, 29). step: walk phase 0-3; reach: arm out; crouch: px lower."""
    img, dr = canvas(24, 32)
    dr.ellipse((6, 27, 18, 31), fill=(0, 0, 0, 90))
    s = (2, 0, -2, 0)[step]
    if d in "NS":
        dr.rectangle((8, 21, 11, 29 - max(0, s)), fill=(*DARK, 255))
        dr.rectangle((13, 21, 16, 29 - max(0, -s)), fill=(*DARK, 255))
    else:
        dr.rectangle((10 + s, 21, 13 + s, 29), fill=(*DARK, 255))
        dr.rectangle((10 - s, 21, 13 - s, 29), fill=(*DARK, 255))
    y = crouch
    dr.rectangle((7, 11 + y, 16, 22), fill=(*top, 255))
    if reach:
        x, ry = {"N": (10, 6), "S": (10, 20), "E": (18, 14), "W": (2, 14)}[d]
        dr.rectangle((x, ry + y, x + 4, ry + 3 + y), fill=(*top, 255))
    dr.ellipse((7, 1 + y, 16, 11 + y), fill=(*SKIN, 255))
    if d == "N":
        dr.ellipse((7, 1 + y, 16, 10 + y), fill=(*hair, 255))
    else:
        dr.rectangle((7, 1 + y, 16, 4 + y), fill=(*hair, 255))
        eyes = {"S": [(10, 7), (13, 7)], "E": [(14, 7)], "W": [(9, 7)]}[d]
        dr.point([(ex, ey + y) for ex, ey in eyes], fill=(*INK, 255))
    return img


def portrait(top: tuple, hair: tuple) -> list[Image.Image]:
    """64x64, four expressions: neutral, warm, worried, evasive (dialogue lines pick one by index)."""
    frames = []
    for expr in range(4):
        img, dr = canvas(64, 64, (0x42, 0x67, 0x51))
        dr.rectangle((14, 46, 50, 63), fill=(*top, 255))
        dr.ellipse((16, 12, 48, 50), fill=(*SKIN, 255))
        dr.chord((16, 8, 48, 34), 180, 360, fill=(*hair, 255))
        dx = 3 if expr == 3 else 0
        for x in (26, 38):
            dr.rectangle((x - 2 + dx, 29, x + 1 + dx, 32), fill=(*INK, 255))
        if expr == 1:
            dr.arc((25, 34, 39, 44), 20, 160, fill=(*INK, 255), width=2)
        elif expr == 2:
            dr.arc((25, 40, 39, 50), 200, 340, fill=(*INK, 255), width=2)
        else:
            dr.line((27 + dx, 41, 37 + dx, 41), fill=(*INK, 255), width=2)
        frames.append(img)
    return frames


def house(dr: ImageDraw.ImageDraw, x: int, y: int) -> None:
    dr.polygon([(x - 8, y + 24), (x + 40, y), (x + 88, y + 24)], fill=(*ROOF, 255))
    dr.rectangle((x, y + 24, x + 80, y + 72), fill=(*WALL, 255), outline=(*INK, 255))
    dr.rectangle((x + 32, y + 44, x + 48, y + 72), fill=(*WOOD, 255), outline=(*INK, 255))  # door
    for wx in (x + 8, x + 58):
        dr.rectangle((wx, y + 36, wx + 14, y + 50), fill=(0x6E, 0x9C, 0xA8, 255), outline=(*INK, 255))


def art(game: Path, title: str) -> None:
    a = game / "assets"
    you, friend = (OCHRE, DARK), (TERRA, (0x6B, 0x4A, 0x36))
    sheet = lambda **k: [person(*you, d, **k) for d in DIRS]  # noqa: E731
    png2asset.export(a, "PJ_IDLE", [person(*you, d) for d in DIRS for _ in (0, 1)], 600, (12, 29))
    png2asset.export(a, "PJ_WALK", [person(*you, d, p) for d in DIRS for p in range(4)], 125, (12, 29))
    png2asset.export(a, "PJ_INTERACT", [f for pair in zip(sheet(), sheet(reach=True)) for f in pair], 150, (12, 29))
    png2asset.export(a, "PJ_LISTEN", [person(*you, d, crouch=c) for d in DIRS for c in (3, 6)], 300, (12, 29))
    png2asset.export(a, "PJ_DESCEND", [person(*you, "S", p) for p in range(4)], 180, (12, 29))
    npc = [person(*friend, d) for d in DIRS for _ in (0, 1)] + [person(*friend, "S", reach=True)] * 2
    png2asset.export(a, "NPC_AMIGA", npc, 600, (12, 29))
    png2asset.export(a, "PT_PROTA", portrait(*you), 0, (0, 0))
    png2asset.export(a, "PT_AMIGA", portrait(*friend), 0, (0, 0))

    img, dr = canvas(240, 160, GRASS)  # Z01: outside, a house with a door at tile (7, 3)
    dr.rectangle((104, 72, 135, 160), fill=(*PATH, 255))
    house(dr, 80, 0)
    for tx, ty in ((2, 6), (12, 7), (3, 2)):
        dr.ellipse((tx * TILE, ty * TILE, tx * TILE + 20, ty * TILE + 16), fill=(0x3E, 0x6B, 0x3A, 255))
    png2asset.export(a, "BG_Z01", [img], 0, (0, 0), "background")

    img, dr = canvas(240, 160, DARK)  # Z02: inside, a chest at tile (7, 3)
    dr.rectangle((32, 32, 207, 143), fill=(*FLOOR, 255))
    for y in range(32, 144, 8):
        dr.line((32, y, 207, y), fill=(*WOOD, 255))
    dr.rectangle((32, 16, 207, 31), fill=(*WALL, 255))
    dr.rectangle((104, 44, 135, 60), fill=(*WOOD, 255), outline=(*INK, 255))
    dr.rectangle((104, 44, 135, 50), fill=(*OCHRE, 255), outline=(*INK, 255))
    dr.rectangle((112, 144, 127, 159), fill=(*FLOOR, 255))  # the doorway out
    png2asset.export(a, "BG_Z02", [img], 0, (0, 0), "background")

    img, dr = canvas(240, 160, GRASS)  # title backdrop: the left half stays clear for the logo
    dr.rectangle((0, 120, 239, 135), fill=(*PATH, 255))
    for x, y in ((150, 30), (200, 70), (170, 100), (20, 140)):
        dr.ellipse((x, y, x + 20, y + 16), fill=(0x3E, 0x6B, 0x3A, 255))
    png2asset.export(a, "BG_TITLE", [img], 0, (0, 0), "background")
    ttf = str(ROOT / "third_party" / "pixelify" / "PixelifySans.ttf")
    for aid, (w, h, px) in {"LOGO": (224, 128, 33), "LOGO_SMALL": (120, 64, 22)}.items():  # SMALL: the pause screen
        img, dr = canvas(w, h)
        font = ImageFont.truetype(ttf, px)
        dr.rounded_rectangle((0, 0, w - 1, h - 1), 8, fill=(*PAPER, 255), outline=(*INK, 255), width=3)
        dr.polygon([(w // 2 - 14, h // 2 - 8), (w // 2, h // 2 - 22), (w // 2 + 14, h // 2 - 8)], fill=(*ROOF, 255))
        dr.text((w // 2, h // 2 + 12), title, font=font, fill=(*INK, 255), anchor="mm")
        png2asset.export(a, aid, [img], 0, (0, 0), "ui")

    img, dr = canvas(16, 16)  # the key
    dr.ellipse((1, 4, 8, 11), outline=(*OCHRE, 255), width=2)
    dr.rectangle((8, 7, 15, 8), fill=(*OCHRE, 255))
    dr.rectangle((12, 9, 13, 11), fill=(*OCHRE, 255))
    png2asset.export(a, "IC_LLAVE", [img], 0, (0, 0))
    img, dr = canvas(16, 16)
    dr.rectangle((3, 5, 12, 14), fill=(*WOOD, 255))
    dr.arc((5, 1, 10, 8), 180, 360, fill=(*PAPER, 255))
    png2asset.export(a, "UI_BAG", [img], 0, (0, 0))
    img, dr = canvas(16, 16)
    dr.rectangle((3, 2, 12, 14), fill=(*TERRA, 255))
    dr.line((5, 2, 5, 14), fill=(*PAPER, 255))
    png2asset.export(a, "UI_BOOK", [img], 0, (0, 0))


def fonts(game: Path) -> None:
    """Pixelify Sans (SIL OFL): 22 px for text, 24 px for the large-text option."""
    ttf = str(ROOT / "third_party" / "pixelify" / "PixelifySans.ttf")
    for name, px, weight in (("FONT_MAIN", 22, 400), ("FONT_BOLD", 22, 600), ("FONT_MAIN_L", 24, 500), ("FONT_BOLD_L", 24, 600)):
        ttf2fnt.build(ttf, str(game / "fonts" / f"{name}.fnt"), px, 1, weight, 0)


def music(game: Path) -> None:
    """A 4-bar loop at 100 bpm, synthesised: mono PCM16 at 22050 Hz, the only WAV format the engine plays."""
    hz, beat = 22050, 22050 * 60 // 100
    tune = [72, 76, 79, 76, 74, 77, 81, 77, 72, 76, 79, 84, 79, 76, 74, 72]  # MIDI notes, one per beat
    out = bytearray()
    for i, note in enumerate(tune):
        f, bass = 440 * 2 ** ((note - 69) / 12), 440 * 2 ** ((48 + (0, 5, 7, 0)[i // 4] - 69) / 12)
        for n in range(beat):
            t, env = n / hz, math.exp(-4 * n / beat)
            v = 0.22 * env * (2 / math.pi) * math.asin(math.sin(2 * math.pi * f * t)) + 0.12 * math.sin(2 * math.pi * bass * t)
            out += struct.pack("<h", int(v * 32767))
    with wave.open(str(game / "audio" / "MUS_HOLA.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(hz)
        w.writeframes(bytes(out))


def zone(zid: str, name: str, floor: list[str], **rest) -> dict:
    return {"id": zid, "name": name, "size": [15, 10], "bg": f"BG_{zid}", "solid": "#", "floor": floor, **rest}


def content(gid: str, title: str) -> dict[str, object]:
    outside = ["###############", "###############", "###############", "#######.#######",
               "##...........##", "#.............#", "#.............#", "#.............#", "#.............#",
               "###############"]
    inside = ["###############", "###############", "###############", "##...........##", "##...........##",
              "##...........##", "##...........##", "##...........##", "##...........##", "#######.#######"]
    return {
        "game.json": {
            "id": gid, "title": title, "subtitle": "Un juego hecho con pinyol", "tagline": "Habla, coge la llave, abre el cofre.",
            "end_text": f"Fin · {title}", "engine": "pinyol@1", "content_version": 1,
            "player": {"speaker": "PROTA", "sprite": "PJ"},
            "title_layout": {"logo": [128, 28], "sub": [128, 236], "menu": [256, 70]},
            "speakers": {"PROTA": {"name": "Tú", "portrait": "PT_PROTA", "color": "#AF743A"},
                         "AMIGA": {"name": "Amiga", "portrait": "PT_AMIGA", "color": "#A95743"}},
            "start": {"zone": "Z01", "spawn": "start"},
            "zones": ["Z01", "Z02"], "dialogues": ["D_HOLA"], "flags": ["llave_dada", "cofre_abierto"],
            "objectives": [{"if": "!llave_dada", "text": "Habla con tu amiga."},
                           {"if": ["and", "llave_dada", "!cofre_abierto"], "text": "Entra en casa y abre el cofre."}],
        },
        "tiles.json": {"atlas": "TS_ATLAS", "families": {}, "legend": {"#": None, ".": None}},
        "items.json": {"IT_LLAVE": {"name": "Llave", "icon": "IC_LLAVE", "persistent": True, "desc": "La llave de casa."}},
        "events.json": {"EV_COFRE": {"if": "!cofre_abierto", "save": True, "do": [["set", "cofre_abierto"], ["dlg", "D_HOLA.cofre"]]}},
        "notebook.json": {}, "sequences.json": {}, "listen.json": {}, "puzzles.json": {},
        "music.json": {"title": {"cue": "MUS_HOLA", "tension": 1}, "end": {"cue": "MUS_HOLA", "tension": 1},
                       "cues": {"MUS_HOLA": {"bpm": 100, "beats": 4, "layers": [[0.6], [1], [1], [1]]}},
                       "zones": {"Z01": "MUS_HOLA", "Z02": "MUS_HOLA"}},
        "zones/Z01.json": zone("Z01", "La calle", outside,
            spawns={"start": [7, 7, "N"], "from_casa": [7, 4, "S"], "safe": [7, 6, "N"]},
            npcs=[{"id": "amiga", "name": "Amiga", "sprite": "NPC_AMIGA", "at": [4, 5], "facing": "E", "dlg": "D_HOLA.amiga"}],
            exits=[{"rect": [7, 3, 1, 1], "to": "Z02", "spawn": "from_calle", "if": ["has", "IT_LLAVE"],
                    "else": [["say", "Está cerrada. ¿Quién tendrá la llave?"]]}]),
        "zones/Z02.json": zone("Z02", "Casa", inside,
            spawns={"from_calle": [7, 8, "N"], "safe": [7, 7, "N"]},
            hotspots=[{"id": "cofre", "name": "Cofre", "verb": "Abrir", "at": [7, 4], "off": [0, -12], "reach": 26,
                       "do": [["event", "EV_COFRE"]]}],
            exits=[{"rect": [7, 9, 1, 1], "to": "Z01", "spawn": "from_casa"}]),
        "dialogues/D_HOLA.json": {"nodes": {
            "amiga": {"repeat": "amiga_2", "lines": [{"s": "AMIGA", "t": "¡Hola! Te estaba esperando."}], "next": "pregunta"},
            "pregunta": {"choices": [
                {"id": "llave", "text": "¿Tienes la llave de casa?", "next": "llave"},
                {"id": "adios", "text": "Luego hablamos.", "bye": True, "next": "adios"}]},
            "llave": {"lines": [{"s": "AMIGA", "t": "Toma. Dentro hay un cofre."}], "do": [["give", "IT_LLAVE"], ["set", "llave_dada"]]},
            "adios": {"lines": [{"s": "AMIGA", "t": "Aquí estaré."}]},
            "amiga_2": {"lines": [{"s": "AMIGA", "t": "El cofre está dentro de casa."}]},
            "cofre": {"lines": [{"s": "PROTA", "t": "Dentro hay una nota: «Ahora haz tu propio juego»."}], "do": [["end"]]},
        }},
    }


def lua_game(game: Path, title: str) -> None:
    """templates/lua with this game's id and title, its art drawn and converted, and the fonts."""
    shutil.copytree(ROOT / "templates" / "lua", game, dirs_exist_ok=True)
    meta = {"id": game.name, "title": title, "engine": "pinyol@2", "main": "main.lua", "author": "", "description": ""}
    (game / "game.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for sub in ("fonts", "saves", "tests"):
        (game / sub).mkdir(exist_ok=True)
    (game / "tests" / f"{game.name}.script").write_text("# plays the game: more lines as it grows (docs/lua.md, Testing)\nnew\ntick 60\nshot start\nexpect_ok\n", encoding="utf-8")
    fonts(game)
    subprocess.run([sys.executable, str(game / "art.py"), "--draw"], check=True, env={**os.environ, "PINYOL": str(ROOT)})


def apply_look(game: Path, look: dict, note: str) -> str:
    """Marks the game with its look: game.json's "look" and subtitle, the look's font pack, and look.md (its rules, limits and the example to start from)."""
    meta_path = game / "game.json"
    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    meta.update(look=look["id"], subtitle=look["name"])
    meta_path.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    subprocess.run([sys.executable, str(ROOT / "tools" / "font2fnt.py"), "--pack", look["font_pack"], str(game)], check=True, capture_output=True)
    lines = [f"# Look: {look['name']} ({look['era']})", "", f"Start from `examples/{look['example']}`. World: {look['world']}. Art: {look['method']}."
             f" Style line: *{look['style']}*.", "", "## Do", *[f"- {r}" for r in look["rules"]], "", "## Avoid", *[f"- {r}" for r in look["avoid"]], "",
             "The template's room, hero and gems (`art.py`, `room.lua`, `art/`, `assets/`) are placeholders in no look: replace them with art made by these rules.", "",
             f"Limits (checked by `uv run tools/look_check.py {game}`): {json.dumps(look['limits'])}.", "Rules in full: docs/art.md, section 'Choose a look'.",
             *(["", f"Note: {note}"] if note else [])]
    (game / "look.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return f"look {look['id']} ({look['name']}): font pack {look['font_pack']}, rules in {game}/look.md, start from examples/{look['example']}"


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("dir", type=Path, help="new game folder, e.g. games/mygame (its name is the game id)")
    p.add_argument("--title", default=None, help="the name shown in the game list (default: Hola pinyol, or the id)")
    p.add_argument("--lua", action="store_true", help="a Lua game (pinyol@2) from templates/lua")
    p.add_argument("--look", help="with --lua: the console the game is made for, as an id or the user's own words (\"game boy\", \"metal slug\"); see tools/looks.py")
    args = p.parse_args()
    found: tuple[dict, str] | None = None
    if args.look:
        if not args.lua:
            sys.exit("--look goes with --lua")
        ids, note = looks.resolve(args.look)
        if len(ids) != 1:
            sys.exit(f"{args.look!r} " + (f"fits several looks ({', '.join(ids)}): ask which one" if ids else "names no look: ask which console")
                     + " (uv run tools/looks.py --list)")
        found = looks.get(ids[0]), note
    game: Path = args.dir
    if game.exists() and any(game.iterdir()):
        sys.exit(f"{game} already exists and is not empty")
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,40}", game.name):
        sys.exit(f"{game.name}: a game's folder name is its id: 1-40 letters, digits, _ or -")
    if args.lua:
        lua_game(game, args.title or game.name)
        if found:
            print(apply_look(game, *found))
        print(f"{game}: ready. Try it: ./build/pinyol_sim --game {game}  (then edit {game}/main.lua)")
        return
    args.title = args.title or "Hola pinyol"
    for sub in ("assets", "fonts", "zones", "dialogues", "audio", "saves"):
        (game / sub).mkdir(parents=True, exist_ok=True)
    for rel, data in content(game.name, args.title).items():
        (game / rel).write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    art(game, args.title)
    fonts(game)
    music(game)
    print(f"{game}: ready. Try it: ./build/pinyol_sim --game {game}")


if __name__ == "__main__":
    main()
