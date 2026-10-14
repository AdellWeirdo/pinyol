# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10"]
# ///
"""Build a web gallery of games: each one playable in the browser and downloadable for the console.

    python3 tools/make_gallery.py out/ --player build-web --headless build/pinyol_headless examples/*

For each game folder: its zip (tools/pack_game.py), a picture of its title screen taken with pinyol_headless, and a
card in out/index.html, next to the web player (player.html/.js/.wasm from an Emscripten build, see the README).
Serve out/ over http (python3 -m http.server -d out).
"""
from __future__ import annotations

import argparse
import html
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import pack_game  # noqa: E402

PAGE = """<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Juegos pinyol</title>
<style>
  @font-face {{ font-family: "Pixelify Sans"; src: url(fonts/PixelifySans.ttf); font-display: swap; }}
  :root {{
    --bg: #11161a; --shelf: #1b2329; --ink: #e8dcc2; --dim: #9aa39c; --accent: #e0a040; --accent-ink: #1b1408;
    --cart: #c9c2b4; --cart-d: #8f887b; --label: #f2e9d2; --line: #2c363d;
  }}
  * {{ box-sizing: border-box; }}
  html, body {{ margin: 0; background: var(--bg); color: var(--ink); font: 16px/1.5 system-ui, sans-serif; }}
  main {{ max-width: 1100px; margin: 0 auto; padding: clamp(16px, 4vw, 48px) 16px 64px; }}
  header {{ margin-bottom: clamp(24px, 5vw, 56px); }}
  h1 {{ font: 700 clamp(2.2rem, 1.2rem + 5vw, 4.6rem)/1 "Pixelify Sans", system-ui; margin: 0 0 12px; letter-spacing: .01em; }}
  h1 span {{ color: var(--accent); }}
  .lede {{ max-width: 60ch; color: var(--dim); margin: 0; font-size: 1.05rem; }}
  .shelf {{ list-style: none; margin: 0; padding: 0; display: grid; gap: clamp(20px, 3vw, 36px);
            grid-template-columns: repeat(auto-fill, minmax(min(100%, 300px), 1fr)); }}
  /* each game is a cartridge: a notched grey shell, its label is the title screen */
  .cart {{ position: relative; display: flex; flex-direction: column; background: linear-gradient(180deg, var(--cart), var(--cart-d)); padding: 22px 18px 18px;
           clip-path: polygon(0 10px, 10px 0, 62% 0, 66% 8px, 100% 8px, 100% 100%, 0 100%);
           border-radius: 0 0 14px 14px; transition: transform .18s ease-out, filter .18s; }}
  .cart:hover, .cart:focus-within {{ transform: translateY(-6px) rotate(-.6deg); filter: drop-shadow(0 14px 18px #0008); }}
  .label {{ flex: 1; background: var(--label); border-radius: 6px; padding: 10px; box-shadow: inset 0 0 0 2px #0002; }}
  .label img {{ display: block; width: 100%; height: auto; aspect-ratio: 3 / 2; image-rendering: pixelated; border-radius: 3px;
               background: #000; }}
  .label h2 {{ font: 700 1.35rem/1.1 "Pixelify Sans", system-ui; color: #203040; margin: 10px 2px 4px; }}
  .label p {{ margin: 0 2px; color: #506070; font-size: .9rem; min-height: 2.7em; }}
  .grip {{ display: flex; gap: 6px; justify-content: center; margin: 12px 0 10px; }}
  .grip i {{ width: 26px; height: 4px; border-radius: 2px; background: #0002; }}
  .actions {{ display: flex; gap: 10px; }}
  .actions a {{ flex: 1; text-align: center; text-decoration: none; border-radius: 999px; padding: 9px 12px;
               font-weight: 650; font-size: .95rem; }}
  .play {{ background: #203040; color: var(--label); }}
  .play:hover {{ background: #2c4258; }}
  .get {{ background: #0000; color: #203040; box-shadow: inset 0 0 0 2px #20304066; }}
  .get:hover {{ box-shadow: inset 0 0 0 2px #203040; }}
  a:focus-visible {{ outline: 3px solid var(--accent); outline-offset: 2px; }}
  .meta {{ display: block; margin: 8px 2px 0; color: #6a7380; font-size: .8rem; }}
  footer {{ margin-top: 56px; color: var(--dim); font-size: .9rem; border-top: 1px solid var(--line); padding-top: 16px; }}
  @media (prefers-reduced-motion: reduce) {{ .cart {{ transition: none; }} .cart:hover {{ transform: none; }} }}
</style>
</head>
<body>
<main>
  <header>
    <h1>Juegos <span>pinyol</span></h1>
    <p class="lede">Para la consola Cirera y para el navegador. Juega aquí, o descarga el .zip y descomprímelo en la
    carpeta <code>games/</code> de la tarjeta microSD.</p>
  </header>
  <ul class="shelf">
{cards}
  </ul>
  <footer>Hecho con pinyol. Teclado: flechas o WASD, Z o Enter (A), X o Esc (B), C, P (START); en el móvil, botones en
  pantalla.</footer>
</main>
</body>
</html>
"""

CARD = """    <li class="cart">
      <div class="label">
        <img src="covers/{id}.png" width="480" height="320" alt="Pantalla de título de {title_attr}" loading="lazy">
        <h2>{title}</h2>
        <p>{description}</p>
        <span class="meta">{kind} · {size} KB</span>
      </div>
      <div class="grip" aria-hidden="true"><i></i><i></i><i></i></div>
      <div class="actions">
        <a class="play" href="player.html?game=games/{id}.zip">Jugar</a>
        <a class="get" href="games/{id}.zip" download>Descargar</a>
      </div>
    </li>"""


def cover(headless: Path, game: Path, out_png: Path) -> None:
    """The game's screen after a second and a half: its title, for most games."""
    with tempfile.TemporaryDirectory() as tmp:
        script = Path(tmp) / "cover.script"
        script.write_text("new\ntick 90\nshot cover\n")
        subprocess.run([str(headless), "--game", str(game), "--saves", tmp, "--fresh", "--script", str(script)],
                       check=True, capture_output=True)
        Image.open(Path(tmp) / "cover.ppm").save(out_png, optimize=True)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("out", type=Path)
    ap.add_argument("games", type=Path, nargs="+", help="game folders")
    ap.add_argument("--headless", type=Path, default=Path("build/pinyol_headless"))
    ap.add_argument("--player", type=Path, help="the folder with player.html, player.js and player.wasm")
    a = ap.parse_args()
    for sub in ("games", "covers", "fonts"):
        (a.out / sub).mkdir(parents=True, exist_ok=True)
    shutil.copy(HERE.parent / "third_party" / "pixelify" / "PixelifySans.ttf", a.out / "fonts")
    shutil.copy(HERE.parent / "third_party" / "pixelify" / "OFL.txt", a.out / "fonts")
    if a.player:
        for f in ("player.html", "player.js", "player.wasm"):
            shutil.copy(a.player / f, a.out / f)
    else:
        print("no --player: the cards' Jugar links need player.html next to index.html")
    cards = []
    for game in a.games:
        if not (game / "game.json").is_file():
            continue
        meta = json.loads((game / "game.json").read_text(encoding="utf-8"))
        gid = pack_game.game_id(game)
        z = pack_game.pack(game, a.out / "games", sources=False)
        cover(a.headless, game, a.out / "covers" / f"{gid}.png")
        title = meta.get("title", gid)
        lua = str(meta.get("engine", "")).startswith(("pinyol@2", "np2d@2"))  # np2d: the engine's first name
        cards.append(CARD.format(id=gid, title=html.escape(title), title_attr=html.escape(title, quote=True),
                                 description=html.escape(meta.get("description", "")),
                                 kind="Lua" if lua else "aventura de datos", size=z.stat().st_size // 1024))
    (a.out / "index.html").write_text(PAGE.format(cards="\n".join(cards)), encoding="utf-8")
    print(f"{a.out / 'index.html'}: {len(cards)} games")


if __name__ == "__main__":
    main()
