# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10"]
# ///
"""The Library: games people send through a GitHub issue form, checked, then published in library/ for the site.

    python3 tools/library.py check-issue --out DIR --headless build/pinyol_headless   # body in $BODY
    python3 tools/library.py check GAME.zip --out DIR --headless build/pinyol_headless
    python3 tools/library.py comment DIR                                             # the answer, in Markdown
    python3 tools/library.py publish DIR --issue N --author LOGIN                     # into library/

check (run on untrusted input, with no write access): opens the zip with limits (size, files, no paths outside it),
keeps only what the console reads, validates the game and plays it for ten seconds headless, takes its cover. Writes
DIR/result.json ({"ok", "id", "title", "errors", ...}), DIR/game/ (the clean folder) and DIR/cover.png.
publish (trusted, runs no game code): packs DIR/game into library/<id>/game.zip, copies the cover, adds the entry to
library/library.json. A game id belongs to whoever published it first; they can send new versions.
update (the maintainer, from a .zip): a new version of a game already in the Library, checked and published in its
author's name, keeping the title, description and licence its form gave it.

    python3 tools/library.py update GAME.zip --headless build/pinyol_headless
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile
from datetime import date
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parent.parent
LIBRARY = ROOT / "library"
sys.path.insert(0, str(Path(__file__).resolve().parent))
import pack_game  # noqa: E402

# ponytail: published games live in git (library/ on main), so a zip stays under GitHub's 50 MB push warning; once
# library/ nears ~1 GB, move the zips out (gh-pages pushed as an orphan, or a repo of their own)
MAX_ZIP = 48 << 20        # bytes, as sent
MAX_UNPACKED = 96 << 20   # bytes, all files once opened (a zip bomb stops here); the web player's own limit
MAX_FILES = 4000          # the web player's own limit too (platform/web/player.html, LIMITS)
PLAY_TICKS = 600          # ten seconds of play
# the zip dragged into the form (GitHub takes files up to 25 MB), or a bigger one linked from a release of the sender's
ATTACHMENT = re.compile(r"https://github\.com/(?:user-attachments/files/\d+|[A-Za-z0-9-]{1,39}/[A-Za-z0-9._-]{1,100}"
                        r"/releases/download/[A-Za-z0-9._%+-]{1,100})/[A-Za-z0-9._%-]+\.zip")
LICENSES = ("CC0", "CC BY 4.0", "MIT")


def said(text: str) -> str:
    """A description as the site shows it: without the game's .zip, when it was dropped there too."""
    return re.sub(r"\[[^\]]*\]\(\s*\)", "", ATTACHMENT.sub("", text)).strip()


def form_fields(body: str) -> dict[str, str]:
    """An issue form's answers: '### Label' then its value, as GitHub writes them."""
    fields, label = {}, None
    for line in body.splitlines():
        if line.startswith("### "):
            label = line[4:].strip()
            fields[label] = ""
        elif label:
            fields[label] += line + "\n"
    return {k: v.strip() for k, v in fields.items()}


def safe_extract(zip_path: Path, dest: Path) -> list[str]:
    """The zip's files into dest, refusing what a game never needs; the errors, if any."""
    if zip_path.stat().st_size > MAX_ZIP:
        return [f"El .zip pesa {zip_path.stat().st_size >> 20} MB: el máximo son {MAX_ZIP >> 20} MB."]
    try:
        z = zipfile.ZipFile(zip_path)
    except zipfile.BadZipFile:
        return ["El archivo no es un .zip válido."]
    infos = [i for i in z.infolist() if not i.is_dir()]
    if len(infos) > MAX_FILES:
        return [f"El .zip tiene {len(infos)} archivos: el máximo son {MAX_FILES}."]
    if sum(i.file_size for i in infos) > MAX_UNPACKED:
        return [f"Descomprimido pasa de {MAX_UNPACKED >> 20} MB."]
    for i in infos:
        p = PurePosixPath(i.filename)
        if p.is_absolute() or ".." in p.parts or "\\" in i.filename or (i.external_attr >> 16) & 0o170000 == 0o120000:
            return [f"Ruta no permitida en el .zip: {i.filename!r}."]
    # the game: game.json at the top, or else the one folder holding it; what lies beside it (notes, the editor's
    # project) stays out
    paths = [PurePosixPath(i.filename) for i in infos]
    tops = {p.parts[0] for p in paths if len(p.parts) == 2 and p.parts[1] == "game.json"}
    root = () if any(p.parts == ("game.json",) for p in paths) else (next(iter(tops)),) if len(tops) == 1 else None
    if root is None:
        return ["No hay game.json en la raíz del juego (o en su carpeta)."]
    for i in infos:
        p = PurePosixPath(i.filename)
        parts = p.parts[len(root):] if p.parts[:len(root)] == root else ()
        if not parts or not pack_game.runtime_file(Path(*parts)):
            continue  # sources, notes, saves: not what the console plays
        out = dest.joinpath(*parts)
        out.parent.mkdir(parents=True, exist_ok=True)
        with z.open(i) as src, open(out, "wb") as dst:
            shutil.copyfileobj(src, dst)
    return [] if (dest / "game.json").is_file() else ["No hay game.json en la raíz del juego (o en su carpeta)."]


def check_game(game: Path, headless: Path, out: Path) -> dict:
    errors, meta = [], {}
    try:
        meta = json.loads((game / "game.json").read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        return {"ok": False, "errors": [f"game.json no se puede leer: {e}"]}
    gid, title = str(meta.get("id", "")), str(meta.get("title", "")).strip()
    if not re.fullmatch(r"[a-z0-9_-]{1,40}", gid):
        errors.append(f"El id de game.json debe ser de 1 a 40 letras minúsculas, cifras, _ o - (es {gid!r}).")
    if (ROOT / "examples" / gid).is_dir():  # its page, cover and votes would be the example's
        errors.append(f"El id {gid!r} ya es el de un ejemplo de pinyol: elige otro en game.json.")
    if not 1 <= len(title) <= 48:
        errors.append("game.json necesita un title de 1 a 48 caracteres.")
    if errors:
        return {"ok": False, "id": gid, "title": title, "errors": errors}
    with tempfile.TemporaryDirectory() as t:
        v = subprocess.run([str(headless), "--game", str(game), "--saves", t, "--fresh", "--validate"],
                           capture_output=True, text=True, timeout=60)
        if v.returncode:
            errors.append("El motor no acepta el juego:\n" + (v.stdout + v.stderr).strip()[-1500:])
        else:
            script = Path(t) / "play.script"
            script.write_text(f"tick 90\nshot cover\ntick {PLAY_TICKS - 90}\nexpect_ok\n")
            try:
                p = subprocess.run([str(headless), "--game", str(game), "--saves", t, "--fresh", "--script", str(script)],
                                   capture_output=True, text=True, timeout=120)
                if p.returncode:
                    errors.append("El juego falla al jugarlo diez segundos:\n" + (p.stdout + p.stderr).strip()[-1500:])
            except subprocess.TimeoutExpired:
                errors.append("El juego no ha terminado diez segundos de juego en dos minutos.")
            cover = Path(t) / "cover.ppm"
            if cover.exists():
                from PIL import Image
                Image.open(cover).save(out / "cover.png", optimize=True)
    return {"ok": not errors, "id": gid, "title": title, "description": str(meta.get("description", "")).strip()[:300],
            "engine": str(meta.get("engine", "")), "errors": errors}


def check(zip_path: Path, out: Path, headless: Path, fields: dict | None = None) -> dict:
    out.mkdir(parents=True, exist_ok=True)
    game = out / "game"
    errors = safe_extract(zip_path, game)
    result = {"ok": False, "errors": errors} if errors else check_game(game, headless, out)
    if fields is not None:
        lic = fields.get("Licencia", "")
        if lic not in LICENSES:
            result["errors"].append(f"Elige una licencia de la lista ({', '.join(LICENSES)}).")
        if fields.get("Permisos", "").count("[X]") + fields.get("Permisos", "").count("[x]") < 3:
            result["errors"].append("Marca las tres casillas de permisos.")
        result.update(license=lic, form_title=fields.get("Título", "")[:48],
                      form_description=said(fields.get("Descripción", ""))[:300])
        result["ok"] = not result["errors"]
    (out / "result.json").write_text(json.dumps(result, ensure_ascii=False, indent=1))
    return result


def check_issue(out: Path, headless: Path) -> dict:
    fields = form_fields(os.environ.get("BODY", ""))
    urls = ATTACHMENT.findall(fields.get("El juego (.zip)", ""))
    out.mkdir(parents=True, exist_ok=True)
    if not urls:
        result = {"ok": False, "errors": ["No encuentro el .zip: arrástralo al campo «El juego (.zip)» del formulario "
                                            "o, si pesa más de 25 MB, pega ahí el enlace de descarga de una Release."]}
        (out / "result.json").write_text(json.dumps(result, ensure_ascii=False))
        return result
    zip_path = out / "sent.zip"
    with urllib.request.urlopen(urls[0], timeout=60) as r, open(zip_path, "wb") as f:  # noqa: S310 (host checked above)
        f.write(r.read(MAX_ZIP + 1))
    return check(zip_path, out, headless, fields)


def index() -> list[dict]:
    path = LIBRARY / "library.json"
    return json.loads(path.read_text()) if path.exists() else []


def publish(checked: Path, issue: int, author: str) -> str:
    result = json.loads((checked / "result.json").read_text())
    if not result.get("ok"):
        sys.exit("not published: the check did not pass")
    if not re.fullmatch(r"[A-Za-z0-9-]{1,39}", author):
        sys.exit(f"not published: odd GitHub login {author!r}")
    gid = result["id"]
    index_path = LIBRARY / "library.json"
    entries = index()
    old = next((e for e in entries if e["id"] == gid), None)
    if old and old["author"].lower() != author.lower():
        sys.exit(f"not published: the id {gid!r} is {old['author']}'s; change the id in game.json")
    dest = LIBRARY / gid
    dest.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as t:
        packed = pack_game.pack(checked / "game", Path(t), False)
        shutil.copy(packed, dest / "game.zip")
    if (checked / "cover.png").exists():
        shutil.copy(checked / "cover.png", dest / "cover.png")
    entry = {"id": gid, "title": result.get("form_title") or result["title"],
             "description": result.get("form_description") or result.get("description", ""),
             "author": author, "license": result.get("license", ""), "issue": issue, "date": date.today().isoformat(),
             "cover": (dest / "cover.png").exists()}
    entries = [entry] + [e for e in entries if e["id"] != gid]
    index_path.write_text(json.dumps(entries, ensure_ascii=False, indent=1) + "\n")
    return gid


def update(zip_path: Path, headless: Path, issue: int | None = None) -> str:
    """A new version of a game that is already in the Library. Its author, title, description and licence stay."""
    with tempfile.TemporaryDirectory() as t:
        checked = Path(t)
        result = check(zip_path, checked, headless)
        if not result.get("ok"):
            sys.exit("not updated: " + "; ".join(result.get("errors", [])))
        old = next((e for e in index() if e["id"] == result["id"]), None)
        if not old:
            sys.exit(f"not updated: {result['id']!r} is not in the Library; a new game goes through the form")
        result.update(form_title=old["title"], form_description=old["description"], license=old["license"])
        (checked / "result.json").write_text(json.dumps(result, ensure_ascii=False, indent=1))
        return publish(checked, old["issue"] if issue is None else issue, old["author"])


def comment(checked: Path) -> str:
    r = json.loads((checked / "result.json").read_text())
    if r.get("ok"):
        known = any(e["id"] == r["id"] for e in index())  # an id already in the Library: this is a new version
        return (f"**{r.get('form_title') or r.get('title')}** (`{r['id']}`) se abre y se juega diez segundos sin errores. "
                + ("Ya está en la Biblioteca: cuando lleve la etiqueta «aprobado» sustituirá a la versión anterior "
                   "(si es de otra cuenta, no se publicará: cambia el id en game.json)."
                   if known else "Ahora lo revisamos: cuando lleve la etiqueta «aprobado» se publica en la Biblioteca."))
    errors = "\n".join(f"- {e}" for e in r.get("errors", []))
    return ("El robot no ha podido aceptar el juego todavía:\n\n" + errors +
            "\n\nCorrígelo y edita este issue (por ejemplo, arrastra el .zip nuevo): se vuelve a comprobar solo.")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("check-issue", "check"):
        p = sub.add_parser(name)
        if name == "check":
            p.add_argument("zip", type=Path)
        p.add_argument("--out", type=Path, required=True)
        p.add_argument("--headless", type=Path, default=ROOT / "build" / "pinyol_headless")
    sub.add_parser("comment").add_argument("checked", type=Path)
    p = sub.add_parser("update")
    p.add_argument("zip", type=Path)
    p.add_argument("--headless", type=Path, default=ROOT / "build" / "pinyol_headless")
    p.add_argument("--issue", type=int)
    p = sub.add_parser("publish")
    p.add_argument("checked", type=Path)
    p.add_argument("--issue", type=int, required=True)
    p.add_argument("--author", required=True)
    a = ap.parse_args()
    if a.cmd == "comment":
        print(comment(a.checked))
        return
    if a.cmd == "publish":
        print(publish(a.checked, a.issue, a.author))
        return
    if a.cmd == "update":
        print(update(a.zip, a.headless, a.issue))
        print("Next: git add library && git commit && git push; then rebuild the site (uv run site/build.py) and publish "
              "gh-pages, so the game's own page shows the changes.", file=sys.stderr)
        return
    r = check_issue(a.out, a.headless) if a.cmd == "check-issue" else check(a.zip, a.out, a.headless)
    print(json.dumps(r, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
