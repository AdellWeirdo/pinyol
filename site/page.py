"""pinyol's showcase page: the looks, the engine measured on the console, how to make a game, the console, the
making-of. build.py renders it into dist/index.html."""
from __future__ import annotations

from html import escape

import charts

REPO = "https://github.com/ipaud/pinyol"
SITE = "https://ipaud.github.io/pinyol/"  # where it will be published (GitHub Pages); only og:image needs it

# The twelve looks: their example, the console it follows, its frame rate on the console as (slowest, fastest
# second), and the first measure when the board made it faster (docs/measurements.md, "The looks on the console").
LOOKS = [
    dict(id="gameboy", name="Game Boy", example="bolsillo", era="1989 · cuatro verdes, pantalla entera", art=False, fps=(61, 61), hue="#8bac0f",
         what="Un plataformas con la paleta de la Game Boy, a pantalla completa.", alt="Un plataformas en cuatro tonos de verde a pantalla completa"),
    dict(id="spectrum", name="ZX Spectrum", example="cinta", era="1982 · dos colores por bloque", art=False, fps=(49, 61), hue="#ff3b3b",
         what="Con su carga de cinta, franjas de colores incluidas.", alt="Una sala de ZX Spectrum: bloques de dos colores, un minero y un guardián"),
    dict(id="pico8", name="PICO-8", example="ladrillos", era="2015 · 128×128 · dieciséis colores", art=False, fps=(56, 60), was=(46, 55), hue="#ff77a8",
         what="Un rompeladrillos en la paleta de la fantasy console.", alt="Un rompeladrillos de PICO-8 en dieciséis colores"),
    dict(id="lcd", name="Maquinita LCD", example="huevos", era="1980 · figuras que se encienden", art=False, fps=(61, 61), hue="#9aa58c",
         what="Un cocinero que recoge huevos, figura a figura.", alt="Una maquinita LCD: un cocinero recogiendo huevos, figuras encendidas o apagadas"),
    dict(id="vector", name="Vectorial", example="rocas", era="1979 · solo líneas que brillan", art=False, fps=(61, 61), hue="#7cf7ff",
         what="Rocas y una nave hechas de líneas sobre negro.", alt="Un juego vectorial: líneas brillantes sobre negro"),
    dict(id="gba", name="Game Boy Advance", example="plataformas", era="2001 · capas, sprites, agua que ondula", art=False, fps=(61, 61), hue="#6c5ce7",
         what="Paralaje, agua transparente y monedas.", alt="Un plataformas de Game Boy Advance con montañas en paralaje y agua"),
    dict(id="16bits", name="Super Nintendo · Mega Drive", example="veloz", era="1991 · velocidad y scroll por línea", art=False, fps=(40, 59), hue="#2f7bff",
         what="Un pangolín muy rápido y un mar que se mueve línea a línea.", alt="Un plataformas de 16 bits: tierra a cuadros y un mar movido línea a línea"),
    dict(id="32bits", name="PlayStation · Saturn 2D", example="gotico", era="1997 · 256 colores, luz mezclada", art=True, fps=(59, 61), was=(31, 31), hue="#b388ff",
         what="Un castillo de noche: velas que brillan y un fantasma a medias.", alt="La sala de un castillo gótico: brillos de vela, un fantasma y una cazadora con látigo"),
    dict(id="neogeo", name="Neo Geo", example="duelo", era="1990 · luchadores enormes", art=True, fps=(60, 61), hue="#ffc94a",
         what="Lucha uno contra uno en un muelle al atardecer.", alt="Un juego de lucha de Neo Geo: dos luchadores grandes en un muelle al atardecer"),
    dict(id="cps2", name="CPS2", example="torneo", era="1993 · quince colores por luchador", art=True, fps=(60, 61), hue="#e8344e",
         what="Lucha con un suelo en perspectiva dibujado en bandas.", alt="Un juego de lucha de CPS2: luchadores de quince colores sobre un suelo en perspectiva"),
    dict(id="vertical", name="Recreativa vertical", example="tormenta", era="1985 · la pantalla girada", art=False, fps=(30, 30), was=(20, 20), hue="#4dd2a1",
         what="Un matamarcianos para jugar con la consola de lado.", alt="Un matamarcianos vertical, girado: se juega con la consola de lado"),
    dict(id="firstperson", name="Primera persona", example="laberinto", era="1992 · a lo Wolfenstein 3D", art=False, fps=(38, 60), was=(20, 31), hue="#c08a5a",
         what="Un laberinto visto desde dentro, con fantasmas y gemas.", alt="Un laberinto en primera persona: pasillos de piedra y un fantasma"),
]
# The shelf's order on a wide screen: two big cartridges (the arcade and 16/32-bit looks), four small, and again
ORDER = ["neogeo", "cps2", "gameboy", "spectrum", "pico8", "lcd", "32bits", "16bits", "vector", "gba", "vertical", "firstperson"]
LOOKS = sorted(LOOKS, key=lambda k: ORDER.index(k["id"]))
BIG = {"neogeo", "cps2", "32bits", "16bits"}
HERO_EXTRA = [("loading", "La pantalla de carga de un juego de ZX Spectrum"), ("32bits_boss", "El jefe calavera girando y creciendo")]

# The other examples, playable too (id, title)
OTHERS = [
    ("asalto", "Asalto al cañón"), ("calle", "Calle de neón"), ("nubes", "Sobre las nubes"), ("futbol", "Gol de oro"),
    ("moto", "Moto costa"), ("mazmorra", "La mazmorra"), ("carreras", "Carreras"), ("naves", "Naves"), ("aldea", "La aldea"),
    ("puzle", "Puzle"), ("inventos", "Inventos"), ("estilos", "Estilos"), ("sonidos", "Sonidos"), ("control", "Control"),
    ("juntos", "Juntos"), ("hola", "Hola pinyol"),
]


def play_url(gid: str) -> str:
    return f"play/player.html?game=../games/{gid}.zip"


def header() -> str:
    return f"""<a class="skip" href="#main">Saltar al contenido</a>
<header class="top"><div class="wrap">
<a class="logo" href="#top" aria-label="pinyol, inicio"><img src="img/logo.png" alt="" width="64" height="42"></a>
<nav aria-label="Secciones"><ul>
<li class="keep"><a href="#aspectos">Juegos</a></li><li><a href="#rendimiento">Rendimiento</a></li>
<li><a href="#hazlo">Haz uno</a></li><li><a href="#consola">La consola</a></li><li><a href="#making">Cómo se hizo</a></li>
<li class="keep"><a href="{REPO}">GitHub</a></li></ul></nav>
</div></header>"""


def hero() -> str:
    shots = [(k["id"], k["alt"]) for k in LOOKS]
    imgs = "".join(f'<img src="img/looks/{i}.png" alt="" width="480" height="320" style="animation-delay:{n * 3}s"'
                   f'{" fetchpriority=high" if n == 0 else " loading=lazy"} decoding="async">' for n, (i, _) in enumerate(shots))
    return f"""<section class="hero" id="top" aria-labelledby="hero-title"><div class="wrap">
<div>
<p class="kicker pixel">Motor de juegos libre · ESP32-S3</p>
<h1 id="hero-title">Un motor, doce épocas</h1>
<p class="lede">pinyol hace juegos con la cara de las consolas de los 80 y 90 y los mueve a 60 fps en una consola de bolsillo con un ESP32‑S3. Dile a tu agente de código qué aspecto quieres y lo construye. Aquí puedes jugarlos todos.</p>
<div class="actions"><a class="btn btn-primary" href="#aspectos">Jugar ahora</a><a class="btn btn-ghost" href="{REPO}">Ver el código</a></div>
<p class="meta">Código MIT · arte y sonido CC0 · {len(LOOKS) + len(OTHERS)} juegos de ejemplo</p>
</div>
<div><div class="device" data-live role="img" aria-label="La consola mostrando, uno tras otro, los doce aspectos"><div class="screen">{imgs}</div></div>
<p class="screen-label pixel">480×320 · 60 fps · en la placa</p></div>
</div></section>"""


def cart(k: dict, n: int) -> str:
    fps = charts.fps_range(k["fps"])
    low = " low" if k["fps"][0] < 56 else ""
    made = "arte generado con IA" if k["art"] else "dibujado con código"
    big = " big" if k["id"] in BIG else ""
    return f"""<li class="cart{big}" style="--hue:{k['hue']}">
<div class="shot"><img src="img/looks/{k['id']}.png" alt="{escape(k['alt'])}" width="480" height="320" loading="lazy" decoding="async"></div>
<div class="label"><p class="era pixel">{escape(k['era'])}</p><h3>{escape(k['name'])}</h3><p class="what">{escape(k['what'])}</p>
<ul class="chips"><li class="chip fps{low}">{fps} fps en la consola</li><li class="chip">{made}</li></ul>
<div class="row"><a class="play" href="{play_url(k['example'])}" aria-label="Jugar a {escape(k['example'])} ({escape(k['name'])})">Jugar</a>
<a class="zip" href="games/{k['example']}.zip" download aria-label="Descargar {escape(k['example'])} para la consola">Descargar .zip</a></div></div></li>"""


def looks() -> str:
    carts = "".join(cart(k, n) for n, k in enumerate(LOOKS))
    others = "".join(f'<li><a href="{play_url(g)}">{escape(t)}</a></li>' for g, t in OTHERS)
    return f"""<section id="aspectos" aria-labelledby="aspectos-t"><div class="wrap">
<h2 id="aspectos-t">Doce aspectos, un motor</h2>
<p class="intro">Cada cartucho es un ejemplo jugable con las reglas de su consola: su resolución, sus colores, sus capas. Se juega con el teclado (flechas y Z, X) o con los botones de la pantalla en el móvil. Las cifras de fps son de la consola real, jugando.</p>
<ul class="shelf">{carts}</ul>
<div class="more"><h3>Y {len(OTHERS)} ejemplos más</h3><ul>{others}</ul></div>
</div></section>"""


def performance(board: dict, tests: int) -> str:
    return f"""<section id="rendimiento" class="perf" aria-labelledby="perf-t"><div class="wrap">
<p class="kicker pixel">ESP32-S3R8 · 240 MHz · PSRAM octal a 80 MHz · pantalla QSPI a 80 MHz</p>
<h2 id="perf-t">Medido en la consola, no prometido</h2>
<p class="intro">Cada cifra de esta sección sale de la placa: un firmware que juega solo con un guion y escribe una línea de rendimiento por segundo, o un banco de pruebas que repite cada escena cinco veces. Nada de emulador. Un frame a 60 fps tiene 16,6 ms.</p>
{charts.stats_band(board, tests)}
{charts.looks_chart(LOOKS)}
{charts.traces_chart(board)}
{charts.strips_demo('img/looks/neogeo.png', 'img/looks/32bits.png', 'Animación: la pantalla dividida en 15 franjas; cada una se llena desde arriba, mitad por el núcleo 0 y mitad por el núcleo 1, y luego aparece en el panel mientras se dibuja la siguiente')}
{charts.profile_chart(board)}
{charts.cost_chart()}
<p class="source">Fuente: <a href="{REPO}/blob/main/docs/measurements.md">docs/measurements.md</a>, con el método y cada medida desde el primer día. Mídelo en tu placa:
<code>idf.py -DBP_BENCH=ON build flash monitor</code></p>
</div></section>"""


def code(text: str) -> str:
    first = text.splitlines()[0]
    return (f'<div class="code"><pre><code>{escape(text)}</code></pre>'
            f'<button class="copy" type="button" aria-label="Copiar: {escape(first)}">Copiar</button></div>')


def make_one() -> str:
    return f"""<section id="hazlo" aria-labelledby="hazlo-t"><div class="wrap">
<h2 id="hazlo-t">Hazte un juego</h2>
<p class="intro">pinyol está pensado para hacerse con un agente de código, como Codex o Claude Code. El agente lee las instrucciones del repositorio, instala lo que falta, sigue la receta del aspecto que pidas y prueba el juego antes de dártelo.</p>
<ol class="steps">
<li><h3>Baja el motor</h3><p>En un Mac con Homebrew o en Linux.</p>{code(f"git clone {REPO}.git" + chr(10) + "cd pinyol")}</li>
<li><h3>Pídeselo a tu agente</h3><p>Abre la carpeta con tu agente y dile qué quieres, en tu idioma.</p>{code("Hazme un plataformas con aspecto Game Boy: un ratón que busca queso en una biblioteca.")}</li>
<li><h3>Juégalo</h3><p>En tu pantalla, o pásalo a la consola por USB.</p>{code("./build/pinyol_sim --game games/raton")}</li>
</ol>
<div class="aside-note"><b>¿Sin programar?</b> El <a href="editor/">editor web</a> dibuja los sprites píxel a píxel, pinta los mapas y prueba el juego en el mismo navegador.</div>
</div></section>"""


def console() -> str:
    spec = [("Placa", "Freenove FNK0104N"), ("Chip", "ESP32-S3R8, dos núcleos a 240 MHz"), ("Memoria", "512 KB de RAM interna, 8 MB de PSRAM, 16 MB de flash"),
            ("Pantalla", "3,5″, 480×320, ST77922 por QSPI, táctil"), ("Sonido", "ES8311 con altavoz"), ("Lo demás", "microSD, batería, USB")]
    dl = "".join(f"<dt>{escape(a)}</dt><dd>{escape(b)}</dd>" for a, b in spec)
    return f"""<section id="consola" aria-labelledby="consola-t"><div class="wrap">
<h2 id="consola-t">La consola</h2>
<p class="intro">Una placa de desarrollo con pantalla que se compra hecha. El motor la exprime: dibuja directamente en franjas, reparte el trabajo entre los dos núcleos y guarda en la tarjeta lo que no cabe.</p>
<div class="hw"><dl class="spec">{dl}</dl>
<div class="pending"><h3>La carcasa, en preparación</h3><p>Carcasa imprimible, botones y lista de materiales para montarla tú. Mientras tanto, la placa sola ya juega.</p>
<p><a href="{REPO}/blob/main/docs/hardware.md">Cómo conectarla</a> · <a href="https://github.com/Freenove/Freenove_ESP32_S3_Display">La placa de Freenove</a></p></div></div>
</div></section>"""


def making(stats: dict) -> str:
    items = [(stats["c_lines"], "líneas de C en el motor"), (stats["examples"], "juegos de ejemplo"), (stats["tests"], "pruebas en cada cambio"),
             (stats["commits"], "commits en el repositorio")]
    li = "".join(f'<li><b data-count="{v}" data-dec="0">{thousands(v)}</b><span>{escape(t)}</span></li>' for v, t in items)
    return f"""<section id="making" aria-labelledby="making-t"><div class="wrap">
<h2 id="making-t">Cómo se hizo</h2>
<ul class="stats reveal">{li}</ul>
<div class="story">
<p><strong>Una persona y Claude.</strong> El motor, los ejemplos, las herramientas y esta web se escribieron hablando con Claude Code: cada idea se probaba en el simulador, se medía en la placa y se corregía con lo que la placa decía.</p>
<p><strong>El arte, generado y encajado.</strong> Los aspectos que lo piden (Neo Geo, CPS2, 32 bits) usan imágenes generadas con IA. Unas herramientas del motor las recortan, las escalan a la altura justa, separan los fotogramas y las reducen a la paleta de la consola. Los aspectos pequeños se dibujan con código.</p>
<p><strong>Medido antes de darlo por bueno.</strong> Cada ejemplo tiene un guion que lo juega solo. En el ordenador compara la suma de control de cada frame con la guardada; en la placa escribe los fps de cada segundo. Las optimizaciones no cambian ni un píxel.</p>
<p><strong>Libre de verdad.</strong> El código es MIT; el arte, el sonido y los vídeos de los ejemplos, CC0. Cógelo, cámbialo, haz tu consola.</p>
</div>
<p class="source">Todo el proceso está en el repositorio: <a href="{REPO}/blob/main/docs/art.md">cómo se hace el arte</a>, <a href="{REPO}/blob/main/docs/lua.md">la API de Lua</a>, <a href="{REPO}/blob/main/AGENTS.md">las instrucciones para agentes</a>.</p>
</div></section>"""


def thousands(v: int) -> str:
    """As Spanish writes them: 15.095, but 1234."""
    return f"{v:,}".replace(",", ".") if v >= 10000 else str(v)


def footer() -> str:
    return f"""<footer><div class="wrap"><img src="img/logo.png" alt="pinyol" width="64" height="42" loading="lazy">
<span>Código MIT · arte y sonido CC0</span><a href="{REPO}">GitHub</a><a href="{REPO}/blob/main/docs/measurements.md">Mediciones</a></div></footer>"""


def render(board: dict, stats: dict) -> str:
    desc = "pinyol: un motor de juegos libre con doce aspectos retro (Game Boy, Neo Geo, CPS2, PlayStation…) que corre a 60 fps en una consola ESP32-S3 y en el navegador."
    csp = ("default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self'; font-src 'self'; "
           "connect-src 'self'; object-src 'none'; base-uri 'self'; form-action 'none'")
    return f"""<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="{csp}">
<title>pinyol · un motor, doce épocas</title>
<meta name="description" content="{escape(desc)}">
<meta property="og:title" content="pinyol · un motor, doce épocas">
<meta property="og:description" content="{escape(desc)}">
<meta property="og:type" content="website">
<meta property="og:image" content="{SITE}img/og.png">
<meta name="theme-color" content="#0b0e1f">
<link rel="icon" href="img/icon.png">
<link rel="preload" href="fonts/jersey15.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="styles.css">
<script src="site.js" defer></script>
</head>
<body>
{header()}
<main id="main">
{hero()}
{looks()}
{performance(board, stats['tests'])}
{make_one()}
{console()}
{making(stats)}
</main>
{footer()}
</body>
</html>
"""
