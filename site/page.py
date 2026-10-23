"""pinyol's showcase page: the looks, the engine measured on the console, how to make a game, the console, the
making-of. build.py renders it into dist/index.html."""
from __future__ import annotations

import re
from html import escape

import charts
import i18n

REPO = "https://github.com/ipaud/pinyol"
RAW = "https://raw.githubusercontent.com/ipaud/pinyol/main"  # the Library's games, read when the page opens
SITE = "https://pinyol.ipaud.dev/"
STATS = "https://raw.githubusercontent.com/ipaud/pinyol/stats/stats.json"  # each game's numbers and the ranking: tools/stats.py, hourly
COUNTER = "https://pinyol.goatcounter.com"  # GoatCounter: visits and plays, no cookies, nothing personal (vendor/goatcounter)  # where it will be published (GitHub Pages); only og:image needs it

# The twelve looks: their example, the console it follows, its frame rate on the console as (slowest, fastest
# second), and the first measure when the board made it faster (docs/measurements.md, "The looks on the console").
LOOKS = [
    dict(id="gameboy", name="Game Boy", example="cerezo", era="1998 · cuatro verdes, un mundo de pantallas", art=False, fps=(58, 60), hue="#8bac0f",
         what="Una aventura al estilo Zelda: una isla, una cueva, un jefe y diálogos.", alt="Una plaza empedrada con un cerezo sin hojas y vecinos alrededor, en cuatro tonos de verde"),
    dict(id="spectrum", name="ZX Spectrum", example="cinta", era="1982 · dos colores por bloque", art=False, fps=(49, 61), hue="#ff3b3b",
         what="Incluye la carga de cinta, con sus franjas de colores.", alt="Una sala de ZX Spectrum: bloques de dos colores, un minero y un guardián"),
    dict(id="pico8", name="PICO-8", example="ladrillos", era="2015 · 128×128 · dieciséis colores", art=False, fps=(56, 60), was=(46, 55), hue="#ff77a8",
         what="Un rompeladrillos con la paleta de esta consola de fantasía.", alt="Un rompeladrillos de PICO-8 en dieciséis colores"),
    dict(id="lcd", name="Maquinita LCD", example="huevos", era="1980 · figuras que se encienden", art=False, fps=(61, 61), hue="#9aa58c",
         what="Un cocinero que recoge huevos y se mueve figura a figura.", alt="Una maquinita LCD: un cocinero que recoge huevos, con figuras que se encienden y se apagan"),
    dict(id="vector", name="Vectorial", example="pozo", era="1979 · solo líneas que brillan", art=False, fps=(59, 60), hue="#7cf7ff",
         what="Un tirador en un pozo hecho de líneas, con un menú que enseña cómo dibuja el haz.",
         alt="Un pozo en forma de estrella hecho de líneas brillantes sobre negro, con un cañón amarillo y enemigos rojos"),
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
    ("selva", "Selva"), ("niebla", "Niebla"), ("recortes", "Recortes"), ("cajas", "Cajas"),
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


def example_ids() -> list[str]:
    """Every example game the site plays: the looks', the other examples and Codex's ladder."""
    return [k["example"] for k in LOOKS] + [g for g, _ in OTHERS] + [j["id"] for j in CODEX]


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
<p class="meta">Código MIT · arte y sonido CC0 · {len(example_ids())} juegos de ejemplo</p>
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
    parts = [("Imagen", "Una consola virtual como la Game Boy Advance: 240×160 con cuatro capas, 128 sprites, paletas, transparencias y efectos por línea, y encima textos y paneles a 480×320. Además, caras 3D con textura al estilo PlayStation, luces, partículas y animación de recortes."),
             ("Mundos", "Mode 7, primera persona a lo Wolfenstein 3D, paisajes de vóxeles, cuadrículas con campo de visión y búsqueda de caminos, mazmorras generadas, enjambres de cientos de balas y niveles dibujados en Tiled o LDtk."),
             ("Sonido", "Efectos hechos con recetas o con números, cuatro voces de sintetizador como las de la Game Boy Advance, instrumentos, reverbs de PlayStation, música en capas que cambia en el compás y módulos .mod, .xm y .s3m."),
             ("El studio", "Un secuenciador de pasos dentro del audio: pistas de sonidos y un bajo ácido como el de una TB-303, con eco, reverb y Lo-fi GBA. Cada paso suena en su muestra exacta, y un patrón nuevo entra justo en el siguiente compás."),
             ("La consola", "Pantalla táctil con lápiz y varios dedos, micrófono, el LED y la batería, vídeo desde la tarjeta y partidas entre consolas cercanas, sin router. El menú se abre sobre cualquier juego, con ajustes, favoritos y logros."),
             ("Para programar", "Lua, con más de treinta librerías dentro: física, partículas, historias, cámara, escenas, inteligencia artificial, niveles generados, el movimiento de Celeste y el kit de aventuras. Las partidas se guardan sin congelar el juego, un guion prueba cada juego solo y un perfilador dice dónde se va el tiempo.")]
    items = "".join(f'<li class="engine-card"><h3>{escape(name)}</h3><p>{escape(text)}</p></li>' for name, text in parts)
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
<p class="intro">Los juegos más votados. Se vota con una reacción en la ficha de cada juego; las cifras se actualizan cada hora.</p>
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
<div class="library" id="library" data-src="{RAW}/library/library.json" data-base="{RAW}/library/" data-repo="{REPO}" data-play="{HOME}juega/" data-pages="{pages}" data-stats="{STATS}">
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
<p class="sub">¿Quieres subir una versión nueva de un juego que ya está en la Biblioteca? Envía el formulario otra vez, desde la misma cuenta de GitHub y con el mismo identificador (el id de tu game.json): al aprobarlo sustituye al anterior, y quien ya jugaba conserva sus partidas guardadas. La ficha del juego puede tardar un poco en mostrar los cambios.</p>
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
             ("consola/", "img/console/cirera_frente.webp", "La consola", "La Cirera, su firmware y la aplicación para jugar en tu ordenador, con Mac, Windows o Linux.")]
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
<h2 id="consola-t"><img class="rayas" src="img/cirera-rayas.svg" alt="" width="90" height="44">La Cirera</h2>
<p class="intro">Una placa de desarrollo con pantalla, que se compra ya montada. El motor la exprime: dibuja directamente por franjas, reparte el trabajo entre los dos núcleos y guarda en la tarjeta lo que no cabe en memoria.</p>
<figure class="renders"><img src="img/console/cirera_frente.webp" alt="La consola Cirera de frente: carcasa marfil, cruceta verde, botones A, B y C de color terracota, MENU y START grises y una pelea de Neo Geo en la pantalla" width="1200" height="800" loading="lazy" decoding="async"><img src="img/console/cirera_detras.webp" alt="La parte de atrás: una placa oscura con CIRERA y una cereza de píxeles, el modelo S3-01, la batería de 3,7 V y 3000 mAh y USB-C a 5 V" width="1200" height="800" loading="lazy" decoding="async"><figcaption>La carcasa Cirera v1.0, en render: imágenes generadas con IA a partir de su modelo 3D. Todavía no se ha impreso.</figcaption></figure>
<figure class="tutorial"><video src="video/montaje.mp4" poster="video/montaje.jpg" width="960" height="540" controls muted preload="none" playsinline aria-describedby="montaje-cap"></video><figcaption id="montaje-cap">El montaje de la v1.0, animado a partir de su modelo 3D: la carcasa, la placa, las dos placas de cobre de los botones, los cables, la batería y el altavoz.</figcaption></figure>
<div class="hw"><dl class="spec">{dl}</dl>
<div class="side">{install(fw)}<div class="pending"><h3>La carcasa v1.0, diseñada</h3><p>Falta imprimirla y probarla. Entonces se publicarán sus archivos para imprimir (CC BY 4.0), la lista de piezas y el montaje. Mientras tanto, ya se juega con la placa sola.</p>
<p><a href="{REPO}/blob/main/docs/hardware.md">Cómo conectarla</a> · <a href="https://github.com/Freenove/Freenove_ESP32_S3_Display">La placa de Freenove</a></p></div></div></div>
</div></section>"""


# The systems' marks on the download buttons: Apple's and Linux's (Tux) from Simple Icons (CC0), Windows' four panes
OS_ICONS = {"mac": "<path d=\"M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701\"/>",
            "windows": "<path d=\"M0 0h11.4v11.4H0zM12.6 0H24v11.4H12.6zM0 12.6h11.4V24H0zM12.6 12.6H24V24H12.6z\"/>",
            "linux": "<path d=\"M12.504 0c-.155 0-.315.008-.48.021-4.226.333-3.105 4.807-3.17 6.298-.076 1.092-.3 1.953-1.05 3.02-.885 1.051-2.127 2.75-2.716 4.521-.278.832-.41 1.684-.287 2.489a.424.424 0 00-.11.135c-.26.268-.45.6-.663.839-.199.199-.485.267-.797.4-.313.136-.658.269-.864.68-.09.189-.136.394-.132.602 0 .199.027.4.055.536.058.399.116.728.04.97-.249.68-.28 1.145-.106 1.484.174.334.535.47.94.601.81.2 1.91.135 2.774.6.926.466 1.866.67 2.616.47.526-.116.97-.464 1.208-.946.587-.003 1.23-.269 2.26-.334.699-.058 1.574.267 2.577.2.025.134.063.198.114.333l.003.003c.391.778 1.113 1.132 1.884 1.071.771-.06 1.592-.536 2.257-1.306.631-.765 1.683-1.084 2.378-1.503.348-.199.629-.469.649-.853.023-.4-.2-.811-.714-1.376v-.097l-.003-.003c-.17-.2-.25-.535-.338-.926-.085-.401-.182-.786-.492-1.046h-.003c-.059-.054-.123-.067-.188-.135a.357.357 0 00-.19-.064c.431-1.278.264-2.55-.173-3.694-.533-1.41-1.465-2.638-2.175-3.483-.796-1.005-1.576-1.957-1.56-3.368.026-2.152.236-6.133-3.544-6.139zm.529 3.405h.013c.213 0 .396.062.584.198.19.135.33.332.438.533.105.259.158.459.166.724 0-.02.006-.04.006-.06v.105a.086.086 0 01-.004-.021l-.004-.024a1.807 1.807 0 01-.15.706.953.953 0 01-.213.335.71.71 0 00-.088-.042c-.104-.045-.198-.064-.284-.133a1.312 1.312 0 00-.22-.066c.05-.06.146-.133.183-.198.053-.128.082-.264.088-.402v-.02a1.21 1.21 0 00-.061-.4c-.045-.134-.101-.2-.183-.333-.084-.066-.167-.132-.267-.132h-.016c-.093 0-.176.03-.262.132a.8.8 0 00-.205.334 1.18 1.18 0 00-.09.4v.019c.002.089.008.179.02.267-.193-.067-.438-.135-.607-.202a1.635 1.635 0 01-.018-.2v-.02a1.772 1.772 0 01.15-.768c.082-.22.232-.406.43-.533a.985.985 0 01.594-.2zm-2.962.059h.036c.142 0 .27.048.399.135.146.129.264.288.344.465.09.199.14.4.153.667v.004c.007.134.006.2-.002.266v.08c-.03.007-.056.018-.083.024-.152.055-.274.135-.393.2.012-.09.013-.18.003-.267v-.015c-.012-.133-.04-.2-.082-.333a.613.613 0 00-.166-.267.248.248 0 00-.183-.064h-.021c-.071.006-.13.04-.186.132a.552.552 0 00-.12.27.944.944 0 00-.023.33v.015c.012.135.037.2.08.334.046.134.098.2.166.268.01.009.02.018.034.024-.07.057-.117.07-.176.136a.304.304 0 01-.131.068 2.62 2.62 0 01-.275-.402 1.772 1.772 0 01-.155-.667 1.759 1.759 0 01.08-.668 1.43 1.43 0 01.283-.535c.128-.133.26-.2.418-.2zm1.37 1.706c.332 0 .733.065 1.216.399.293.2.523.269 1.052.468h.003c.255.136.405.266.478.399v-.131a.571.571 0 01.016.47c-.123.31-.516.643-1.063.842v.002c-.268.135-.501.333-.775.465-.276.135-.588.292-1.012.267a1.139 1.139 0 01-.448-.067 3.566 3.566 0 01-.322-.198c-.195-.135-.363-.332-.612-.465v-.005h-.005c-.4-.246-.616-.512-.686-.71-.07-.268-.005-.47.193-.6.224-.135.38-.271.483-.336.104-.074.143-.102.176-.131h.002v-.003c.169-.202.436-.47.839-.601.139-.036.294-.065.466-.065zm2.8 2.142c.358 1.417 1.196 3.475 1.735 4.473.286.534.855 1.659 1.102 3.024.156-.005.33.018.513.064.646-1.671-.546-3.467-1.089-3.966-.22-.2-.232-.335-.123-.335.59.534 1.365 1.572 1.646 2.757.13.535.16 1.104.021 1.67.067.028.135.06.205.067 1.032.534 1.413.938 1.23 1.537v-.043c-.06-.003-.12 0-.18 0h-.016c.151-.467-.182-.825-1.065-1.224-.915-.4-1.646-.336-1.77.465-.008.043-.013.066-.018.135-.068.023-.139.053-.209.064-.43.268-.662.669-.793 1.187-.13.533-.17 1.156-.205 1.869v.003c-.02.334-.17.838-.319 1.35-1.5 1.072-3.58 1.538-5.348.334a2.645 2.645 0 00-.402-.533 1.45 1.45 0 00-.275-.333c.182 0 .338-.03.465-.067a.615.615 0 00.314-.334c.108-.267 0-.697-.345-1.163-.345-.467-.931-.995-1.788-1.521-.63-.4-.986-.87-1.15-1.396-.165-.534-.143-1.085-.015-1.645.245-1.07.873-2.11 1.274-2.763.107-.065.037.135-.408.974-.396.751-1.14 2.497-.122 3.854a8.123 8.123 0 01.647-2.876c.564-1.278 1.743-3.504 1.836-5.268.048.036.217.135.289.202.218.133.38.333.59.465.21.201.477.335.876.335.039.003.075.006.11.006.412 0 .73-.134.997-.268.29-.134.52-.334.74-.4h.005c.467-.135.835-.402 1.044-.7zm2.185 8.958c.037.6.343 1.245.882 1.377.588.134 1.434-.333 1.791-.765l.211-.01c.315-.007.577.01.847.268l.003.003c.208.199.305.53.391.876.085.4.154.78.409 1.066.486.527.645.906.636 1.14l.003-.007v.018l-.003-.012c-.015.262-.185.396-.498.595-.63.401-1.746.712-2.457 1.57-.618.737-1.37 1.14-2.036 1.191-.664.053-1.237-.2-1.574-.898l-.005-.003c-.21-.4-.12-1.025.056-1.69.176-.668.428-1.344.463-1.897.037-.714.076-1.335.195-1.814.12-.465.308-.797.641-.984l.045-.022zm-10.814.049h.01c.053 0 .105.005.157.014.376.055.706.333 1.023.752l.91 1.664.003.003c.243.533.754 1.064 1.189 1.637.434.598.77 1.131.729 1.57v.006c-.057.744-.48 1.148-1.125 1.294-.645.135-1.52.002-2.395-.464-.968-.536-2.118-.469-2.857-.602-.369-.066-.61-.2-.723-.4-.11-.2-.113-.602.123-1.23v-.004l.002-.003c.117-.334.03-.752-.027-1.118-.055-.401-.083-.71.043-.94.16-.334.396-.4.69-.533.294-.135.64-.202.915-.47h.002v-.002c.256-.268.445-.601.668-.838.19-.201.38-.336.663-.336zm7.159-9.074c-.435.201-.945.535-1.488.535-.542 0-.97-.267-1.28-.466-.154-.134-.28-.268-.373-.335-.164-.134-.144-.333-.074-.333.109.016.129.134.199.2.096.066.215.2.36.333.292.2.68.467 1.167.467.485 0 1.053-.267 1.398-.466.195-.135.445-.334.648-.467.156-.136.149-.267.279-.267.128.016.034.134-.147.332a8.097 8.097 0 01-.69.468zm-1.082-1.583V5.64c-.006-.02.013-.042.029-.05.074-.043.18-.027.26.004.063 0 .16.067.15.135-.006.049-.085.066-.135.066-.055 0-.092-.043-.141-.068-.052-.018-.146-.008-.163-.065zm-.551 0c-.02.058-.113.049-.166.066-.047.025-.086.068-.14.068-.05 0-.13-.02-.136-.068-.01-.066.088-.133.15-.133.08-.031.184-.047.259-.005.019.009.036.03.03.05v.02h.003z\"/>"}


def download(os_id: str, href: str, label: str, note: str) -> str:
    """A download button: the system's mark, what to download and for which machines."""
    return (f'<a class="btn btn-primary btn-dl" href="{href}" data-goatcounter-click="cirera-{os_id}">'
            f'<svg class="os" viewBox="0 0 24 24" aria-hidden="true">{OS_ICONS[os_id]}</svg>'
            f'<span class="dl-text"><span>{label}</span><small>{note}</small></span></a>')


def desktop() -> str:
    """The console as an app for Mac, Windows and Linux (tools/make_app.py), from the release the desktop workflow keeps."""
    dl = f"{REPO}/releases/download/cirera"
    return f"""<section id="escritorio" aria-labelledby="escritorio-t"><div class="wrap">
<h2 id="escritorio-t">Cirera en tu ordenador</h2>
<p class="intro">La consola, hecha aplicación para Mac, Windows y Linux: su menú, los juegos de ejemplo dentro y cualquier juego de la Biblioteca. Es el mismo motor, así que el juego es el mismo, con teclado o con mando.</p>
<div class="dl-row">{download("mac", f"{dl}/Cirera-mac.zip", "Descargar para Mac", "Intel y Apple Silicon")}{download("windows", f"{dl}/Cirera-windows.zip", "Descargar para Windows", "64 bits")}{download("linux", f"{dl}/Cirera-linux-x86_64.tar.gz", "Descargar para Linux", "x86_64")}</div>
<p class="meta">Mac: macOS 11 o posterior, una sola aplicación para los Mac con Intel y con Apple Silicon · Windows 10 o posterior · Linux: Ubuntu 22.04, Debian 12 o posteriores · entre 10 y 12 MB</p>
<p class="meta">¿Linux en ARM, como una Raspberry Pi con el sistema de 64 bits? <a href="{dl}/Cirera-linux-aarch64.tar.gz" data-goatcounter-click="cirera-linux-arm">Descárgala para ARM</a>.</p>
<ol class="steps">
<li><h3>Ábrela la primera vez</h3><p>Aún no está firmada por Apple ni por Microsoft, así que el sistema te avisa la primera vez.</p>
<p>En el Mac, descomprime el .zip, arrastra Cirera a Aplicaciones y ábrela. Cuando avise, ve a Ajustes del Sistema → Privacidad y seguridad y pulsa «Abrir igualmente».</p>
<p>En Windows, descomprime el .zip y abre Cirera.exe. Si sale «Windows protegió su PC», pulsa «Más información» y «Ejecutar de todas formas».</p>
<p>En Linux, descomprime el .tar.gz y abre Cirera, dentro de su carpeta. Para instalar juegos soltándolos en la ventana hace falta unzip, que casi todas las distribuciones ya traen.</p></li>
<li><h3>Añade juegos</h3><p>Descarga el .zip de cualquier juego de esta página o de la Biblioteca y suéltalo sobre la ventana de Cirera: se instala y sale en el menú.</p></li>
<li><h3>Juega</h3><p>Flechas para moverte; Z o Intro es A, X o Esc es B, C es C y P es START. Mantén la I (MENU) dos segundos para volver al menú, y F11 para la pantalla completa. En el mando, X o Y hacen de C, y SELECT de MENU. Las partidas se guardan en tu ordenador.</p></li>
</ol>
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
        ("2026-10-17", "17 oct.", "Comentarios y votos en cada juego, y el 3D al estilo PlayStation medido en la placa: luces, deformaciones, perspectiva y recortes."),
        ("2026-10-18", "18 oct.", "Caras 3D con textura y cámaras, animación de recortes, partículas con brillo y una librería de transiciones."),
        ("2026-10-19", "19 oct.", "Instrumentos, envíos y eco para el sonido, mezclas fieles a la Game Boy Advance y un pinball con física de verdad."),
        ("2026-10-20", "20 oct.", "Lápiz y varios dedos en la pantalla táctil, dos pantallas en el simulador, la careta POWERED BY PINYOL en todos los juegos, Lua al doble de velocidad, once ejemplos nuevos y el firmware 0.3.0."),
        ("2026-10-21", "21 oct.", "El menú de la consola sobre cualquier juego, con ajustes, favoritos y logros; partidas entre consolas por radio; movimiento al estilo de Celeste; y el código desde la PSRAM, que acelera el mundo hasta un 30 %."),
        ("2026-10-22", "22 oct.", "Módulos XM y S3M, canciones de FamiStudio, vuelta atrás (rollback) entre consolas, campo de visión en cuadrículas, la memoria de la consola reordenada y el firmware 0.4.0."),
        ("2026-10-23", "23 oct.", "mesh(): modelos 3D dibujados en C, y cuatro juegos con el aspecto de los 32 bits: Selva, Niebla, Recortes y Cajas. Firmware 0.5.0."),
    ]
    li = "".join(f'<li><time datetime="{d}">{label}</time><p>{escape(t)}</p></li>' for d, label, t in items)
    return f"""<div class="days reveal"><h3>Trece días en el repositorio</h3><ol>{li}</ol></div>"""


def thousands(v: int) -> str:
    """As Spanish writes them: 15.095, but 1234."""
    return f"{v:,}".replace(",", ".") if v >= 10000 else str(v)


def footer() -> str:
    """The logo and the licence, two short columns of links, and the small print folded away (it is all still there)."""
    tabs = "".join(f'<li><a href="{HOME}{t}">{name}</a></li>' for t, name in TABS)
    return f"""<footer><div class="wrap foot">
<div class="foot-brand"><img src="img/logo.png" alt="pinyol" width="64" height="42" loading="lazy"><p>Código MIT · arte y sonido CC0</p></div>
<div class="foot-col"><p class="foot-h">Explora</p><ul>{tabs}</ul></div>
<div class="foot-col"><p class="foot-h">El proyecto</p><ul><li><a href="{REPO}">GitHub</a></li><li><a href="{REPO}/blob/main/docs/measurements.md">Mediciones</a></li></ul></div>
<details class="foot-fine"><summary>Marcas, privacidad y datos</summary><div>
<p>Game Boy, PICO-8, Neo Geo y las demás consolas que se nombran son marcas de sus dueños; pinyol y Cirera no tienen relación con ellos.</p>
<p>Apple, Mac y macOS son marcas de Apple; Windows, de Microsoft, y Linux, de Linus Torvalds.</p>
<p>Las visitas, las partidas y el tiempo jugado se cuentan con <a href="https://www.goatcounter.com">GoatCounter</a>, sin cookies ni datos personales.</p>
<p>Los comentarios y los votos de cada juego se guardan en GitHub y se cargan con giscus solo si los pides.</p>
<p>La Biblioteca, el ranking y las cifras de cada juego se leen de GitHub al abrir la página.</p>
</div></details>
</div></footer>"""


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
        "consola/": layout("consola/", "Consola · pinyol", "La consola Cirera, su firmware para instalar desde el navegador, la Cirera como aplicación para Mac, Windows y Linux, y pinyol en RetroArch y RetroPie.",
                           page_head("ESP32-S3 · 480×320 · 60 fps", "Consola", "La Cirera, su firmware para instalar desde el navegador, la misma consola como aplicación para tu ordenador y RetroArch.")
                           + f"\n{console(fw)}\n{desktop()}\n{retroarch()}", fw),
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
