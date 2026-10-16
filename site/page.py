"""pinyol's showcase page: the looks, the engine measured on the console, how to make a game, the console, the
making-of. build.py renders it into dist/index.html."""
from __future__ import annotations

import re
from html import escape

import charts
import i18n

REPO = "https://github.com/ipaud/pinyol"
RAW = "https://raw.githubusercontent.com/ipaud/pinyol/main"  # the Library's games, read when the page opens
SITE = "https://ipaud.github.io/pinyol/"
STATS = "https://raw.githubusercontent.com/ipaud/pinyol/stats/stats.json"  # each game's numbers and the ranking: tools/stats.py, daily
COUNTER = "https://pinyol.goatcounter.com"  # GoatCounter: visits and plays, no cookies, nothing personal (vendor/goatcounter)  # where it will be published (GitHub Pages); only og:image needs it

# The twelve looks: their example, the console it follows, its frame rate on the console as (slowest, fastest
# second), and the first measure when the board made it faster (docs/measurements.md, "The looks on the console").
LOOKS = [
    dict(id="gameboy", name="Game Boy", example="bolsillo", era="1989 · cuatro verdes, pantalla completa", art=False, fps=(61, 61), hue="#8bac0f",
         what="Un plataformas con la paleta de la Game Boy, a pantalla completa.", alt="Un plataformas en cuatro tonos de verde, a pantalla completa"),
    dict(id="spectrum", name="ZX Spectrum", example="cinta", era="1982 · dos colores por bloque", art=False, fps=(49, 61), hue="#ff3b3b",
         what="Incluye la carga de cinta, con sus franjas de colores.", alt="Una sala de ZX Spectrum: bloques de dos colores, un minero y un guardián"),
    dict(id="pico8", name="PICO-8", example="ladrillos", era="2015 · 128×128 · dieciséis colores", art=False, fps=(56, 60), was=(46, 55), hue="#ff77a8",
         what="Un rompeladrillos con la paleta de esta consola de fantasía.", alt="Un rompeladrillos de PICO-8 en dieciséis colores"),
    dict(id="lcd", name="Maquinita LCD", example="huevos", era="1980 · figuras que se encienden", art=False, fps=(61, 61), hue="#9aa58c",
         what="Un cocinero que recoge huevos y se mueve figura a figura.", alt="Una maquinita LCD: un cocinero que recoge huevos, con figuras que se encienden y se apagan"),
    dict(id="vector", name="Vectorial", example="rocas", era="1979 · solo líneas que brillan", art=False, fps=(61, 61), hue="#7cf7ff",
         what="Rocas y una nave hechas de líneas sobre negro.", alt="Un juego vectorial: líneas brillantes sobre negro"),
    dict(id="gba", name="Game Boy Advance", example="plataformas", era="2001 · capas, sprites, agua que ondula", art=False, fps=(61, 61), hue="#6c5ce7",
         what="Montañas en paralaje, agua transparente y monedas.", alt="Un plataformas de Game Boy Advance con montañas en paralaje y agua"),
    dict(id="16bits", name="Super Nintendo · Mega Drive", example="veloz", era="1991 · velocidad y scroll por línea", art=False, fps=(40, 59), hue="#2f7bff",
         what="Un pangolín muy rápido y un mar que se mueve línea a línea.", alt="Un plataformas de 16 bits: tierra a cuadros y un mar que se mueve línea a línea"),
    dict(id="32bits", name="PlayStation · Saturn 2D", example="gotico", era="1997 · 256 colores, luces translúcidas", art=True, fps=(59, 61), was=(31, 31), hue="#b388ff",
         what="Un castillo de noche: velas que brillan y un fantasma semitransparente.", alt="La sala de un castillo gótico: velas que brillan, un fantasma y una cazadora con látigo"),
    dict(id="neogeo", name="Neo Geo", example="duelo", era="1990 · luchadores enormes", art=True, fps=(60, 61), hue="#ffc94a",
         what="Lucha uno contra uno en un muelle al atardecer.", alt="Un juego de lucha de Neo Geo: dos luchadores grandes en un muelle al atardecer"),
    dict(id="cps2", name="CPS2", example="torneo", era="1993 · quince colores por luchador", art=True, fps=(60, 61), hue="#e8344e",
         what="Lucha sobre un suelo en perspectiva dibujado en bandas.", alt="Un juego de lucha de CPS2: luchadores de quince colores sobre un suelo en perspectiva"),
    dict(id="vertical", name="Recreativa vertical", example="tormenta", era="1985 · la pantalla girada", art=False, fps=(30, 30), was=(20, 20), hue="#4dd2a1",
         what="Un matamarcianos para jugar con la consola de lado.", alt="Un matamarcianos vertical que se juega con la consola de lado"),
    dict(id="firstperson", name="Primera persona", example="laberinto", era="1992 · a lo Wolfenstein 3D", art=False, fps=(38, 60), was=(20, 31), hue="#c08a5a",
         what="Un laberinto visto desde dentro, con fantasmas y gemas.", alt="Un laberinto en primera persona: pasillos de piedra y un fantasma"),
]
# The shelf's order on a wide screen: two big cartridges (the arcade and 16/32-bit looks), four small, and again
ORDER = ["neogeo", "cps2", "gameboy", "spectrum", "pico8", "lcd", "32bits", "16bits", "vector", "gba", "vertical", "firstperson"]
LOOKS = sorted(LOOKS, key=lambda k: ORDER.index(k["id"]))
BIG = {"neogeo", "cps2", "32bits", "16bits"}
HIGHLIGHTS = {"neogeo", "cps2", "32bits", "gba", "gameboy", "spectrum"}  # the home page's six
HERO_EXTRA = [("loading", "La pantalla de carga de un juego de ZX Spectrum"), ("32bits_boss", "El jefe calavera girando y creciendo")]

# The other examples, playable too (id, title)
OTHERS = [
    ("asalto", "Asalto al cañón"), ("calle", "Calle de neón"), ("nubes", "Sobre las nubes"), ("futbol", "Gol de oro"),
    ("moto", "Moto costa"), ("mazmorra", "La mazmorra"), ("carreras", "Carreras"), ("naves", "Naves"), ("aldea", "La aldea"),
    ("puzle", "Puzle"), ("inventos", "Inventos"), ("estilos", "Estilos"), ("sonidos", "Sonidos"), ("control", "Control"),
    ("juntos", "Juntos"), ("hola", "Hola pinyol"),
]

# The ladder: games Codex made, one request each, on a fresh clone with nothing but AGENTS.md (2026-10-14), from the
# simplest to the hardest. Times, commands and tokens from its logs; fps on the console, each game playing its own test
# (an autotest build). "after" says what was retouched by hand later, so the page claims no more than Codex did.
CODEX_RUN = "Codex 0.155 y gpt-6-sol, razonamiento medio"
CODEX = [
    dict(id="paletes", level=1, title="Paletes", look="Vectorial", minutes=3.5, time="3 min 30 s", commands=29, tokens="73 mil",
         fps="61", prompt="Hazme un Pong contra la consola: dos palas, una pelota y un marcador hasta 7 puntos. No me preguntes nada, decide tú.",
         after="Sin retoques.", alt="Paletes, con aspecto vectorial: dos palas, la pelota y el marcador"),
    dict(id="raton_de_biblioteca", level=2, title="Ratón de biblioteca", look="Game Boy", minutes=4.8, time="4 min 49 s",
         commands=29, tokens="78 mil", fps="59",
         prompt="Hazme un juego con aspecto de Game Boy: un ratón que recorre una biblioteca saltando entre estanterías y "
                "recogiendo trozos de queso, con gatos que patrullan. Que funcione y se vea bien. No me preguntes nada, decide tú.",
         after="Retocado después: a pantalla completa, sin el marco de la consola.",
         alt="Un ratón saltando entre estanterías de una biblioteca, en cuatro tonos de verde"),
    dict(id="oxigeno", level=3, title="Oxígeno 48K", look="ZX Spectrum", minutes=5.0, time="5 min 2 s", commands=40,
         tokens="104 mil", fps="30–60",
         prompt="Quiero un juego con aspecto de ZX Spectrum, con su pantalla de carga de cinta: un astronauta en una estación "
                "espacial que recoge botellas de oxígeno antes de que se le acabe el aire, esquivando robots. No me preguntes nada, decide tú.",
         after="Retocado después: el título de la portada y los textos, para que quepan en sus cuadros.",
         alt="La pantalla de carga: un astronauta con una botella de oxígeno ante una estación espacial"),
    dict(id="museo_nocturno", level=4, title="Museo de medianoche", look="Primera persona", minutes=6.1, time="6 min 8 s",
         commands=33, tokens="84 mil", fps="42",
         prompt="Hazme un juego en primera persona tipo Wolfenstein: un museo de noche, buscas cinco cuadros robados mientras "
                "esquivas a los vigilantes. No me preguntes nada, decide tú.",
         after="Retocado después: el texto de la pantalla final.",
         alt="Un pasillo de museo visto en primera persona, con un cuadro al fondo"),
    dict(id="costa_relampago", level=5, title="Ardilla Relámpago", look="Mega Drive", minutes=18.6, time="18 min 34 s",
         commands=102, tokens="252 mil", fps="59",
         prompt="Hazme un plataformas de velocidad con aspecto de Mega Drive: una ardilla que corre por una costa con rampas y "
                "bucles, varias capas de fondo moviéndose a distintas velocidades, el mar del fondo ondulando línea a línea, "
                "enemigos y frutas que recoger. Que vaya rápido y se vea bien. No me preguntes nada, decide tú.",
         after="Tres encargos: el juego (4 min 41 s); el arte, generado con IA (10 min 8 s; con él iba a 30 fps), y hacerlo "
               "ir a 60 fps en la consola con un suelo hecho a medida (3 min 45 s). Sin retoques a mano.",
         alt="Una ardilla corriendo por una costa con palmeras, colinas y el mar"),
]


def play_url(gid: str) -> str:
    """A game played on the Juega tab (the bare player, play/player.html, is the tab's frame and the editor's)."""
    return f"{HOME}juega/?juego={gid}"


# The site's tabs: a page each, in each language (publish()). HOME is a page's way to its language's home page, made
# right for each page's folder when it is published.
HOME = "@HOME@"
TABS = [("juega/", "Juega"), ("biblioteca/", "Biblioteca"), ("crear/", "Crear"), ("consola/", "Consola"), ("como-se-hizo/", "Cómo se hizo")]  # (the logo: home)


def header(tab: str, path: str | None = None) -> str:
    """The logo, the tabs (tab: the one this page is in) and the languages (path: this page's, if not the tab's)."""
    current = ' aria-current="page"'
    items = "".join(f'<li><a href="{HOME}{t}"{current if t == tab else ""}>{name}</a></li>' for t, name in TABS)
    return f"""<a class="skip" href="#main">Saltar al contenido</a>
<header class="top"><div class="wrap">
<a class="logo" href="{HOME}" aria-label="pinyol, inicio"><span class="logo-anim"><img class="l-leaves" src="img/logo/leaves.png" alt="" width="83" height="52"><img class="l-seed" src="img/logo/seed.png" alt="" width="83" height="52"><img class="l-word" src="img/logo/word.png" alt="" width="83" height="52"></span></a>
<nav class="tabs" aria-label="Secciones"><ul>{items}<li><a href="{REPO}">GitHub</a></li></ul></nav>
{i18n.switcher("es", tab if path is None else path)}
</div></header>"""


def page_head(kicker: str, title: str, lede: str) -> str:
    """A tab's own title, short: what is in it."""
    return f"""<section class="page-head"><div class="wrap">
<p class="kicker pixel">{kicker}</p><h1 class="page-title">{title}</h1><p class="lede">{lede}</p>
</div></section>"""


def hero() -> str:
    return f"""<section class="hero" id="top" aria-labelledby="hero-title"><div class="wrap">
<div>
<p class="kicker pixel">Motor de juegos libre · ESP32-S3</p>
<h1 id="hero-title">Un motor, doce épocas</h1>
<p class="lede"><img class="wordmark" src="img/wordmark.png" alt="pinyol" width="65" height="26"> hace juegos con el aspecto de las consolas de los 80 y los 90 y los mueve a 60 fps en una consola de bolsillo con un ESP32‑S3. Dile a tu agente de código qué aspecto quieres y te hace el juego. Aquí puedes jugar a todos.</p>
<div class="actions"><a class="btn btn-primary" href="{HOME}juega/">Jugar ahora</a><a class="btn btn-ghost" href="{HOME}crear/">Crear un juego</a><a class="btn btn-ghost" href="{REPO}">Ver el código</a></div>
<p class="meta">Código MIT · arte y sonido CC0 · {len(LOOKS) + len(OTHERS) + len(CODEX)} juegos de ejemplo</p>
</div>
<div><div class="board" data-live role="img" aria-label="La consola (una placa Freenove FNK0104N) arrancando: la intro de pinyol, el menú de Cirera con sus juegos y algunos de ellos en marcha">
<span class="hole tl"></span><span class="hole bl"></span><span class="hole tr"></span><span class="hole br"></span>
<span class="mic" aria-hidden="true">MIC</span><span class="mic-hole"></span><span class="keys" aria-hidden="true"><i></i><i></i></span>
<div class="glass"><div class="screen"><video class="boot" src="video/consola.mp4" poster="video/consola.jpg" width="720" height="480" autoplay muted loop playsinline preload="auto"></video></div></div></div>
<p class="screen-label pixel">Freenove FNK0104N · 480×320 · 60 fps en la placa <button class="screen-toggle" type="button" aria-pressed="false">Pausar</button></p></div>
</div></section>"""


def cart(k: dict, n: int, shelf: bool = True) -> str:
    fps = charts.fps_range(k["fps"])
    low = " low" if k["fps"][0] < 56 else ""
    made = "arte generado con IA" if k["art"] else "dibujado con código"
    big = " big" if shelf and k["id"] in BIG else ""
    return f"""<li class="cart{big}" style="--hue:{k['hue']}">
<div class="shot"><img src="img/looks/{k['id']}.png" alt="{escape(k['alt'])}" width="480" height="320" loading="lazy" decoding="async"></div>
<div class="label"><p class="era pixel">{escape(k['era'])}</p><h3>{escape(k['name'])}</h3><p class="what">{escape(k['what'])}</p>
<ul class="chips"><li class="chip fps{low}">{fps} fps en la consola</li><li class="chip">{made}</li></ul>
<div class="row"><a class="play" href="{play_url(k['example'])}" data-goatcounter-click="jugar/{k['example']}" aria-label="Jugar a {escape(k['example'])} ({escape(k['name'])})">Jugar</a>
<a class="zip" href="games/{k['example']}.zip" download data-goatcounter-click="descargar/{k['example']}" aria-label="Descargar {escape(k['example'])} para la consola">Descargar .zip</a>
<a class="sheet-link" href="{HOME}juegos/{k['example']}/" aria-label="Ficha de {escape(k['example'])} ({escape(k['name'])})">Ficha</a></div></div></li>"""


def measured(board: dict) -> list[dict]:
    """The looks with their ranges from the board's own logs where it logged their example second by second (the same
    numbers the charts draw, a trace's first second left out); the others keep docs/measurements.md's."""
    logs = {t["id"]: (t["after"]["fps"][charts.LOAD_S:], t["before"]["fps"][charts.LOAD_S:]) for t in board["traces"]}
    logs.update({s["id"]: (s["fps"], None) for s in board["steady"]})
    rng = lambda v: (round(min(v)), round(max(v)))
    out = []
    for k in LOOKS:
        now, was = logs.get(k["example"], (None, None))
        out.append({**k, **({"fps": rng(now)} if now else {}), **({"was": rng(was)} if was else {})})
    return out


def looks(shelf: list[dict]) -> str:
    carts = "".join(cart(k, n) for n, k in enumerate(shelf))
    others = "".join(f'<li><a href="{HOME}juegos/{g}/">{escape(t)}</a></li>' for g, t in OTHERS)
    return f"""<section id="aspectos" aria-labelledby="aspectos-t"><div class="wrap">
<h2 id="aspectos-t">Doce aspectos, un motor</h2>
<p class="intro">Cada cartucho es un ejemplo jugable con las reglas de su consola: su resolución, sus colores, sus capas. Se juega con el teclado (flechas, Z y X) o, en el móvil, con los botones en pantalla. Las cifras de fps se midieron jugando en la consola real.</p>
<ul class="shelf">{carts}</ul>
<div class="more"><h3>Y {len(OTHERS)} ejemplos más</h3><ul>{others}</ul></div>
</div></section>"""


def performance(board: dict, tests: int, shelf: list[dict]) -> str:
    return f"""<section id="rendimiento" class="perf" aria-labelledby="perf-t"><div class="wrap">
<p class="kicker pixel">ESP32-S3R8 · 240 MHz · PSRAM octal a 80 MHz · pantalla QSPI a 80 MHz</p>
<h2 id="perf-t">Medido en la consola, no prometido</h2>
<p class="intro">Cada cifra de esta sección sale de la placa: o un firmware que juega solo siguiendo un guion y anota el rendimiento cada segundo, o un banco de pruebas que repite cada escena cinco veces. Nada de emuladores. A 60 fps, cada fotograma dispone de 16,6 ms.</p>
{charts.stats_band(board, tests)}
{charts.looks_chart(shelf)}
{charts.traces_chart(board)}
{charts.strips_demo('img/looks/neogeo.png', 'img/looks/32bits.png', 'Animación: la pantalla dividida en 15 franjas; cada una se llena desde arriba, mitad por el núcleo 0 y mitad por el núcleo 1, y luego aparece en el panel mientras se dibuja la siguiente')}
{charts.profile_chart(board)}
{charts.cost_chart()}
<p class="source">Fuente: <a href="{REPO}/blob/main/docs/measurements.md">docs/measurements.md</a>, con el método y cada medición desde el primer día. Mídelo en tu placa:
<code>idf.py -DBP_BENCH=ON build flash monitor</code></p>
</div></section>"""


def code(text: str, wide: bool = False) -> str:
    """A command to copy. wide: lines that must not wrap (a shell command split with \\) scroll sideways instead."""
    first = text.splitlines()[0]
    pre = '<div class="code wide"><pre tabindex="0">' if wide else '<div class="code"><pre>'
    return (f'{pre}<code>{escape(text)}</code></pre>'
            f'<button class="copy" type="button" aria-label="Copiar: {escape(first)}">Copiar</button></div>')


def make_one() -> str:
    return f"""<section id="hazlo" aria-labelledby="hazlo-t"><div class="wrap">
<h2 id="hazlo-t">Hazte un juego</h2>
<p class="intro">pinyol está pensado para usarse con un agente de código, como Codex o Claude Code. El agente lee las instrucciones del repositorio, instala lo que falta, sigue la receta del aspecto que pidas y prueba el juego antes de dártelo.</p>
<ol class="steps">
<li><h3>Baja el motor</h3><p>En un Mac con Homebrew o en Linux.</p>{code(f"git clone {REPO}.git" + chr(10) + "cd pinyol")}</li>
<li><h3>Pídeselo a tu agente</h3><p>Abre la carpeta con tu agente y dile qué quieres, en tu idioma.</p>{code("Hazme un plataformas con aspecto de Game Boy: un ratón que busca queso en una biblioteca.")}</li>
<li><h3>Juégalo</h3><p>En el ordenador, o pásalo a la consola por USB.</p>{code("./build/pinyol_sim --game games/raton")}</li>
</ol>
<div class="aside-note"><b>¿Sin programar?</b> <a href="#crear">El editor web</a> hace lo mismo con dibujos y bloques, en el navegador.</div>
</div></section>"""


def engine() -> str:
    """What the engine brings, for whoever is about to make a game (the Crear tab): the facts of docs/lua.md."""
    parts = [("Imagen", "Una consola virtual como la Game Boy Advance: 240×160 con cuatro capas, 128 sprites, paletas, transparencias y efectos por línea, y encima textos y paneles a 480×320."),
             ("Mundos", "Mode 7, primera persona a lo Wolfenstein 3D, enjambres de cientos de balas, cuadrículas y niveles dibujados en Tiled."),
             ("Sonido", "Efectos hechos con recetas o con números, cuatro voces de sintetizador como las de la Game Boy Advance, música en capas que entran y salen, y módulos .mod de hasta 32 canales."),
             ("El studio", "Un secuenciador de pasos dentro del audio: pistas de sonidos y un bajo ácido como el de una TB-303, con eco, reverb y Lo-fi GBA. Cada paso suena en su muestra exacta, y un patrón nuevo entra justo en el siguiente compás."),
             ("La consola", "Pantalla táctil, micrófono, el LED y la batería, vídeo desde la tarjeta y partidas entre consolas cercanas, sin router."),
             ("Para programar", "Lua, con librerías dentro: física, partículas, historias, teclado y el kit de aventuras. Las partidas se guardan sin congelar el juego, y un guion prueba cada juego solo.")]
    items = "".join(f'<li class="engine-card{" new" if name == "El studio" else ""}"><h3>{escape(name)}</h3>'
                    + ('<span class="chip">Nuevo</span>' if name == "El studio" else "") + f"<p>{escape(text)}</p></li>" for name, text in parts)
    return f"""<section id="motor" aria-labelledby="motor-t"><div class="wrap">
<h2 id="motor-t">Lo que trae el motor</h2>
<p class="intro">Todo esto funciona igual en la consola, en el ordenador y en el navegador, y tu agente lo conoce porque está en las instrucciones del repositorio.</p>
<ul class="engine-grid">{items}</ul>
<p class="more-link"><a class="btn btn-ghost" href="{REPO}/blob/main/docs/lua.md">La API de Lua, con ejemplos</a></p>
</div></section>"""


def editor() -> str:
    """The editor, with the video of LÍNEA 0 being made in it (site/src/video, recorded with Playwright)."""
    features = [("Aspecto de consola", "Game Boy, Game Boy Advance, PICO-8, ZX Spectrum o 16 bits: sus colores y su tipo de letra"),
                ("Dibujos que se mueven", "píxel a píxel, de frente, de lado y de espaldas, con animaciones para andar, recibir un golpe o hacer hasta seis acciones"),
                ("Reglas con bloques", "vidas, cuenta atrás, diálogos, girarse hacia alguien, récords que se guardan y persianas entre niveles"),
                ("Sonido", "efectos a partir de recetas, música compuesta en una cuadrícula o un .mod"),
                ("A la consola", "por cable USB o en un .zip para la tarjeta"),
                ("En tres idiomas", "castellano, català y English")]
    items = "".join(f"<li><b>{escape(a)}</b> <span>{escape(b)}</span></li>" for a, b in features)
    return f"""<section id="crear" class="editor-sec" aria-labelledby="crear-t"><div class="wrap editor-grid">
<div class="editor-copy">
<p class="era pixel">Sin programar · en el navegador</p>
<h2 id="crear-t">El editor</h2>
<p class="intro">Dibuja los personajes píxel a píxel, pinta los mapas, pon las reglas con bloques y prueba el juego al momento. Empieza desde cero o desde una plantilla, como Abella o LÍNEA 0.</p>
<ul class="features">{items}</ul>
<div class="actions"><a class="btn btn-primary btn-big" href="editor/">Abrir el editor</a><a class="btn btn-ghost" href="{HOME}biblioteca/">Juegos hechos con él</a></div>
</div>
<figure class="editor-video">
<video src="video/linea0.mp4" poster="video/linea0.jpg" width="1280" height="800" controls muted loop playsinline autoplay preload="metadata" aria-describedby="linea0-cap"></video>
<figcaption id="linea0-cap">LÍNEA 0, un juego de Game Boy Advance hecho entero con el editor y grabado de principio a fin: dibujos, mapas, reglas y a jugar. La creación va ocho veces más rápida; la partida, a velocidad real.</figcaption>
</figure>
</div></section>"""


def featured() -> str:
    """The cover of the week: games.js shows the game tools/stats.py chose (the most voted of the week, or the most talked
    about, or one at random), or one at random until it has chosen; hidden until it knows which."""
    return """<section id="portada" class="featured" aria-labelledby="portada-t" hidden><div class="wrap feat">
<a class="feat-shot" id="feat-shot" tabindex="-1" aria-hidden="true"><img id="feat-img" alt="" width="480" height="320"></a>
<div class="feat-info"><p class="kicker pixel" id="portada-t">Portada de la semana</p>
<h2 class="feat-title" id="feat-title"></h2><p class="feat-why" id="feat-why"></p>
<div class="actions"><a class="btn btn-primary" id="feat-play">Jugar</a><a class="btn btn-ghost" id="feat-page">Ver la ficha</a></div></div>
</div></section>"""


def ranking(catalog: str, top: int = 10) -> str:
    """The most voted games (games.js, from stats.json), with each one's numbers; the games it may list, as JSON. The
    home page shows the first five, with the way to the rest."""
    title, more = ("Ranking", "") if top == 10 else \
        ("Lo más votado", f'<p class="more-link"><a class="btn btn-ghost" href="{HOME}biblioteca/#ranking">Ver el ranking completo</a></p>')
    return f"""<section id="ranking" aria-labelledby="ranking-t"><div class="wrap">
<h2 id="ranking-t">{title}</h2>
<p class="intro">Los juegos más votados. Se vota con una reacción en la ficha de cada juego; las cifras se actualizan una vez al día.</p>
<div class="rank" id="rank" data-src="{STATS}" data-top="{top}"><p class="lib-state">El ranking necesita JavaScript para cargarse.</p></div>
{more}
<script type="application/json" id="catalog">{catalog}</script>
</div></section>"""


def library(pages: str = "") -> str:
    """People's games (tools/library.py publishes them in library/): site.js reads the list when the page opens. On its
    own tab, whose title says what it is."""
    return f"""<section id="biblioteca" class="library-sec" aria-labelledby="biblioteca-t"><div class="wrap">
<h2 id="biblioteca-t" class="sr">Los juegos</h2>
<div class="actions"><a class="btn btn-primary" href="{REPO}/issues/new?template=biblioteca.yml">Sube tu juego</a><a class="btn btn-ghost" href="{HOME}crear/#subir">Cómo se sube</a></div>
<div class="library" id="library" data-src="{RAW}/library/library.json" data-base="{RAW}/library/" data-repo="{REPO}" data-play="{HOME}juega/" data-pages="{pages}">
<p class="lib-state">La Biblioteca necesita JavaScript para cargarse. Sus juegos también están en <a href="{REPO}/tree/main/library">GitHub</a>.</p></div>
</div></section>"""


def share() -> str:
    """How a game goes to the Library (the create tab): the form, the video, and how to ask for something to go."""
    return f"""<section id="subir" aria-labelledby="subir-t"><div class="wrap">
<h2 id="subir-t">Súbelo a la Biblioteca</h2>
<p class="intro">Cuando tu juego esté listo, súbelo con el formulario: un robot lo abre y lo juega diez segundos, y cuando lo hayamos revisado se podrá jugar en la web y descargar para la consola.</p>
<div class="actions"><a class="btn btn-primary" href="{REPO}/issues/new?template=biblioteca.yml">Sube tu juego</a><a class="btn btn-ghost" href="{HOME}biblioteca/">La Biblioteca</a></div>
<figure class="tutorial"><video src="video/subir.mp4" poster="video/subir.jpg" width="960" height="600" controls preload="none" playsinline aria-describedby="subir-cap"></video>
<figcaption id="subir-cap">Tutorial, de tu juego a la Biblioteca: descarga el .zip desde el editor, rellena el formulario y adjúntalo. Un robot lo comprueba y, cuando está aprobado, ya se puede jugar aquí. Las esperas van aceleradas.</figcaption></figure>
<p class="sub">¿Algo tuyo publicado aquí sin tu permiso, o algo que no debería estar? <a href="{REPO}/issues/new?title=Retirar%3A%20">Pide que lo retiremos</a>.</p>
</div></section>"""


def highlights(shelf: list[dict]) -> str:
    """Six of the looks to start with, on the home page; the rest on the games tab."""
    six = [k for k in shelf if k["id"] in HIGHLIGHTS]
    return f"""<section id="destacados" aria-labelledby="destacados-t"><div class="wrap">
<h2 id="destacados-t">Seis para empezar</h2>
<p class="intro">Seis de los doce aspectos, para jugar ahora mismo en el navegador. Las cifras de fps se midieron jugando en la consola real.</p>
<ul class="jobs">{"".join(cart(k, n, shelf=False) for n, k in enumerate(six))}</ul>
<p class="more-link"><a class="btn btn-ghost" href="{HOME}crear/#aspectos">Ver los doce aspectos</a></p>
</div></section>"""


def doors() -> str:
    """The home page's three ways in: to play, to make, the console."""
    items = [("juega/", "img/looks/neogeo.png", "Juega", "El reproductor con todos los juegos: elige uno o abre el tuyo."),
             ("biblioteca/", "img/covers/ilustres.png", "Biblioteca", "Los juegos que hace la gente con pinyol, y el ranking de los más votados."),
             ("crear/", "video/linea0.jpg", "Crea", "Doce aspectos de consola para empezar, tu agente de código o el editor, sin programar."),
             ("consola/", "img/console/cirera_frente.webp", "La consola", "La Cirera, su firmware y otras formas de jugar, como RetroArch.")]
    li = "".join(f"""<li class="door"><img src="{img}" alt="" width="480" height="320" loading="lazy" decoding="async">
<div><h3><a class="stretch" href="{HOME}{t}">{escape(name)}</a> <span class="arrow" aria-hidden="true">→</span></h3><p>{escape(text)}</p></div></li>""" for t, img, name, text in items)
    return f"""<section class="doors-sec" aria-labelledby="doors-t"><div class="wrap"><h2 id="doors-t" class="sr">Las secciones</h2><ul class="doors">{li}</ul></div></section>"""


def codex() -> str:
    jobs = "".join(f"""<li class="cart job">
<div class="shot"><img src="img/codex/{j['id']}.png" alt="{escape(j['alt'])}" width="480" height="320" loading="lazy" decoding="async"></div>
<div class="label"><p class="era pixel">Nivel {j['level']} · {escape(j['look'])}</p><h3>{escape(j['title'])}</h3>
<blockquote><p>{escape(j['prompt'])}</p></blockquote>
<ul class="chips"><li class="chip fps">{j['time']}</li><li class="chip">{j['commands']} comandos</li><li class="chip">{j['tokens']} tokens</li><li class="chip fps{' low' if j['fps'] not in ('59', '60', '61') else ''}">{j['fps']} fps en la consola</li></ul>
<p class="after">{escape(j['after'])}</p>
<div class="row"><a class="play" href="{play_url(j['id'])}" aria-label="Jugar a {escape(j['title'])}">Jugar</a>
<a class="zip" href="games/{j['id']}.zip" download aria-label="Descargar {escape(j['title'])} para la consola">Descargar .zip</a>
<a class="sheet-link" href="{HOME}juegos/{j['id']}/" aria-label="Ficha de {escape(j['title'])}">Ficha</a></div></div></li>""" for j in CODEX)
    return f"""<section id="codex" aria-labelledby="codex-t"><div class="wrap">
<h2 id="codex-t">La escalera: cinco encargos</h2>
<p class="intro">De lo más sencillo a lo más difícil. Cada encargo partió de un clon limpio del repositorio, con un solo mensaje y sin responder a ninguna pregunta. Codex leyó AGENTS.md, compiló el motor, siguió la receta del aspecto y escribió un guion que juega solo al juego, y no paró hasta que pasó la prueba. Luego cada juego se midió en la consola con ese mismo guion. Con {escape(CODEX_RUN)}.</p>
{charts.bars([(f"{j['level']} · {j['title']}", j['minutes'], f"{j['time']} · {j['fps']} fps") for j in CODEX], 20, None, "")}
<ul class="jobs">{jobs}</ul>
</div></section>"""


def install(fw: dict | None) -> str:
    """The console's firmware installed from the browser (ESP Web Tools, Web Serial), when the site was built with it."""
    if not fw:
        return ""
    return f"""<div class="install" id="instalar"><h3>Instala el firmware desde el navegador</h3>
<ol><li>Conecta la placa al ordenador por USB.</li><li>Pulsa el botón y elige el puerto de la placa.</li>
<li>Espera unos minutos: arranca con {fw['games']} juegos en la memoria.</li></ol>
<esp-web-install-button manifest="firmware/manifest.json">
<button slot="activate" class="btn btn-primary" type="button" data-goatcounter-click="instalar-consola">Instalar en la consola</button>
<span slot="unsupported" class="note">Este navegador no puede comunicarse con la placa por USB: abre esta página en Chrome o Edge, en un ordenador.</span>
<span slot="not-allowed" class="note">Para instalar, abre la página por https.</span>
</esp-web-install-button>
<p class="note">Firmware {escape(fw['version'])} · {fw['mb']} MB · <a href="{REPO}/releases/tag/{fw['tag']}">los archivos para esptool</a></p></div>"""


def console(fw: dict | None) -> str:
    spec = [("Placa", "Freenove FNK0104N"), ("Chip", "ESP32-S3R8, dos núcleos a 240 MHz"), ("Memoria", "512 KB de RAM interna, 8 MB de PSRAM, 16 MB de flash"),
            ("Pantalla", "3,5″, 480×320, ST77922 por QSPI, táctil"), ("Sonido", "ES8311 con altavoz"), ("Lo demás", "microSD, batería, USB")]
    dl = "".join(f"<dt>{escape(a)}</dt><dd>{escape(b)}</dd>" for a, b in spec)
    return f"""<section id="consola" aria-labelledby="consola-t"><div class="wrap">
<h2 id="consola-t">La Cirera</h2>
<p class="intro">Una placa de desarrollo con pantalla, que se compra ya montada. El motor la exprime: dibuja directamente por franjas, reparte el trabajo entre los dos núcleos y guarda en la tarjeta lo que no cabe en memoria.</p>
<figure class="renders"><img src="img/console/cirera_frente.webp" alt="La consola Cirera de frente: carcasa marfil, cruceta verde, botones A, B y C de color terracota, MENU y START grises y una pelea de Neo Geo en la pantalla" width="1200" height="800" loading="lazy" decoding="async"><img src="img/console/cirera_detras.webp" alt="La parte de atrás: una placa oscura con CIRERA y una cereza de píxeles, el modelo S3-01, la batería de 3,7 V y 3000 mAh y USB-C a 5 V" width="1200" height="800" loading="lazy" decoding="async"><figcaption>La carcasa Cirera v1.0, en render: imágenes generadas con IA a partir de su modelo 3D. Todavía no se ha impreso.</figcaption></figure>
<figure class="tutorial"><video src="video/montaje.mp4" poster="video/montaje.jpg" width="960" height="540" controls muted preload="none" playsinline aria-describedby="montaje-cap"></video><figcaption id="montaje-cap">El montaje de la v1.0, animado a partir de su modelo 3D: la carcasa, la placa, las dos placas de cobre de los botones, los cables, la batería y el altavoz.</figcaption></figure>
<div class="hw"><dl class="spec">{dl}</dl>
<div class="side">{install(fw)}<div class="pending"><h3>La carcasa v1.0, diseñada</h3><p>Falta imprimirla y probarla. Entonces se publicarán sus archivos para imprimir (CC BY 4.0), la lista de piezas y el montaje. Mientras tanto, ya se juega con la placa sola.</p>
<p><a href="{REPO}/blob/main/docs/hardware.md">Cómo conectarla</a> · <a href="https://github.com/Freenove/Freenove_ESP32_S3_Display">La placa de Freenove</a></p></div></div></div>
</div></section>"""


def retroarch() -> str:
    """The engine as a libretro core (docs/libretro.md): RetroArch, and RetroPie on a Raspberry Pi."""
    setup = ("cd ~/RetroPie-Setup\ncurl -fsSL --create-dirs \\\n  -o ext/pinyol/scriptmodules/libretrocores/lr-pinyol.sh \\\n"
             f"  {RAW}/platform/libretro/lr-pinyol.sh\nsudo ./retropie_packages.sh lr-pinyol")
    return f"""<section id="retroarch" aria-labelledby="retroarch-t"><div class="wrap">
<h2 id="retroarch-t">En RetroArch y RetroPie</h2>
<p class="intro">¿Sin la consola? El motor también es un núcleo de libretro: los juegos de pinyol se juegan en RetroArch y en todo lo que se basa en él, como RetroPie o Lakka en una Raspberry Pi, Batocera, Recalbox, las portátiles que lo llevan o un ordenador. Es el mismo motor, así que el juego es el mismo.</p>
<ol class="steps">
<li><h3>Instálalo en RetroPie</h3><p>En la Raspberry Pi, este comando descarga el núcleo ya compilado (una Pi 1 o Zero lo compila, en unos minutos) y añade Pinyol a EmulationStation.</p>{code(setup, wide=True)}</li>
<li><h3>Copia los juegos</h3><p>El .zip de cualquier juego, como los que se descargan aquí, va a su carpeta.</p>{code("~/RetroPie/roms/pinyol/")}</li>
<li><h3>Juega</h3><p>Reinicia EmulationStation y aparece Pinyol con sus juegos. En el mando, X o Y hacen de C, y SELECT de MENU.</p></li>
</ol>
<div class="aside-note"><b>¿Otro RetroArch?</b> En un ordenador con Linux, Batocera o Lakka, <a href="{REPO}/releases/tag/libretro">el núcleo ya compilado</a> va a la carpeta de núcleos de RetroArch; <a href="{REPO}/blob/main/docs/libretro.md">la guía</a> lo explica. Probado en RetroArch y con el sistema de RetroPie emulado, aún no en una Raspberry Pi de verdad: si lo pruebas, <a href="{REPO}/issues">cuéntanos cómo va</a>.</div>
</div></section>"""


def making(stats: dict) -> str:
    items = [(stats["c_lines"], "líneas de C en el motor"), (stats["examples"], "juegos de ejemplo"), (stats["tests"], "pruebas en cada cambio"),
             (stats["commits"], "commits en el repositorio")]
    li = "".join(f'<li><b data-count="{v}" data-dec="0">{thousands(v)}</b><span>{escape(t)}</span></li>' for v, t in items)
    return f"""<section id="making" aria-labelledby="making-t"><div class="wrap">
<h2 id="making-t" class="sr">En cifras</h2>
<ul class="stats reveal">{li}</ul>
<div class="story">
<p><strong>Una persona y Claude.</strong> El motor, los ejemplos, las herramientas y esta web se escribieron hablando con Claude Code: cada idea se probaba en el simulador, se medía en la placa y se corregía según lo que mostraban las mediciones.</p>
<p><strong>El arte, generado y ajustado.</strong> Los aspectos que lo necesitan (Neo Geo, CPS2, 32 bits) usan imágenes generadas con IA. Las herramientas del motor las recortan, las escalan a la altura justa, separan los fotogramas y las reducen a la paleta de la consola. Los aspectos de baja resolución se dibujan con código.</p>
<p><strong>Medido antes de darlo por bueno.</strong> Cada ejemplo tiene un guion que lo juega solo. En el ordenador, el guion compara la suma de control de cada fotograma con la guardada; en la placa, anota los fps de cada segundo. Así se comprueba que las optimizaciones no cambian ni un píxel.</p>
<p><strong>Libre de verdad.</strong> El código tiene licencia MIT; el arte, el sonido y los vídeos de los ejemplos, CC0. Cógelo, cámbialo y haz tu propia consola.</p>
</div>
{art_pipeline()}
{days()}
<p class="source">Todo el proceso está en el repositorio: <a href="{REPO}/blob/main/docs/art.md">cómo se hace el arte</a>, <a href="{REPO}/blob/main/docs/lua.md">la API de Lua</a>, <a href="{REPO}/blob/main/AGENTS.md">las instrucciones para agentes</a>.</p>
</div></section>"""


def art_pipeline() -> str:
    """One enemy from the request to the game: mazmorra's goblin, with the real pictures (web-retrogo/assets/cps2/raw,
    examples/mazmorra/art; site/src/img/making)."""
    steps = [
        ("1 · El encargo", '<blockquote><p>Un goblin original para un beat \'em up de fantasía: pequeño, enjuto y encorvado, '
         'piel verde, orejas enormes, un taparrabos raído y un puñal curvo oxidado. De cuerpo entero, mirando a la '
         'izquierda. Estilo: sprite de recreativa de mediados de los noventa, píxeles nítidos, contorno oscuro, unos 15 '
         'colores. Fondo transparente.</p></blockquote>', "Resumido y traducido del encargo, que se escribió en inglés."),
        ("2 · La referencia", '<img src="img/making/goblin_ref.webp" alt="El goblin solo, de cuerpo entero: verde, con '
         'orejas puntiagudas y un puñal curvo" width="360" height="356" loading="lazy" decoding="async">',
         "El personaje solo. Se adjunta a cada encargo siguiente para que no cambie de un dibujo a otro."),
        ("3 · La hoja de poses", '<img src="img/making/goblin_sheet.jpg" alt="Diez poses del goblin en dos filas, sobre un fondo '
         'oscuro difuminado" width="720" height="480" loading="lazy" decoding="async">',
         "Diez poses: andar, apuñalar, encajar un golpe y caer. El fondo se pidió transparente y salió pintado."),
        ("4 · El recorte", '<img class="px" src="img/making/goblin_frames.png" alt="Los diez fotogramas recortados, a la '
         'misma escala y con los pies en la misma línea" width="535" height="200" loading="lazy" decoding="async">',
         "Las herramientas del motor quitan el fondo, separan los fotogramas, los dejan a la misma escala con los pies "
         "alineados y los reducen a 15 colores. Luego se revisa cada uno a ojo."),
        ("5 · En el juego", '<img class="px" src="img/making/mazmorra.png" alt="Alba, la espadachina, frente a dos '
         'goblins en el pasillo de la mazmorra" width="480" height="320" loading="lazy" decoding="async">',
         "En mazmorra salen en grupo, a 60 fps en la consola."),
    ]
    li = "".join(f"<li><h4>{t}</h4>{body}<p>{escape(note)}</p></li>" for t, body, note in steps)
    return f"""<figure class="pipeline reveal" aria-labelledby="pipe-t">
<figcaption><h3 id="pipe-t">Un enemigo, del encargo al juego</h3>
<p>El goblin del juego mazmorra, paso a paso, con las imágenes reales.</p></figcaption>
<ol class="pipe">{li}</ol>
</figure>"""


def days() -> str:
    """The repository's days, from its git log."""
    items = [
        ("2026-10-11", "11 oct.", "El motor nace de dos juegos de aventuras y se mide en la placa: la imagen va directa al panel, por franjas."),
        ("2026-10-12", "12 oct.", "Un procesador de imagen virtual, como el de la Game Boy Advance, y juegos en Lua de cualquier género."),
        ("2026-10-13", "13 oct.", "Medición y optimización en la consola. El editor web, para hacer juegos sin programar."),
        ("2026-10-14", "14 oct.", "Los aspectos de doce consolas, la vista en primera persona, las instrucciones para que un agente haga juegos, la web y la Biblioteca."),
        ("2026-10-15", "15 oct.", "La web y el editor en tres idiomas, los juegos de Codex e IL·LUSTRES en la Biblioteca."),
        ("2026-10-16", "16 oct.", "El studio de sonido, un secuenciador con sintetizador y efectos. La web, en pestañas, con la pestaña Juega y una página y un ranking para cada juego."),
    ]
    li = "".join(f'<li><time datetime="{d}">{label}</time><p>{escape(t)}</p></li>' for d, label, t in items)
    return f"""<div class="days reveal"><h3>Seis días en el repositorio</h3><ol>{li}</ol></div>"""


def thousands(v: int) -> str:
    """As Spanish writes them: 15.095, but 1234."""
    return f"{v:,}".replace(",", ".") if v >= 10000 else str(v)


def footer() -> str:
    return f"""<footer><div class="wrap"><img src="img/logo.png" alt="pinyol" width="64" height="42" loading="lazy">
<span>Código MIT · arte y sonido CC0</span><span>Game Boy, PICO-8, Neo Geo y las demás consolas que se nombran son marcas de sus dueños; pinyol y Cirera no tienen relación con ellos.</span><a href="{REPO}">GitHub</a><a href="{REPO}/blob/main/docs/measurements.md">Mediciones</a><span>Las visitas, las partidas y el tiempo jugado se cuentan con <a href="https://www.goatcounter.com">GoatCounter</a>, sin cookies ni datos personales.</span><span>Los comentarios y los votos de cada juego se guardan en GitHub y se cargan con giscus solo si los pides.</span><span>La Biblioteca, el ranking y las cifras de cada juego se leen de GitHub al abrir la página.</span></div></footer>"""


NEW_TAB = " (se abre en una pestaña nueva)"


def new_tabs(html: str) -> str:
    """Links that leave the page (other sites, the player, the editor) open in a new tab, so the page stays open; the
    tab is said to screen readers too."""
    def one(m: re.Match) -> str:
        attrs, inner = m[1], m[2]
        href = re.search(r'href="([^"]*)"', attrs)
        if not href or " download" in attrs or not href[1].startswith(("http", "play/", "editor/")):
            return m[0]
        if "aria-label=" in attrs:
            attrs = re.sub(r'aria-label="([^"]*)"', lambda a: f'aria-label="{a[1]}{NEW_TAB}"', attrs)
        else:
            inner += f'<span class="sr">{NEW_TAB}</span>'
        return f'<a{attrs} target="_blank" rel="noopener">{inner}</a>'
    return re.sub(r"<a(\s[^>]*)>(.*?)</a>", one, html, flags=re.S)


CSP = (f"default-src 'self'; img-src 'self' data: https://raw.githubusercontent.com {COUNTER}; style-src 'self' 'unsafe-inline'; "
       f"script-src 'self'; font-src 'self'; connect-src 'self' https://raw.githubusercontent.com {COUNTER}; object-src 'none'; "
       f"base-uri 'self'; form-action 'none'")


def layout(path: str, title: str, desc: str, body: str, fw: dict | None = None, extra: str = "") -> str:
    """A tab's page: its head (title, description, the three languages), the tabs, its sections, the footer."""
    return new_tabs(f"""<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="{CSP}">
<title>{title}</title>
<meta name="description" content="{escape(desc)}">
<meta property="og:title" content="{title}">
<meta property="og:description" content="{escape(desc)}">
<meta property="og:type" content="website">
<meta property="og:image" content="{SITE}img/og.png">
<meta name="theme-color" content="#0b0e1f">
<link rel="canonical" href="{SITE}{path}">
{i18n.alternates(SITE, path)}
<link rel="icon" href="img/icon.png">
<link rel="preload" href="fonts/jersey15.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="styles.css">
<script src="site.js" defer></script>
<script src="games.js" defer></script>{extra}
<script data-goatcounter="{COUNTER}/count" async src="vendor/goatcounter/count.js"></script>{'<script type="module" src="vendor/esp-web-tools/install-button.js"></script>' if fw else ""}
</head>
<body>
{header(path)}
<main id="main">
{body}
</main>
{footer()}
</body>
</html>
""")


def play(catalog: str, picker: str) -> str:
    """The Juega tab: the player (play/player.html in a frame, juega.js), a game chosen from the list or a .zip of one's
    own, opened or dropped on the page."""
    return f"""<section class="play-sec" aria-labelledby="juega-t"><div class="wrap play-head">
<div><h1 id="juega-t" class="page-title">Juega</h1>
<p class="lede">Elige un juego de la lista o abre el tuyo: un .zip hecho con pinyol, desde el botón o arrastrándolo a la página.</p></div>
<label class="btn btn-ghost pick-zip">Abrir tu juego (.zip)<input type="file" id="zip-file" accept=".zip,application/zip"></label>
</div>
<div class="stage"><iframe id="player" data-player="play/player.html" title="El reproductor de pinyol" allow="fullscreen; gamepad; microphone; autoplay"></iframe></div>
</section>
<section class="picker-sec" aria-labelledby="elige-t"><div class="wrap">
<h2 id="elige-t">Elige un juego</h2>
{picker}
<script type="application/json" id="catalog">{catalog}</script>
</div></section>"""


def site(board: dict, stats: dict, fw: dict | None, catalog: str = "[]", pages: str = "", picker: str = "") -> dict[str, str]:
    """The five tabs, {path: page in Spanish}."""
    shelf = measured(board)
    desc = "pinyol: un motor de juegos libre con doce aspectos retro (Game Boy, Neo Geo, CPS2, PlayStation…) que corre a 60 fps en una consola ESP32-S3 y en el navegador."
    return {
        "": layout("", "pinyol · un motor, doce épocas", desc,
                   f"{hero()}\n{featured()}\n{doors()}\n{highlights(shelf)}\n{ranking(catalog, 5)}"),
        "juega/": layout("juega/", "Juega · pinyol", "Juega a los juegos de pinyol en el navegador: elige uno de la lista, o abre el .zip de uno tuyo.",
                         play(catalog, picker), extra='<script src="juega.js" defer></script>'),
        "biblioteca/": layout("biblioteca/", "Biblioteca · pinyol", "La Biblioteca de pinyol: los juegos que hace la gente, para jugar en el navegador o descargar para la consola, y el ranking de los más votados.",
                              page_head("Juegos hechos por la gente", "Biblioteca", "Juegos hechos por la gente con pinyol: se juegan aquí y se descargan para la consola. Cada uno tiene su ficha, con sus cifras, sus comentarios y sus votos.")
                              + f"\n{library(pages)}\n{ranking(catalog)}"),
        "crear/": layout("crear/", "Crear · pinyol", "Hazte un juego con pinyol: con tu agente de código, a partir de doce aspectos de consola, o con el editor web, sin programar, y súbelo a la Biblioteca.",
                         page_head("Con tu agente o sin programar", "Crear", "Elige un aspecto de consola y pídeselo a tu agente de código, o dibújalo y ponle reglas en el editor. Cuando esté listo, súbelo a la Biblioteca.")
                         + f"\n{make_one()}\n{engine()}\n{looks(shelf)}\n{editor()}\n{codex()}\n{share()}"),
        "consola/": layout("consola/", "Consola · pinyol", "La consola Cirera, su firmware para instalar desde el navegador, y pinyol en RetroArch y RetroPie.",
                           page_head("ESP32-S3 · 480×320 · 60 fps", "Consola", "La Cirera, su firmware para instalar desde el navegador y otras formas de jugar a lo mismo, como RetroArch.")
                           + f"\n{console(fw)}\n{retroarch()}", fw),
        "como-se-hizo/": layout("como-se-hizo/", "Cómo se hizo · pinyol", "Cómo se hicieron pinyol y su web con Claude, y su rendimiento medido en la consola.",
                                page_head("Una persona y Claude", "Cómo se hizo", "El motor, los juegos y esta web, hechos hablando con Claude Code y medidos en la placa de verdad.")
                                + f"\n{making(stats)}\n{performance(board, stats['tests'], shelf)}"),
    }


def moved(to: str) -> str:
    """A page that is now elsewhere: it sends there at once."""
    return f"""<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="0; url={HOME}{to}">
<meta name="robots" content="noindex">
<title translate="no">pinyol</title>
</head>
<body><p><a href="{HOME}{to}">La Biblioteca</a></p></body>
</html>
"""


def publish(dist, html: str, path: str = "") -> None:
    """A page in the three languages: dist/<path>, dist/ca/<path>, dist/en/<path>, its links made right for each."""
    up = "../" * path.count("/")
    for lang in i18n.LANGS:
        out = html if lang == "es" else i18n.translate(html, lang, path)
        if up:
            out = i18n.relocate(out, up)
            out = re.sub(r'<nav class="langs".*?</nav>', lambda _: i18n.switcher(lang, path), out, count=1, flags=re.S)
        out = out.replace(HOME, up or "./")
        target = dist / i18n.page_path(lang) / path / "index.html"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(out, encoding="utf-8")
