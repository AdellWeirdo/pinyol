"""The font catalog (third_party/fonts/catalog.json, tools/font2fnt.py --pack): every font in it is there with its
licence beside it, every pack names fonts that exist, every pack makes three real .fnt files, and the engine loads and
draws each of them.

    python3 tests/fonts_test.py BP_HEADLESS OUT_DIR
"""
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import font2fnt  # noqa: E402

headless, out = sys.argv[1], Path(sys.argv[2])
shutil.rmtree(out, ignore_errors=True)
out.mkdir(parents=True)
failures = 0


def check(cond, what):
    global failures
    if not cond:
        failures += 1
        print("FAIL:", what)


cat = font2fnt.catalog()
fonts_dir = font2fnt.CATALOG.parent
check(len(cat["fonts"]) >= 40 and len(cat["packs"]) >= 30, "a catalog of fonts and packs (%d, %d)" % (len(cat["fonts"]), len(cat["packs"])))
for fid, f in cat["fonts"].items():
    path = fonts_dir / f["file"]
    check(path.exists(), f"{fid}: {f['file']} exists")
    check((path.parent / "OFL.txt").exists(), f"{fid}: OFL.txt beside it")
    check(f.get("name") and f.get("feel"), f"{fid}: a name and a feel")
for pid, pk in cat["packs"].items():
    check(set(pk["roles"]) == set(font2fnt.ROLES), f"{pid}: title, body and small")
    for role, spec in pk["roles"].items():
        check(spec["font"] in cat["fonts"], f"{pid}.{role}: font {spec['font']} is in the catalog")
        check(1 <= spec.get("scale", 1) <= 4, f"{pid}.{role}: a scale of 1 to 4")

# each pack made into a game of its own: three fonts, with ink, and the engine draws text in all three
text = 'text("Hamburgefonstiv ñ¿ 0123", 8, 8, {font = "%s"})\ntext("Hamburgefonstiv ñ¿ 0123", 8, 100, {font = "%s", scale = 1})\ntext("Hamburgefonstiv ñ¿ 0123", 8, 200, {font = "%s"})'
script = out / "draw.script"
script.write_text("new\ntick 3\nexpect_ok\n")
for pid in cat["packs"]:
    g = out / pid
    shutil.copytree(ROOT / "tests" / "games" / "turned" / "fonts", g / "fonts")  # (the four every game has)
    names = font2fnt.make_pack(pid, str(g))
    check(names == [f"{pid}_{r}" for r in font2fnt.ROLES], f"{pid}: its files are named by the pack")
    for n in names:
        blob = (g / "fonts" / f"{n}.fnt").read_bytes()
        cw, ch = blob[4], blob[5]
        stride = (cw + 7) // 8
        check(blob[:4] == b"FNT1" and cw > 0 and ch > 0, f"{n}: a FNT1 header")
        check(len(blob) == 8 + 256 + 256 * ch * stride, f"{n}: the size the format has")
        ink = any(blob[8 + 256 + (code * ch + y) * stride + x] for code in range(ord("A"), ord("Z") + 1)
                  for y in range(ch) for x in range(stride))
        check(ink, f"{n}: letters with ink")
    (g / "game.json").write_text('{"id": "%s", "title": "%s", "engine": "pinyol@2", "main": "main.lua"}' % (pid, pid))
    (g / "main.lua").write_text("function _init() show(0) end\nfunction _draw()\n" + text % tuple(names) + "\nend\n")
    r = subprocess.run([headless, "--game", str(g), "--saves", str(g / "saves"), "--fresh", "--script", str(script)],
                       capture_output=True, text=True)
    check(r.returncode == 0, f"{pid}: the engine draws with its fonts: {r.stdout[-300:]}{r.stderr[-300:]}")

print("fonts: %s (%d packs)" % ("ok" if not failures else "%d failed" % failures, len(cat["packs"])))
sys.exit(1 if failures else 0)
