"""A page for each game, juegos/<id>/ (and ca/juegos/<id>/, en/juegos/<id>/): its picture and what it is, its numbers
(visits, plays, time played, likes, comments, its place in the ranking), its card, its comments and votes, and more
games. The numbers come from stats.json, which tools/stats.py makes every hour; games.js reads it when the page opens.
The comments and votes are giscus (a GitHub Discussion per game), loaded only when someone asks for them.

The pages are written in Spanish with the site's own links (img/, play/...) and moved down here by i18n.relocate.
"""
from __future__ import annotations

import json
from html import escape
from pathlib import Path

import i18n
import page

# giscus: a Discussion per game (its id), in the category "Juegos" (an Announcement category: only giscus and the
# maintainers open Discussions there). With category_id empty the page says comments are coming and loads nothing.
# (docs/comments.md): until then the pages say the comments are on their way.
GISCUS = {"repo": "ipaud/pinyol", "repo_id": "R_kgDOVJaigg", "category": "Juegos", "category_id": "DIC_kwDOVJaigs4DIxP0"}
HOME = page.HOME  # the language's home page, from a game's page (../../ once published)
# A game whose game.json describes it in another language, as the site says it in Spanish (the tables translate it)
SAID = {"control": "Realizas el informativo de la noche de 1994 desde la sala de control: cortas cámaras, lanzas el "
                   "vídeo y pones rótulos al ritmo de la sintonía, con el LED de la consola como piloto rojo. Hasta que "
                   "se enciende una cámara que no existe y te mira a ti."}
HUES = {"Vectorial": "#7cf7ff", "Game Boy": "#8bac0f", "ZX Spectrum": "#ff3b3b", "Primera persona": "#c08a5a",
        "Mega Drive": "#2f7bff"}


def catalog(np2d: Path, measured: list[dict]) -> list[dict]:
    """Every game the site plays: the looks' examples (with their fps as measured, page.measured), Codex's five, the
    other examples, then the Library's."""
    shelf = {k["example"]: k for k in measured}
    codex = {j["id"]: j for j in page.CODEX}
    ids = [k["example"] for k in measured] + [j["id"] for j in page.CODEX] + [g for g, _ in page.OTHERS]
    games = []
    for gid in ids:
        meta = json.loads((np2d / "examples" / gid / "game.json").read_text(encoding="utf-8"))
        g = dict(id=gid, title=dict(page.OTHERS).get(gid) or meta.get("title", gid),
                 description=SAID.get(gid, meta.get("description", "")), zip=f"games/{gid}.zip", play=page.play_url(gid),
                 image=f"img/covers/{gid}.png", alt="", hue="#e8344e", kind="example", code=f"{page.REPO}/tree/main/examples/{gid}")
        if gid in shelf:
            k = shelf[gid]
            g.update(kind="look", look=k, image=f"img/looks/{k['id']}.png", alt=k["alt"], hue=k["hue"])
        elif gid in codex:
            j = codex[gid]
            g.update(kind="codex", job=j, title=j["title"], image=f"img/codex/{gid}.png", alt=j["alt"], hue=HUES.get(j["look"], g["hue"]))
        games.append(g)
    for lg in json.loads((np2d / "library/library.json").read_text(encoding="utf-8")):
        zip_url = f"{page.RAW}/library/{lg['id']}/game.zip"
        games.append(dict(id=lg["id"], title=lg["title"], description=lg.get("description", ""), zip=zip_url,
                          play=page.play_url(lg["id"]), image=f"img/covers/{lg['id']}.png" if lg.get("cover") else "",
                          alt="", hue="#ffc94a", kind="library", lib=lg, code=f"{page.REPO}/tree/main/library/{lg['id']}"))
    ids = [g["id"] for g in games]
    assert len(set(ids)) == len(ids), f"two games with one id: {sorted(i for i in ids if ids.count(i) > 1)}"
    return games


def picker(games: list[dict]) -> str:
    """The Juega tab's list: every game, in groups, each a link to itself on the tab (juega.js plays it in place). The
    Library's group says where its list is, so juega.js adds the games approved since the site was built."""
    groups = [("library", "De la Biblioteca"), ("look", "Doce aspectos"), ("codex", "La escalera de Codex"), ("example", "Otros ejemplos")]
    lib = f' id="picks-library" data-src="{page.RAW}/library/library.json" data-base="{page.RAW}/library/"'
    out = []
    for kind, name in groups:
        items = "".join(
            f'<li><a class="pick" href="{page.play_url(g["id"])}" data-id="{g["id"]}">'
            + (f'<img src="{g["image"]}" alt="" width="240" height="160" loading="lazy" decoding="async">' if g["image"] else '<span class="noshot"></span>')
            + f'<span translate="no">{escape(g["title"])}</span></a></li>' for g in games if g["kind"] == kind)
        if items or kind == "library":  # (a group with nothing in it shows nothing)
            out.append(f'<h3>{name}</h3><ul class="picks"{lib if kind == "library" else ""}>{items}</ul>')
    return "".join(out)


def public(games: list[dict]) -> str:
    """What games.js needs of each game (the ranking, the cover of the week), as JSON for a <script> in the page."""
    out = [{"id": g["id"], "title": g["title"], "image": g["image"], "kind": g["kind"],
            "zip": g["zip"] if g["kind"] == "library" else f"../games/{g['id']}.zip"} for g in games]
    return json.dumps(out, ensure_ascii=False, separators=(",", ":")).replace("<", "\\u003c")  # no tag can open in it


def head(g: dict) -> str:
    path = f"juegos/{g['id']}/"
    csp = (f"default-src 'self'; img-src 'self' data: https://raw.githubusercontent.com {page.COUNTER}; style-src 'self' 'unsafe-inline'; "
           f"script-src 'self' https://giscus.app; frame-src https://giscus.app; font-src 'self'; "
           f"connect-src 'self' https://raw.githubusercontent.com {page.COUNTER}; object-src 'none'; base-uri 'self'; form-action 'none'")
    image = page.SITE + (g["image"] or "img/og.png")
    own = ' translate="no"' if g["kind"] == "library" else ""  # people's words stay as they wrote them
    return f"""<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="{csp}">
<title translate="no">{escape(g['title'])} · pinyol</title>
<meta name="description" content="{escape(g['description'])}"{own}>
<meta property="og:title" content="{escape(g['title'])} · pinyol" translate="no">
<meta property="og:description" content="{escape(g['description'])}"{own}>
<meta property="og:type" content="website">
<meta property="og:image" content="{image}">
<meta name="theme-color" content="#0b0e1f">
<link rel="canonical" href="{page.SITE}{path}">
{i18n.alternates(page.SITE, path)}
<link rel="icon" href="img/icon.png">
<link rel="stylesheet" href="styles.css">
<script src="games.js" defer></script>
<script data-goatcounter="{page.COUNTER}/count" async src="vendor/goatcounter/count.js"></script>
</head>"""


def kicker(g: dict) -> str:
    if g["kind"] == "look":
        return f"<span>{escape(g['look']['name'])}</span> · <span>{escape(g['look']['era'])}</span>"
    if g["kind"] == "codex":
        return f"<span>La escalera</span> · <span>Nivel {g['job']['level']} · {escape(g['job']['look'])}</span>"
    if g["kind"] == "library":
        return "<span>La Biblioteca</span>"
    return "<span>Ejemplo de pinyol</span>"


def facts(g: dict, size_kb: int | None) -> str:
    rows = []
    if g["kind"] == "look":
        k = g["look"]
        rows += [("Aspecto", escape(k["name"])), ("En la consola", f"{page.charts.fps_range(k['fps'])} fps"),
                 ("Dibujo", "arte generado con IA" if k["art"] else "dibujado con código")]
    if g["kind"] == "codex":
        j = g["job"]
        rows += [("Encargo", f"<blockquote><p>{escape(j['prompt'])}</p></blockquote>"), ("Lo hizo", escape(page.CODEX_RUN)),
                 ("Tiempo", escape(j["time"])), ("Comandos", str(j["commands"])), ("En la consola", f"{escape(j['fps'])} fps"),
                 ("Después", escape(j["after"]))]
    if g["kind"] == "library":
        lg = g["lib"]
        who = f'<a href="https://github.com/{escape(lg["author"])}" translate="no">@{escape(lg["author"])}</a>'
        rows += [("Autor", who), ("Licencia", f'<span translate="no">{escape(lg.get("license", ""))}</span>')]
        if lg.get("date"):
            rows.append(("Publicado", escape("/".join(reversed(lg["date"].split("-"))))))
        if lg.get("issue"):
            rows.append(("En la Biblioteca", f'<a href="{page.REPO}/issues/{int(lg["issue"])}">#{int(lg["issue"])}</a>'))
    else:
        rows += [("Licencia", "código MIT · arte y sonido CC0")]
    if size_kb:
        rows.append(("El .zip", f"{size_kb} KB"))
    rows.append(("Código", f'<a href="{g["code"]}">GitHub</a>'))
    return "".join(f"<div><dt>{a}</dt><dd>{b}</dd></div>" for a, b in rows)


def related(g: dict, games: list[dict]) -> list[dict]:
    """Four more: the next ones of its kind, then whatever follows in the catalog."""
    i = games.index(g)
    order = games[i + 1:] + games[:i]
    same = [o for o in order if o["kind"] == g["kind"]]
    return (same + [o for o in order if o not in same])[:4]


def card(o: dict) -> str:
    shot = f'<img src="{o["image"]}" alt="" width="480" height="320" loading="lazy" decoding="async">' if o["image"] else ""
    return (f'<li class="cart" style="--hue:{o["hue"]}"><div class="shot">{shot}</div><div class="label">'
            f'<h3><a class="stretch" href="{HOME}juegos/{o["id"]}/" translate="no">{escape(o["title"])}</a></h3></div></li>')


def render(g: dict, games: list[dict], size_kb: int | None) -> str:
    """The game's page in Spanish, with the site's own links as on the home page (relocated by write())."""
    shot = (f'<img src="{g["image"]}" alt="{escape(g["alt"])}" width="480" height="320" decoding="async" fetchpriority="high">'
            if g["image"] else '<span class="noshot pixel">pinyol</span>')
    own = ' translate="no"' if g["kind"] == "library" else ""  # people's words stay as they wrote them
    by = (f'Por <a href="https://github.com/{escape(g["lib"]["author"])}" translate="no">@{escape(g["lib"]["author"])}</a>'
          if g["kind"] == "library" else "Hecho con pinyol")
    talk = ' data-ready=""' if GISCUS["category_id"] else ""
    return page.new_tabs(f"""{head(g)}
<body>
{page.header("biblioteca/" if g["kind"] == "library" else "crear/", f"juegos/{g['id']}/")}
<main id="main" class="game" style="--hue:{g['hue']}">
<section class="game-hero"><div class="wrap">
<figure class="game-shot">{shot}</figure>
<div class="game-info">
<p class="kicker pixel">{kicker(g)}</p>
<h1 class="game-title" translate="no">{escape(g['title'])}</h1>
<p class="lede"{own}>{escape(g['description'])}</p>
<div class="actions"><a class="btn btn-primary" href="{g['play']}" data-goatcounter-click="jugar/{g['id']}">Jugar</a><a class="btn btn-ghost" href="{g['zip']}" download data-goatcounter-click="descargar/{g['id']}">Descargar .zip</a></div>
<p class="meta">{by}</p>
</div></div></section>
<section class="game-numbers" aria-labelledby="numbers-t"><div class="wrap">
<h2 id="numbers-t">Las cifras</h2>
<dl class="tally" id="tally" data-id="{g['id']}" data-src="{page.STATS}" aria-busy="true">
<div><dt>Visitas</dt><dd data-k="visits">—</dd></div><div><dt>Partidas</dt><dd data-k="plays">—</dd></div>
<div><dt>Tiempo jugado</dt><dd data-k="minutes">—</dd></div><div><dt>Me gusta</dt><dd data-k="likes">—</dd></div>
<div><dt>Comentarios</dt><dd data-k="comments">—</dd></div><div><dt>En el ranking</dt><dd data-k="rank">—</dd></div>
</dl>
<p class="tally-note" id="tally-note" role="status">Las cifras se actualizan cada hora.</p>
</div></section>
<section class="game-sheet" aria-labelledby="sheet-t"><div class="wrap">
<h2 id="sheet-t">La ficha</h2>
<dl class="sheet">{facts(g, size_kb)}</dl>
</div></section>
<section class="game-talk" id="comentarios" aria-labelledby="talk-t"><div class="wrap">
<h2 id="talk-t">Comentarios y votos</h2>
<p class="intro">Vota con una reacción (👍 ❤️ 🎉 🚀) y deja tu comentario con tu cuenta de GitHub. Los votos ordenan el ranking y eligen la portada de la semana.</p>
<div class="talk" id="talk" tabindex="-1" data-term="{g['id']}" data-repo="{GISCUS['repo']}" data-repo-id="{GISCUS['repo_id']}" data-category="{GISCUS['category']}" data-category-id="{GISCUS['category_id']}"{talk}>
<p class="talk-soon">Los comentarios y los votos llegan muy pronto.</p>
<p class="talk-ask"><button class="btn btn-primary" type="button" id="talk-load">Ver los comentarios y votar</button></p>
<p class="talk-note">Se cargan desde giscus.app, con los comentarios guardados en GitHub, solo cuando los pides.</p>
</div>
</div></section>
<section class="game-more" aria-labelledby="more-t"><div class="wrap">
<h2 id="more-t">Más juegos</h2>
<ul class="jobs">{"".join(card(o) for o in related(g, games))}</ul>
</div></section>
</main>
{page.footer()}
</body>
</html>
""")


def write(dist: Path, games: list[dict], versioned=lambda html: html) -> int:
    """Each game's page in the three languages, under dist/juegos/ and dist/<lang>/juegos/."""
    for g in games:
        zip_file = dist / g["zip"] if g["kind"] != "library" else None
        size = round(zip_file.stat().st_size / 1024) if zip_file and zip_file.exists() else None
        page.publish(dist, versioned(render(g, games, size)), f"juegos/{g['id']}/")
    return len(games)
