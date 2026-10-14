"""tools/library.py on what people may send: a good game, a path that climbs out, a file that is no zip, a form.

    python3 tests/library_test.py build/pinyol_headless
"""
import json
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import library  # noqa: E402
import pack_game  # noqa: E402

headless = Path(sys.argv[1])
with tempfile.TemporaryDirectory() as t:
    t = Path(t)
    good = pack_game.pack(ROOT / "examples" / "bolsillo", t / "zips", False)
    r = library.check(good, t / "good", headless)
    assert r["ok"] and r["id"] == "bolsillo", r
    assert (t / "good" / "cover.png").exists() and (t / "good" / "game" / "game.json").exists()

    evil = t / "evil.zip"
    with zipfile.ZipFile(evil, "w") as z:
        z.writestr("juego/game.json", "{}")
        z.writestr("../../escape.lua", "print('out')")
    r = library.check(evil, t / "evil", headless)
    assert not r["ok"] and "Ruta no permitida" in r["errors"][0], r
    assert not (t / "escape.lua").exists() and not (t.parent / "escape.lua").exists()

    junk = t / "junk.zip"
    junk.write_text("not a zip")
    r = library.check(junk, t / "junk", headless)
    assert not r["ok"] and "no es un .zip" in r["errors"][0], r

    body = ("### Título\n\nMi juego\n\n### Descripción\n\nUn juego.\n\n### El juego (.zip)\n\n"
            "[j.zip](https://github.com/user-attachments/files/123/j.zip)\n\n### Licencia\n\nCC0\n\n"
            "### Permisos\n\n- [X] Es mío\n- [X] Acepto\n")
    f = library.form_fields(body)
    assert f["Título"] == "Mi juego" and f["Licencia"] == "CC0", f
    assert library.ATTACHMENT.findall(f["El juego (.zip)"]) == ["https://github.com/user-attachments/files/123/j.zip"]
    assert not library.ATTACHMENT.findall("https://evil.example/files/1/x.zip")
    r = library.check(good, t / "form", headless, f)
    assert r["ok"] and r["license"] == "CC0" and r["form_title"] == "Mi juego", r
    print(json.dumps({"library": "ok"}))
