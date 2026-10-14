"""The performance section's charts, as plain HTML and inline SVG (no chart library): every number is a measure taken
on the console, from np2d's docs/measurements.md or the board logs kept in src/data/board.json."""
from __future__ import annotations

from html import escape

BUDGET_MS = 16.6  # one frame at 60 fps
PANEL_MS, WIRE_MS = 8.1, 7.68  # sending a whole frame to the panel, and the wire alone (docs/measurements.md)
FPS_TOP = 64      # the fps axis runs 0..64 so 60 and 61 do not touch the edge

# Rendering one 240x160 logical frame on one core, best of five (docs/measurements.md, 2026-10-11)
SCENES = [
    ("Una capa de tiles", 1.96, 11.8),
    ("128 sprites de 16×16", 2.24, 13.5),
    ("Una capa afín a pantalla completa", 3.34, 20.0),
    ("Mezcla alfa de dos frames enteros", 4.03, 24.2),
    ("Mode 7: afín, una capa, 64 sprites", 6.28, 37.7),
    ("4 capas de tiles", 6.50, 39.0),
    ("GBA modo 0: 4 capas, 128 sprites", 8.64, 51.9),
    ("Todo: afín, 4 capas, 128 sprites", 11.88, 71.3),
]
# memcpy, 1 MB (docs/measurements.md)
MEMORY = [
    ("RAM interna → RAM interna", 381.0),
    ("PSRAM → RAM interna", 84.7),
    ("RAM interna → PSRAM", 48.5),
    ("PSRAM → PSRAM", 31.9),
]


def num(x: float, d: int = 1) -> str:
    """Spanish decimals: 16,6."""
    return f"{x:.{d}f}".replace(".", ",")


def fps_range(r: tuple[int, int]) -> str:
    return f"{r[0]}" if r[0] == r[1] else f"{r[0]}–{r[1]}"


def looks_chart(looks: list[dict]) -> str:
    """Each look's frame rate on the console as a range (its slowest and fastest second), the first measure behind."""
    rows = []
    for n, k in enumerate(looks):
        now, was = k["fps"], k.get("was")
        pct = lambda v: f"{v / FPS_TOP * 100:.2f}%"
        ghost = (f'<span class="rg was" style="--a:{pct(was[0])};--b:{pct(max(was[1], was[0] + 1))}"></span>'
                 if was else "")
        tone = "ok" if now[0] >= 56 else "mid" if now[0] >= 38 else "low"
        said = f"{fps_range(now)} fps" + (f", antes {fps_range(was)}" if was else "")
        rows.append(f"""<tr style="--n:{n}"><th scope="row">{escape(k['name'])}<small>{escape(k['example'])}</small></th>
<td><div class="track" aria-hidden="true">{ghost}<span class="rg now {tone}" style="--a:{pct(now[0])};--b:{pct(max(now[1], now[0] + 1))}"></span></div>
<span class="val">{said}</span></td></tr>""")
    ticks = "".join(f'<span style="--x:{v / FPS_TOP * 100:.2f}%">{v}</span>' for v in (0, 30, 60))
    return f"""<figure class="chart reveal" id="chart-looks">
<figcaption><h3>Doce aspectos, en fotogramas por segundo</h3>
<p>El segundo más lento y el más rápido de cada ejemplo jugado en la consola. En gris, la primera medida, antes de optimizar.</p></figcaption>
<table class="ranges"><thead><tr><th scope="col">Aspecto</th><th scope="col"><span class="sr">fps</span><div class="axis" aria-hidden="true">{ticks}</div></th></tr></thead>
<tbody>{''.join(rows)}</tbody></table>
<div class="legend" aria-hidden="true"><span><span class="key now"></span>ahora</span> <span><span class="key was"></span>antes</span> <span><span class="key line"></span>60 fps</span></div>
</figure>"""


def _poly(series: list[float], w: int, h: int) -> str:
    n = len(series)
    step = w / max(1, n - 1)
    return " ".join(f"{i * step:.1f},{h - min(v, FPS_TOP) / FPS_TOP * h:.1f}" for i, v in enumerate(series))


def trace_svg(before: list[float] | None, after: list[float], label: str, w: int = 300, h: int = 110) -> str:
    y = lambda v: f"{h - v / FPS_TOP * h:.1f}"
    small = h < 60  # a sparkline: its 30 and 60 lines without numbers
    lines = "".join(f'<line class="grid" x1="0" x2="{w}" y1="{y(v)}" y2="{y(v)}"/>'
                    + ("" if small else f'<text x="{w}" y="{float(y(v)) - 3:.1f}">{v}</text>') for v in (30, 60))
    was = f'<polyline class="was" pathLength="1" points="{_poly(before, w, h)}"/>' if before else ""
    return (f'<svg viewBox="0 -4 {w} {h + 8}" role="img" aria-label="{escape(label)}" preserveAspectRatio="none">'
            f'{lines}{was}<polyline class="now" pathLength="1" points="{_poly(after, w, h)}"/></svg>')


def traces_chart(board: dict) -> str:
    """Second by second, before and after, for the four examples the board made faster."""
    cards = []
    for t in board["traces"]:
        b, a = t["before"], t["after"]
        label = (f"{t['id']}: antes entre {min(b['fps']):.0f} y {max(b['fps']):.0f} fps, "
                 f"ahora entre {min(a['fps']):.0f} y {max(a['fps']):.0f}")
        cards.append(f"""<li class="trace">
<p class="who"><b>{escape(t['id'])}</b> <span>{escape(t['look'])} · {escape(t['scene'])}</span></p>
{trace_svg(b['fps'], a['fps'], label)}
<p class="ms"><span class="from">{num(b['ms'])}</span><span class="arrow" aria-hidden="true">→</span><b data-count="{a['ms']}" data-from="{b['ms']}" data-dec="1">{num(a['ms'])}</b> <small>ms por frame</small></p>
</li>""")
    steady = []
    for s in board["steady"]:
        label = f"{s['id']}: entre {min(s['fps']):.0f} y {max(s['fps']):.0f} fps"
        steady.append(f"""<li><span class="who"><b>{escape(s['id'])}</b> {escape(s['look'])}</span>
{trace_svg(None, s['fps'], label, 160, 40)}<span class="v">{min(s['fps']):.0f}–{max(s['fps']):.0f}</span></li>""")
    return f"""<figure class="chart reveal" id="chart-traces">
<figcaption><h3>Segundo a segundo</h3>
<p>Cada punto es un segundo de juego en la placa: una línea de rendimiento por segundo mientras un guion juega solo. Discontinua, la primera medida; continua, la de ahora.</p></figcaption>
<ul class="traces">{''.join(cards)}</ul>
<p class="sub">Los que ya iban a 60 desde el principio:</p>
<ul class="steady">{''.join(steady)}</ul>
</figure>"""


def bars(rows: list[tuple[str, float, str]], top: float, mark: float | None, mark_label: str) -> str:
    """Horizontal bars, value / top wide; an optional mark line (a budget)."""
    out = []
    for n, (name, v, shown) in enumerate(rows):
        over = mark is not None and v > mark
        out.append(f"""<tr style="--n:{n}"><th scope="row">{escape(name)}</th><td><div class="track" aria-hidden="true">
<span class="bar{' over' if over else ''}" style="--w:{min(v / top, 1) * 100:.2f}%"></span></div><span class="val">{shown}</span></td></tr>""")
    if mark is None:
        return f'<table class="bars"><tbody>{"".join(out)}</tbody></table>'
    x = f"{mark / top * 100:.2f}%"
    head = (f'<thead><tr><th><span class="sr">Medida</span></th><td><div class="axis"><span style="--x:{x}">{mark_label}</span></div>'
            f'<span></span></td></tr></thead>')
    return f'<table class="bars marked" style="--m:{x}">{head}<tbody>{"".join(out)}</tbody></table>'


def profile_chart(board: dict) -> str:
    """How a cost is found: the same scene played again with one thing taken away each time."""
    g = next(p for p in board["profiles"] if p["id"] == "gotico")
    lab = next(p for p in board["profiles"] if p["id"] == "laberinto")
    top = max(v for _, v in g["steps"]) * 1.08
    gb = bars([(n, v, f"{num(v)} ms") for n, v in g["steps"]], top, BUDGET_MS, "16,6 ms = 60 fps")
    rows = [(f"{n} · antes", v, f"{num(v)} ms") for n, v in lab["before"]]
    rows = [r for pair in zip(rows, [(f"{n} · ahora", v, f"{num(v)} ms") for n, v in lab["after"]]) for r in pair]
    lb = bars(rows, max(v for _, v, _ in rows) * 1.08, BUDGET_MS, "16,6 ms")
    return f"""<figure class="chart reveal" id="chart-profile">
<figcaption><h3>Cómo se encuentra lo que cuesta</h3>
<p>La misma escena, jugada otra vez quitando una cosa cada vez. En gotico, los dos rayos de luna mezclados al vuelo se comían 13 ms por frame: ahora vienen ya pintados en el fondo, y el juego pasó de 31 a 60 fps.</p></figcaption>
<div class="two"><div><p class="sub">gotico, antes del arreglo (ms por frame)</p>{gb}</div>
<div><p class="sub">laberinto: el raycast antes y después de optimizarlo (ms por frame)</p>{lb}</div></div>
</figure>"""


def cost_chart() -> str:
    scenes = bars([(n, pct, f"{num(ms, 2)} ms · {num(pct)} %") for n, ms, pct in SCENES], 100, 100, "un núcleo entero")
    mem = bars([(n, v, f"{num(v)} MB/s") for n, v in MEMORY], 400, None, "")
    return f"""<figure class="chart reveal" id="chart-cost">
<figcaption><h3>Lo que cuesta dibujar, en un núcleo</h3>
<p>Un frame lógico de 240×160 con contenido sintético, el mejor de cinco intentos, en porcentaje de un núcleo a 60 fps. La consola tiene dos.</p></figcaption>
{scenes}
<p class="sub">Y por qué casi todo se dibuja en la RAM interna: copiar 1 MB.</p>
{mem}
</figure>"""


def strips_demo(shot: str, shot2: str, alt: str) -> str:
    """How a frame reaches the panel: 15 strips of 32 columns, each drawn by both cores (left and right halves) in
    internal RAM while the one before goes out by DMA. The demo alternates two frames so each strip visibly changes."""
    strips = "".join(f'<i style="--i:{i};--p:{i / 14 * 100:.3f}%"><b class="c0"></b><b class="c1"></b><b class="next"></b><b class="back"></b></i>'
                     for i in range(15))
    return f"""<figure class="chart reveal" id="chart-strips">
<figcaption><h3>Cómo llega un frame a la pantalla</h3>
<p>No hay un frame entero en memoria: la pantalla se dibuja en 15 franjas de 32 columnas. Los dos núcleos se reparten cada franja, mitad izquierda y mitad derecha, en la RAM interna, mientras la anterior sale por DMA hacia el panel.</p></figcaption>
<div class="strips" data-live style="--shot:url('{shot}');--shot2:url('{shot2}')" role="img" aria-label="{escape(alt)}">{strips}</div>
<div class="legend" aria-hidden="true"><span><span class="key c0"></span>núcleo 0</span> <span><span class="key c1"></span>núcleo 1</span> <span><span class="key dma"></span>ya en el panel</span></div>
<p class="sub">A cámara lenta: un frame de verdad tarda 16,6 ms; aquí, 2,4 segundos. Enviar uno entero cuesta {num(PANEL_MS)} ms, de los que {num(WIRE_MS)} son el propio cable.</p>
</figure>"""


def stats_band(board: dict, tests: int) -> str:
    audio = round(max(board["audio_pct"]))
    heaviest = SCENES[-1][2]
    items = [
        (str(round(heaviest)), "%", "de un núcleo en la escena más pesada: afín, cuatro capas y 128 sprites"),
        (num(PANEL_MS), "ms", f"para mandar un frame entero al panel; el cable solo ya son {num(WIRE_MS)}"),
        (str(audio), "%", "de un núcleo para el sonido mientras se juega"),
        (str(tests), "", "pruebas que juegan solas y comparan cada frame, en cada cambio"),
    ]
    li = "".join(f'<li><b><span data-count="{v.replace(",", ".")}" data-dec="{1 if "," in v else 0}">{v}</span>'
                 f'<small>{u}</small></b><span>{escape(t)}</span></li>' for v, u, t in items)
    return f'<ul class="stats perf-stats reveal">{li}</ul>'
