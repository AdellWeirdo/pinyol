"""The site in three languages: the page is written in Spanish (page.py) and translated here, text by text, from
tables in i18n/<lang>.json (each Spanish text and its translation). Every text of the page needs its translation: a
missing one stops the build and is named, so no Spanish slips into the other pages.

    python3 site/i18n.py site/dist/index.html      # the texts a table needs (for a new language, or new texts)
"""
from __future__ import annotations

import json
import re
import sys
from html import escape
from html.parser import HTMLParser
from pathlib import Path

HERE = Path(__file__).resolve().parent
LANGS = {"es": "Español", "ca": "Català", "en": "English"}
ATTRS = ("alt", "aria-label", "title", "content", "placeholder")  # attributes people read (content: meta description)
READ_META = ("description", "og:title", "og:description")
LOCAL = ("img/", "play/", "games/", "editor/", "vendor/", "firmware/", "fonts/", "video/", "styles.css", "site.js",
         "games.js")  # a page's own files
# The language links: left as they are by the walk, then swapped for the ones of each page
KEEP = {"Idioma", *LANGS.values(), *(code.upper() for code in LANGS)}
VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"}


NUMBERS = re.compile(r"^[\d.,–\-\s·%×/=]*(?:ms|fps|MB/s|MB|KB|MHz|min|s|%)?(?:[\d.,–\-\s·%×/=]*(?:ms|fps|MB/s|MB|KB|MHz|min|s|%)?)*$")
# Texts made from data, their numbers and names kept, the rest in each language; {n} parts are translated in turn
RULES = [
    (r"^Nivel (\d+) · (.+)$", {"en": "Level {0} · {1t}", "ca": "Nivell {0} · {1t}"}),
    (r"^(.+) fps en la consola$", {"en": "{0} fps on the console", "ca": "{0} fps a la consola"}),
    (r"^(\d+) comandos$", {"en": "{0} commands", "ca": "{0} ordres"}),
    (r"^(\d+) mil tokens$", {"en": "{0}k tokens", "ca": "{0} mil tokens"}),
    (r"^Jugar a (.+?)(?: \((.+)\))? \(se abre en una pestaña nueva\)$",
     {"en": "Play {0}{1p} (opens in a new tab)", "ca": "Juga a {0}{1p} (s'obre en una pestanya nova)"}),
    (r"^Descargar (.+) para la consola$", {"en": "Download {0} for the console", "ca": "Descarrega {0} per a la consola"}),
    (r"^Ficha de (.+?)(?: \((.+)\))?$", {"en": "Details: {0}{1p}", "ca": "Fitxa de {0}{1p}"}),
    (r"^(.+) · pinyol$", {"en": "{0t} · pinyol", "ca": "{0t} · pinyol"}),  # a tab's title
    (r"^Copiar: (.+)$", {"en": "Copy: {0t}", "ca": "Copia: {0t}"}),
    (r"^(\w+): antes (.+) fps, ahora (.+)$", {"en": "{0}: before, {1t} fps; now {2t}", "ca": "{0}: abans {1t} fps, ara {2t}"}),
    (r"^(\w+): ((?:entre )?\d+(?: y \d+)?) fps$", {"en": "{0}: {1t} fps", "ca": "{0}: {1t} fps"}),
    (r"^entre (\d+) y (\d+)$", {"en": "{0} to {1}", "ca": "entre {0} i {1}"}),  # a range of fps (charts.span)
    (r"^(.+) fps, antes (.+)$", {"en": "{0} fps, was {1}", "ca": "{0} fps, abans {1}"}),
    (r"^Firmware (\S+) · ([\d,]+) MB ·$", {"en": "Firmware {0} · {1n} MB ·", "ca": "Firmware {0} · {1} MB ·"}),
    (r"^Código MIT · arte y sonido CC0 · (\d+) juegos de ejemplo$",
     {"en": "MIT code · CC0 art and sound · {0} example games", "ca": "Codi MIT · art i so CC0 · {0} jocs d'exemple"}),
    (r"^Y (\d+) ejemplos más$", {"en": "And {0} more examples", "ca": "I {0} exemples més"}),
    (r"^Espera unos minutos: arranca con (\d+) juegos en la memoria\.$",
     {"en": "Wait a few minutes: it starts with {0} games in its memory.",
      "ca": "Espera uns minuts: arrenca amb {0} jocs a la memòria."}),
    (r"^(.+) · (antes|ahora)$", {"en": "{0t} · {1t}", "ca": "{0t} · {1t}"}),
]


def by_rule(key: str, lang: str, table: dict) -> str | None:
    """A text made from data, in lang; None when no rule makes it (or a part has no translation)."""
    if NUMBERS.match(key):  # figures and units: English writes 16.6, Catalan and Spanish 16,6
        return re.sub(r"(\d),(\d)", r"\1.\2", key) if lang == "en" else key
    for pattern, out in RULES:
        m = re.match(pattern, key)
        if not m:
            continue
        def part(name: str) -> str | None:  # {0}: as it is; {0t}: translated; {0n}: a number; {0p}: " (translated)"
            g = m.group(int(name[0]) + 1) or ""
            kind = name[1:]
            if kind == "t":
                return table.get(g) or by_rule(g, lang, table) or (g if not worth(g) else None)
            if kind == "n":
                return re.sub(r"(\d),(\d)", r"\1.\2", g) if lang == "en" else g
            if kind == "p":
                return f" ({table.get(g) or by_rule(g, lang, table) or g})" if g else ""
            return g
        parts = {name: part(name) for name in re.findall(r"\{(\w+)\}", out[lang])}
        if any(v is None for v in parts.values()):
            return None
        return re.sub(r"\{(\w+)\}", lambda x: parts[x[1]], out[lang])
    return None


def worth(text: str) -> bool:
    """A text that says something in a language (not a number, a name of a file, punctuation)."""
    return bool(re.search(r"[A-Za-zÀ-ÿ]{2}", text))


class _Walk(HTMLParser):
    def __init__(self, table: dict | None, lang: str = "es"):
        super().__init__(convert_charrefs=True)
        self.table, self.lang, self.out, self.texts, self.missing, self.raw = table, lang, [], [], set(), 0
        self.keep = []  # translate="no": the tag and how deep inside it the walk is, text left as its author wrote it

    def tr(self, text: str) -> str:
        key = text.strip()
        if not key or not worth(key) or key in KEEP or self.keep:
            return text
        self.texts.append(key)
        if self.table is None:
            return text
        new = self.table.get(key) or by_rule(key, self.lang, self.table)
        if new is None:
            self.missing.add(key)
            return text
        return text.replace(key, new)

    def handle_decl(self, decl):
        self.out.append(f"<!{decl}>")

    def handle_starttag(self, tag, attrs):
        raw = self.get_starttag_text()
        a = dict(attrs)
        for name, value in attrs:
            if not value or name not in ATTRS or a.get("translate") == "no" or self.keep:
                continue
            if tag == "meta" and name == "content" and (a.get("name") or a.get("property")) not in READ_META:
                continue  # viewport, CSP, og:type, og:image: not words
            new = self.tr(value)
            if new != value:
                raw = raw.replace(f'{name}="{escape(value)}"', f'{name}="{escape(new)}"', 1)
        if tag in ("script", "style"):
            self.raw += 1
        if tag not in VOID and self.keep and tag == self.keep[-1][0]:
            self.keep[-1][1] += 1
        elif tag not in VOID and a.get("translate") == "no" and not self.get_starttag_text().endswith("/>"):
            self.keep.append([tag, 1])
        self.out.append(raw)

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)

    def handle_endtag(self, tag):
        if tag in ("script", "style"):
            self.raw -= 1
        if self.keep and tag == self.keep[-1][0]:
            self.keep[-1][1] -= 1
            if not self.keep[-1][1]:
                self.keep.pop()
        self.out.append(f"</{tag}>")

    def handle_data(self, data):
        self.out.append(data if self.raw else escape(self.tr(data), quote=False))

    def handle_comment(self, data):
        self.out.append(f"<!--{data}-->")


def page_path(lang: str) -> str:
    """Where the page in lang lives, from the site's root: the Spanish one is the root itself."""
    return "" if lang == "es" else f"{lang}/"


def switcher(lang: str, path: str = "") -> str:
    """The language links of the page in lang (path: where the page is below each language's root, "juegos/x/")."""
    up = "../" * (path.count("/") + (lang != "es"))
    items = []
    for code, name in LANGS.items():
        current = ' aria-current="page"' if code == lang else ""
        items.append(f'<li class="keep"><a href="{up + page_path(code) + path or "./"}" lang="{code}" hreflang="{code}" aria-label="{name}"'
                     f'{current}>{code.upper()}</a></li>')
    return f'<nav class="langs" aria-label="{"Language" if lang == "en" else "Idioma"}"><ul>{"".join(items)}</ul></nav>'


def alternates(site: str, path: str = "") -> str:
    """The <head> links that tell search engines the three pages are one page in three languages."""
    return "".join(f'<link rel="alternate" hreflang="{code}" href="{site}{page_path(code)}{path}">\n' for code in LANGS) + \
        f'<link rel="alternate" hreflang="x-default" href="{site}{path}">'


def relocate(html: str, up: str) -> str:
    """The page's own links (img/, play/, games/...) from a folder `up` below the site's root ("../", "../../")."""
    return re.sub(r"""((?:src|href|poster|manifest|data-play|data-src)="|url\(')((?:\.\./)*)(""" +
                  "|".join(re.escape(p) for p in LOCAL) + ")", lambda m: m[1] + up + m[2] + m[3], html)


def texts(html: str) -> list[str]:
    w = _Walk(None)
    w.feed(html)
    return list(dict.fromkeys(w.texts))


def translate(html: str, lang: str, path: str = "") -> str:
    """The Spanish page in lang, its local links one folder up (it lives in <lang>/; path: where it is below that)."""
    table = json.loads((HERE / "i18n" / f"{lang}.json").read_text(encoding="utf-8"))
    w = _Walk(table, lang)
    w.feed(html)
    w.close()
    if w.missing:
        raise SystemExit(f"i18n/{lang}.json lacks {len(w.missing)} texts, first: " + " | ".join(sorted(w.missing)[:8]))
    out = "".join(w.out).replace('<html lang="es">', f'<html lang="{lang}">', 1)
    out = relocate(out, "../")
    out = out.replace('href="../play/player.html?', f'href="../play/player.html?lang={lang}&amp;')  # the player in lang too
    out = re.sub(r'href="((?:\.\./)+)play/player\.html\?(?!lang=)', rf'href="\1play/player.html?lang={lang}&amp;', out)
    out = out.replace('href="../editor/"', f'href="../editor/?lang={lang}"')  # and the editor
    out = re.sub(r'<link rel="canonical" href="([^"]+)">',
                 lambda m: f'<link rel="canonical" href="{m[1][:len(m[1]) - len(path)]}{page_path(lang)}{path}">', out)
    return re.sub(r'<nav class="langs".*?</nav>', lambda _: switcher(lang, path), out, count=1, flags=re.S)


if __name__ == "__main__":  # the texts no table or rule has yet, for each language
    html = Path(sys.argv[1]).read_text(encoding="utf-8")
    for lang in ("en", "ca"):
        path = HERE / "i18n" / f"{lang}.json"
        table = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
        todo = [t for t in texts(html) if t not in table and by_rule(t, lang, table) is None]
        print(f"{lang}: {len(todo)}")
        print(json.dumps(todo, ensure_ascii=False, indent=1))
